module Lazuli
  class Resource
    attr_reader :params, :request

    def initialize(params = {}, request: nil)
      @params = params
      @request = request
    end

    def self.rpc(name, options = {})
      @rpc_definitions ||= {}
      @rpc_definitions[name.to_sym] = options
    end

    def self.rpc_definitions
      @rpc_definitions || {}
    end

    # Helper to render a page
    # Usage: Render "users/index", users: users
    def Render(page, props = {})
      Lazuli::Renderer.render(page, normalize_value(props))
    end

    def turbo_stream?
      # Turbo uses Accept: text/vnd.turbo-stream.html for stream responses.
      accept = request&.get_header("HTTP_ACCEPT").to_s
      return true if accept.include?("text/vnd.turbo-stream.html")

      # Fallback for manual testing / non-browser clients.
      params[:format].to_s == "turbo_stream"
    end

    def turbo_stream
      stream = Lazuli::TurboStream.new
      yield stream
      body = Lazuli::Renderer.render_turbo_stream(normalize_value(stream.operations))
      [200, { "content-type" => "text/vnd.turbo-stream.html", "vary" => "accept" }, [body]]
    end

    def redirect_to(location, status: 303)
      [status, { "location" => location, "content-type" => "text/plain" }, ["Redirecting to #{location}"]]
    end

    private

    def normalize_value(value)
      if value.is_a?(Hash)
        value.transform_values { |v| normalize_value(v) }
      elsif value.is_a?(Array)
        value.map { |v| normalize_value(v) }
      elsif value.respond_to?(:to_h)
        normalize_value(value.to_h)
      else
        value
      end
    end
  end
end
