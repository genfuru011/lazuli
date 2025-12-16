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

    TURBO_STREAM_MIME = "text/vnd.turbo-stream.html"

    def turbo_stream?
      # Turbo uses Accept: text/vnd.turbo-stream.html for stream responses.
      accept = request&.get_header("HTTP_ACCEPT").to_s
      return true if accepts_mime?(accept, TURBO_STREAM_MIME)

      # Fallback for manual testing / non-browser clients.
      fmt = params[:format].to_s
      fmt == "turbo_stream" || fmt == "turbo-stream"
    end

    def turbo_stream
      stream = Lazuli::TurboStream.new
      yield stream

      begin
        body = Lazuli::Renderer.render_turbo_stream(normalize_value(stream.operations))
        return [200, { "content-type" => "text/vnd.turbo-stream.html; charset=utf-8", "vary" => "accept" }, [body]]
      rescue StandardError => e
        status = (e.message.to_s[/\((\d{3})\)/, 1] || "500").to_i
        status = 500 if status < 400 || status > 599

        msg = escape_html(e.message)
        body = %(<turbo-stream action="update" target="flash"><template><pre>#{msg}</pre></template></turbo-stream>)
        return [status, { "content-type" => "text/vnd.turbo-stream.html; charset=utf-8", "vary" => "accept" }, [body]]
      end
    end

    def escape_html(s)
      s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end

    def redirect_to(location, status: nil)
      status ||= begin
        method = request&.request_method.to_s
        method == "GET" ? 302 : 303
      rescue StandardError
        303
      end

      [status, { "location" => location, "content-type" => "text/plain" }, ["Redirecting to #{location}"]]
    end

    private

    def accepts_mime?(accept, mime)
      return false if accept.nil? || accept.strip.empty?

      accept.split(",").any? do |part|
        type, *params = part.strip.split(";")
        next false unless type.strip == mime

        q = 1.0
        params.each do |p|
          k, v = p.strip.split("=", 2)
          next unless k == "q"
          q = v.to_f
        end

        q > 0
      end
    end

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
