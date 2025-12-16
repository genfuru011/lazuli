require "fileutils"

require_relative "type_generator"

module Lazuli
  class ServerRunner
    DEFAULT_PORT = 9292

    def initialize(app_root:, socket:, port: DEFAULT_PORT, reload: false)
      @app_root = File.expand_path(app_root)
      @socket_path = File.expand_path(socket || File.join(@app_root, "tmp", "sockets", "lazuli-renderer.sock"))
      @port = port || DEFAULT_PORT
      @reload = reload
      @pids = {}
    end

    def start
      FileUtils.mkdir_p(File.dirname(@socket_path))
      ENV["LAZULI_APP_ROOT"] = @app_root
      ENV["LAZULI_SOCKET"] = @socket_path

      start_processes
      start_watcher if @reload
      trap_signals
      sleep
    end

    private

    def start_processes
      stop_process(:deno)
      stop_process(:rack)

      generate_types

      token = Time.now.to_f.to_s
      ENV["LAZULI_RELOAD_TOKEN"] = token if @reload
      ENV["LAZULI_RELOAD_ENABLED"] = @reload ? "1" : nil

      deno_cmd = [
        "deno", "run", "-A", "--unstable-net",
        "--config", File.join(@app_root, "deno.json"),
        adapter_path,
        "--app-root", @app_root,
        "--socket", @socket_path
      ]

      rack_cmd = [
        "bundle", "exec", "rackup", "-p", @port.to_s
      ]

      puts "[Lazuli] Starting Deno adapter..."
      deno_env = {
        "LAZULI_APP_ROOT" => @app_root,
        "LAZULI_SOCKET" => @socket_path,
        "LAZULI_RELOAD_TOKEN" => token,
        "LAZULI_RELOAD_ENABLED" => @reload ? "1" : nil
      }.compact
      @pids[:deno] = Process.spawn(deno_env, *deno_cmd, chdir: @app_root, out: $stdout, err: $stderr)
      puts "[Lazuli] Deno PID: #{@pids[:deno]}"

      puts "[Lazuli] Starting Rack server on port #{@port}..."
      @pids[:rack] = Process.spawn(
        {
          "LAZULI_APP_ROOT" => @app_root,
          "LAZULI_SOCKET" => @socket_path,
          "LAZULI_RELOAD_TOKEN" => token,
          "LAZULI_RELOAD_ENABLED" => @reload ? "1" : nil
        },
        *rack_cmd,
        chdir: @app_root,
        out: $stdout,
        err: $stderr
      )
      puts "[Lazuli] Rack PID: #{@pids[:rack]}"
    end

    def start_watcher
      @watcher_thread = Thread.new do
        previous = checksum
        loop do
          sleep 1.5
          current = checksum
          next if current == previous
          previous = current
          puts "[Lazuli] Change detected. Restarting servers..."
          start_processes
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
          puts "[Lazuli] Shutting down..."
          stop_all
          exit
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
    end

    def stop_process(key)
      pid = @pids[key]
      return unless pid
      begin
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
      ensure
        @pids[key] = nil
      end
    end

    def generate_types
      out_path = File.join(@app_root, "client.d.ts")
      Lazuli::TypeGenerator.generate(app_root: @app_root, out_path: out_path)
    rescue StandardError => e
      warn "[Lazuli] Type generation failed: #{e.message}"
    end

    def adapter_path
      File.expand_path("../../assets/adapter/server.tsx", __dir__)
    end
  end
end
