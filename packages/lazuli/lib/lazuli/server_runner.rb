require "fileutils"
require "timeout"
require "socket"

require_relative "type_generator"

module Lazuli
  class ServerRunner
    DEFAULT_PORT = 9292

    def initialize(app_root:, socket:, port: DEFAULT_PORT, reload: false, rack_server: nil, yjit: false)
      @app_root = File.expand_path(app_root)
      @socket_path = File.expand_path(socket || File.join(@app_root, "tmp", "sockets", "lazuli-renderer.sock"))
      @reload_token_path = File.join(@app_root, "tmp", "lazuli_reload_token")
      @port = port || DEFAULT_PORT
      @reload = reload
      @rack_server = (rack_server || ENV["LAZULI_RACK_SERVER"] || :rackup).to_sym
      @yjit = yjit || ENV["LAZULI_YJIT"] == "1"
      @pids = {}
      @quiet = ENV["LAZULI_QUIET"] == "1"
      @start_retries = (ENV["LAZULI_START_RETRIES"] || "2").to_i
      @start_timeout = (ENV["LAZULI_START_TIMEOUT"] || "5").to_f
    end

    def start
      FileUtils.mkdir_p(File.dirname(@socket_path))
      FileUtils.mkdir_p(File.dirname(@reload_token_path))
      ENV["LAZULI_APP_ROOT"] = @app_root
      ENV["LAZULI_SOCKET"] = @socket_path
      ENV["LAZULI_RELOAD_ENABLED"] = @reload ? "1" : nil
      ENV["LAZULI_RELOAD_TOKEN_PATH"] = @reload_token_path

      bump_reload_token if @reload

      @shutdown_requested = false

      start_processes
      start_watcher if @reload
      trap_signals
      at_exit { stop_all }

      loop do
        break if @shutdown_requested
        sleep 0.5
      end

      stop_all
    end

    private

    def start_processes
      stop_process(:deno)
      stop_process(:rack)

      generate_types

      token = current_reload_token
      ENV["LAZULI_RELOAD_TOKEN"] = token if @reload

      deno = ENV["LAZULI_DENO"] || ENV["DENO"]
      deno ||= begin
        candidate = File.expand_path("~/.deno/bin/deno")
        File.exist?(candidate) ? candidate : "deno"
      end

      deno_cmd = [
        deno, "run", "-A", "--unstable-net",
        "--config", File.join(@app_root, "deno.json"),
        adapter_path,
        "--app-root", @app_root,
        "--socket", @socket_path
      ]

      if @rack_server == :falcon
        begin
          Gem::Specification.find_by_name("falcon")
        rescue Gem::LoadError
          warn "[Lazuli] falcon gem not found; falling back to rackup"
          @rack_server = :rackup
        end
      end

      rack_cmd = case @rack_server
      when :falcon
        ["bundle", "exec", "falcon", "serve", "--bind", "http://0.0.0.0:#{@port}"]
      else
        ["bundle", "exec", "rackup", "-p", @port.to_s]
      end

      log "[Lazuli] Starting Deno adapter..."
      deno_env = {
        "LAZULI_APP_ROOT" => @app_root,
        "LAZULI_SOCKET" => @socket_path,
        "LAZULI_RELOAD_TOKEN" => token,
        "LAZULI_RELOAD_ENABLED" => @reload ? "1" : nil,
        "LAZULI_RELOAD_TOKEN_PATH" => @reload_token_path
      }.compact
      @pids[:deno] = spawn_with_retry(:deno) do
        Process.spawn(deno_env, *deno_cmd, chdir: @app_root, out: $stdout, err: $stderr, pgroup: true)
      end
      debug "[Lazuli] Deno PID: #{@pids[:deno]}"

      log "[Lazuli] Starting Rack server on port #{@port}..."

      rack_env = {
        "LAZULI_APP_ROOT" => @app_root,
        "LAZULI_SOCKET" => @socket_path,
        "LAZULI_RELOAD_TOKEN" => token,
        "LAZULI_RELOAD_ENABLED" => @reload ? "1" : nil,
        "LAZULI_RELOAD_TOKEN_PATH" => @reload_token_path
      }.compact

      if @yjit
        rack_env["RUBYOPT"] = [ENV["RUBYOPT"], "--yjit"].compact.join(" ")
      end

      @pids[:rack] = spawn_with_retry(:rack) do
        Process.spawn(
          rack_env,
          *rack_cmd,
          chdir: @app_root,
          out: $stdout,
          err: $stderr,
          pgroup: true
        )
      end
      debug "[Lazuli] Rack PID: #{@pids[:rack]}"
    end

    def start_watcher
      @watcher_thread = Thread.new do
        previous = checksum
        loop do
          sleep 1.0
          current = checksum
          next if current == previous
          previous = current
          log "[Lazuli] Change detected. Reloading..."
          generate_types
          bump_reload_token
        end
      end
    end

    def checksum
      files = Dir[File.join(@app_root, "app", "**", "*.{rb,ts,tsx,js,jsx}")].sort
      files += Dir[File.join(@app_root, "config", "**", "*")].sort
      files << File.join(@app_root, "deno.json")
      files.compact!
      stats = files.map { |f| File.mtime(f).to_f rescue 0 }
      stats.join(":")
    end

    def trap_signals
      %w[INT TERM].each do |sig|
        Signal.trap(sig) do
          log "[Lazuli] Shutting down..."
          @shutdown_requested = true
        end
      end
    end

    def stop_all
      stop_process(:deno)
      stop_process(:rack)
      @watcher_thread&.kill
      begin
        File.delete(@socket_path) if File.exist?(@socket_path)
      rescue StandardError
      end
      begin
        File.delete(@reload_token_path) if File.exist?(@reload_token_path)
      rescue StandardError
      end
    end

    def stop_process(key)
      pid = @pids[key]
      return unless pid

      stop_pid(pid)
      @pids[key] = nil
    end

    def stop_pid(pid)
      pgid = begin
        Process.getpgid(pid)
      rescue StandardError
        pid
      end

      begin
        Process.kill("TERM", -pgid)
      rescue Errno::ESRCH
      end

      begin
        Timeout.timeout(5) { Process.wait(pid) }
      rescue Timeout::Error
        begin
          Process.kill("KILL", -pgid)
        rescue Errno::ESRCH
        end
        begin
          Process.wait(pid)
        rescue Errno::ECHILD
        end
      rescue Errno::ECHILD
      ensure
        begin
          Process.kill(0, -pgid)
          Process.kill("KILL", -pgid)
        rescue Errno::ESRCH
        rescue Errno::EPERM
        end
      end
    end

    def spawn_with_retry(key)
      attempts = 0
      pid = nil

      begin
        attempts += 1
        pid = yield
        wait_for_renderer_socket if key == :deno
        pid
      rescue StandardError => e
        warn "[Lazuli] #{key} failed to start: #{e.message}"
        stop_pid(pid) if pid
        retry if attempts <= @start_retries
        raise
      end
    end

    def wait_for_renderer_socket
      deadline = Time.now + @start_timeout

      loop do
        begin
          sock = UNIXSocket.new(@socket_path)
          sock.close
          return
        rescue Errno::ENOENT, Errno::ECONNREFUSED
        end

        raise "Renderer socket not ready" if Time.now >= deadline
        sleep 0.05
      end
    end

    def log(msg)
      puts msg unless @quiet
    end

    def debug(msg)
      puts msg if ENV["LAZULI_DEBUG"] == "1"
    end

    def generate_types
      out_path = File.join(@app_root, "client.d.ts")
      Lazuli::TypeGenerator.generate(app_root: @app_root, out_path: out_path)
    rescue StandardError => e
      warn "[Lazuli] Type generation failed: #{e.message}"
    end

    def current_reload_token
      File.read(@reload_token_path).to_s.strip
    rescue StandardError
      ""
    end

    def bump_reload_token
      token = Time.now.to_f.to_s
      File.write(@reload_token_path, token)
      ENV["LAZULI_RELOAD_TOKEN"] = token
    rescue StandardError => e
      warn "[Lazuli] Reload token update failed: #{e.message}"
    end

    def adapter_path
      File.expand_path("../../assets/adapter/server.tsx", __dir__)
    end
  end
end
