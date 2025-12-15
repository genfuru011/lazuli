require "rack"

module Lazuli
  class App
    def initialize
      start_deno_process
    end

    def call(env)
      req = Rack::Request.new(env)
      path = req.path_info

      # Simple routing: /users -> UsersResource#index
      # Remove leading slash
      path = path[1..-1] if path.start_with?("/")
      path = "home" if path.empty?

      resource_name = "#{path.capitalize}Resource"
      
      begin
        # Try to find the resource class
        # In a real app, we would autoload these
        resource_class = Object.const_get(resource_name)
        resource = resource_class.new(req.params)
        
        # Assume 'index' action for now
        html = resource.index
        
        [200, { "content-type" => "text/html" }, [html]]
      rescue NameError
        [404, { "content-type" => "text/plain" }, ["Resource not found: #{resource_name}"]]
      rescue => e
        [500, { "content-type" => "text/plain" }, ["Internal Server Error: #{e.message}"]]
      end
    end

    private

    def start_deno_process
      # TODO: Implement process management
      # For now, we assume the user started Deno manually or we print instructions
      puts "[Lazuli] Ensure Deno renderer is running on #{Lazuli::Renderer::SOCKET_PATH}"
    end
  end
end
