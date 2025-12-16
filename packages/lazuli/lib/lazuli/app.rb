require "rack"

module Lazuli
  class App
    def initialize(root: nil, socket: nil)
      @app_root = File.expand_path(root || ENV["LAZULI_APP_ROOT"] || Dir.pwd)
      ENV["LAZULI_APP_ROOT"] ||= @app_root
      Lazuli::Renderer.configure(socket_path: socket)
      start_deno_process
    end

    def call(env)
      req = Rack::Request.new(env)
      path = req.path_info
      
      # Remove leading slash
      path = path[1..-1] if path.start_with?("/")

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
        resource = resource_class.new(req.params)

        unless resource.respond_to?(action)
          return [404, { "content-type" => "text/plain" }, ["Action not found: #{resource_name}##{action}"]]
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

    def start_deno_process
      # TODO: Implement process management
      # For now, we assume the user started Deno manually or we print instructions
      puts "[Lazuli] Ensure Deno renderer is running on #{Lazuli::Renderer.socket_path}"
    end
  end
end
