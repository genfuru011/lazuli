module Lazuli
  class Resource
    attr_reader :params, :request

    def initialize(params = {}, request: nil)
      @params = params
      @request = request
    end

    # Stable key used by Lazuli RPC. Default: class name -> path-like key.
    #   UsersResource       => "users"
    #   Admin::UsersResource => "admin/users"
    def self.rpc_key
      @rpc_key ||= begin
        n = name.to_s
        if n.empty?
          n
        else
          parts = n.split("::").map do |part|
            base = part.sub(/Resource\z/, "")
            underscore(base)
          end
          parts.join("/")
        end
      end
    end

    def self.rpc_key=(value)
      @rpc_key = value.to_s
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

    def turbo_stream(error_target: "flash", error_targets: nil)
      stream = Lazuli::TurboStream.new
      yield stream

      begin
        body = Lazuli::Renderer.render_turbo_stream(normalize_value(stream.operations))
        return [200, { "content-type" => "text/vnd.turbo-stream.html; charset=utf-8", "vary" => "accept" }, [body]]
      rescue Lazuli::RendererError => e
        status = e.status.to_i
        msg = if status >= 500 && ENV["LAZULI_DEBUG"] != "1"
          "Internal Server Error"
        else
          (e.body.to_s.empty? ? e.message : e.body.to_s)
        end
        msg = escape_html(msg)
      rescue StandardError => e
        status = 500
        msg = ENV["LAZULI_DEBUG"] == "1" ? e.message : "Internal Server Error"
        msg = escape_html(msg)
      end

      selector_attr = if error_targets
        %(targets="#{escape_html(error_targets)}")
      else
        %(target="#{escape_html(error_target)}")
      end

      body = %(<turbo-stream action="update" #{selector_attr}><template><pre>#{msg}</pre></template></turbo-stream>)
      [status, { "content-type" => "text/vnd.turbo-stream.html; charset=utf-8", "vary" => "accept" }, [body]]
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

    def self.underscore(s)
      s.to_s
        .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
        .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
        .downcase
    end
    private_class_method :underscore
  end
end
