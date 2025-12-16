require "rack"

module Lazuli
  class App
    def initialize(root: nil, socket: nil)
      @app_root = File.expand_path(root || ENV["LAZULI_APP_ROOT"] || Dir.pwd)
      ENV["LAZULI_APP_ROOT"] ||= @app_root
      @reload_enabled = ENV["LAZULI_RELOAD_ENABLED"] == "1"
      @reload_token_path = ENV["LAZULI_RELOAD_TOKEN_PATH"] || File.join(@app_root, "tmp", "lazuli_reload_token")
      @reload_mtimes = {}
      Lazuli::Renderer.configure(socket_path: socket)
      # Deno process is managed by Lazuli::ServerRunner (CLI). Lazuli::App is a plain Rack app.
    end

    def call(env)
      reload_app_code! if @reload_enabled

      req = Rack::Request.new(env)
      path = req.path_info
      
      # Remove leading slash
      path = path[1..-1] if path.start_with?("/")

      # Live Reload (SSE)
      if path == "__lazuli/events"
        return sse_response
      end

      # Asset/Dev Proxy
      if path.start_with?("assets/") || path.start_with?("__lazuli/")
        response = Lazuli::Renderer.asset("/" + path)
        status = response[:status] || 500
        headers = normalize_headers(response[:headers])
        headers["content-type"] ||= content_type_for(path)
        body = response[:body].to_s
        return [status, headers, [body]]
      end

      # Simple routing: /users -> UsersResource#index
      path = "home" if path.empty?

      segments = path.split("/")
      resource_name = "#{segments.first.capitalize}Resource"
      action = resolve_action(req.request_method, segments)
      
      begin
        # Try to find the resource class
        # In a real app, we would autoload these
        resource_class = Object.const_get(resource_name)

        # Merge Rack params with path params (/users/:id) and normalize keys to symbols.
        merged_params = req.params.dup
        merged_params["id"] ||= segments[1] if segments.length > 1 && !segments[1].to_s.empty?
        merged_params = merged_params.transform_keys { |k| k.to_s.to_sym }

        resource = resource_class.new(merged_params)

        unless resource.respond_to?(action)
          return [405, { "content-type" => "text/plain" }, ["Action not allowed: #{resource_name}##{action}"]]
        end

        html = resource.public_send(action)
        
        [200, { "content-type" => "text/html" }, [html]]
      rescue NameError
        [404, { "content-type" => "text/plain" }, ["Resource not found: #{resource_name}"]]
      rescue => e
        [500, { "content-type" => "text/plain" }, ["Internal Server Error: #{e.message}"]]
      end
    end

    private

    def resolve_action(method, segments)
      id_present = segments.length > 1 && !segments[1].to_s.empty?
      case method
      when "GET"
        id_present ? "show" : "index"
      when "POST"
        "create"
      when "PUT", "PATCH"
        "update"
      when "DELETE"
        "destroy"
      else
        "index"
      end
    end

    def normalize_headers(headers)
      (headers || {}).transform_keys do |key|
        key.to_s.downcase
      end
    end

    def content_type_for(path)
      case File.extname(path)
      when ".js", ".mjs", ".ts", ".tsx"
        "application/javascript"
      when ".css"
        "text/css"
      when ".json"
        "application/json"
      when ".svg"
        "image/svg+xml"
      when ".png"
        "image/png"
      when ".jpg", ".jpeg"
        "image/jpeg"
      else
        "application/octet-stream"
      end
    end

    def sse_response
      headers = {
        "content-type" => "text/event-stream",
        "cache-control" => "no-cache",
        "connection" => "keep-alive",
      }

      body = Enumerator.new do |y|
        last = read_reload_token
        y << "data: #{last}\n\n"

        ticks = 0
        loop do
          sleep 0.5
          ticks += 1

          current = read_reload_token
          if current != last
            last = current
            y << "data: #{last}\n\n"
          elsif ticks % 30 == 0
            y << ": keep-alive\n\n"
          end
        end
      end

      [200, headers, body]
    end

    def read_reload_token
      File.read(@reload_token_path).to_s.strip
    rescue StandardError
      ENV["LAZULI_RELOAD_TOKEN"].to_s
    end

    def reload_app_code!
      app_glob = File.join(@app_root, "app", "**", "*.rb")
      Dir[app_glob].sort.each do |file|
        mtime = File.mtime(file).to_f rescue 0
        next if @reload_mtimes[file] && @reload_mtimes[file] >= mtime
        load file
        @reload_mtimes[file] = mtime
      end
    rescue StandardError => e
      warn "[Lazuli] Code reload failed: #{e.message}"
    end

    def start_deno_process
      # Reserved for a future opt-in mode where Lazuli::App can manage the Deno process.
      # Current default: Lazuli::ServerRunner (CLI) manages it.
    end
  end
end
