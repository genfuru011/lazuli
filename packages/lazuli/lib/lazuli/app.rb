require "rack"
require "json"

require_relative "renderer"

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

      # RPC (JSON)
      if path == "__lazuli/rpc"
        return rpc_response(req)
      end

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

        resource = resource_class.new(merged_params, request: req)

        unless resource.respond_to?(action)
          allow = allowed_methods(resource, segments)
          headers = { "content-type" => "text/plain" }
          headers["allow"] = allow.join(", ") unless allow.empty?
          return [405, headers, ["Action not allowed: #{resource_name}##{action}"]]
        end

        result = resource.public_send(action)

        if result.is_a?(Array) && result.length == 3
          return result
        end

        [200, { "content-type" => "text/html" }, [result.to_s]]
      rescue NameError
        [404, { "content-type" => "text/plain" }, ["Resource not found: #{resource_name}"]]
      rescue Lazuli::RendererError => e
        status = e.status.to_i
        debug = ENV["LAZULI_DEBUG"] == "1"
        msg = if status >= 500 && !debug
          "Internal Server Error"
        else
          e.body.to_s.empty? ? e.message : e.body.to_s
        end
        msg = escape_html(msg)
        body = "<!DOCTYPE html><html><head><meta charset=\"utf-8\" /></head><body><pre>#{msg}</pre></body></html>"
        [status, { "content-type" => "text/html; charset=utf-8" }, [body]]
      rescue StandardError => e
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

    def allowed_methods(resource, segments)
      id_present = segments.length > 1 && !segments[1].to_s.empty?

      allow = []
      allow << "GET" if resource.respond_to?(id_present ? "show" : "index")
      allow << "POST" if resource.respond_to?("create")
      allow << "PUT" if resource.respond_to?("update")
      allow << "PATCH" if resource.respond_to?("update")
      allow << "DELETE" if resource.respond_to?("destroy")
      allow
    end

    def normalize_headers(headers)
      (headers || {}).transform_keys do |key|
        key.to_s.downcase
      end
    end

    def escape_html(s)
      s.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
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

    def rpc_response(req)
      origin = req.get_header("HTTP_ORIGIN").to_s
      if !origin.empty? && origin != req.base_url
        return [403, { "content-type" => "text/plain" }, ["Invalid Origin"]]
      end

      payload = JSON.parse(req.body.read.to_s) rescue nil
      return [400, { "content-type" => "text/plain" }, ["Invalid JSON"]] unless payload.is_a?(Hash)

      key = payload["key"].to_s
      params = payload["params"]
      resource_name, action = key.split("#", 2)
      return [400, { "content-type" => "text/plain" }, ["Invalid key"]] if resource_name.to_s.empty? || action.to_s.empty?

      resource_class = resolve_rpc_resource_class(resource_name)
      return [404, { "content-type" => "text/plain" }, ["Resource not found: #{resource_name}"]] unless resource_class

      defs = resource_class.respond_to?(:rpc_definitions) ? resource_class.rpc_definitions : {}
      rpc_def = defs[action.to_sym]
      return [404, { "content-type" => "text/plain" }, ["RPC not defined: #{key}"]] unless rpc_def

      if rpc_def.key?(:params)
        return [400, { "content-type" => "text/plain" }, ["Invalid params (expected object)"]] unless params.is_a?(Hash)
        expected = rpc_def[:params]
        unless validate_rpc_params(expected, params)
          return [400, { "content-type" => "text/plain" }, ["Invalid params for #{key}"]]
        end
      end

      rpc_params = (params.is_a?(Hash) ? params : {}).transform_keys { |k| k.to_s.to_sym }
      resource = resource_class.new(rpc_params, request: req)

      unless resource.respond_to?(action)
        return [404, { "content-type" => "text/plain" }, ["Action not found: #{key}"]]
      end

      result = resource.public_send(action)
      if result.is_a?(Array) && result.length == 3
        return [500, { "content-type" => "text/plain" }, ["RPC actions must return a JSON-serializable object, not a Rack response"]]
      end

      json = JSON.generate(normalize_json_value(result))
      [200, { "content-type" => "application/json" }, [json]]
    rescue StandardError => e
      [500, { "content-type" => "text/plain" }, ["RPC error: #{e.message}"]]
    end

    def resolve_rpc_resource_class(resource_key)
      # Back-compat: allow old keys like "UsersResource" or "Admin::UsersResource".
      if resource_key.include?("::") || resource_key.end_with?("Resource")
        begin
          return Object.const_get(resource_key)
        rescue NameError
        end
      end

      # New default: path-like keys ("users", "admin/users").
      segments = resource_key.to_s.split("/")
      return nil if segments.empty?

      modules = segments[0...-1].map { |s| camelize(s) }
      klass = "#{camelize(segments[-1])}Resource"
      const_name = (modules + [klass]).join("::")

      begin
        return Object.const_get(const_name)
      rescue NameError
      end

      # Last resort: scan loaded resources.
      ObjectSpace.each_object(Class).find do |c|
        defined?(Lazuli::Resource) && c < Lazuli::Resource && c.respond_to?(:rpc_key) && c.rpc_key == resource_key
      end
    end

    def camelize(s)
      s.to_s.split("_").map { |p| p.empty? ? p : p[0].upcase + p[1..] }.join
    end

    def validate_rpc_params(expected, value)
      return true if expected.nil?

      if defined?(Lazuli::Types)
        if expected.is_a?(Lazuli::Types::Nilable)
          return true if value.nil?
          return validate_rpc_params(expected.type, value)
        end

        if expected.is_a?(Lazuli::Types::ArrayOf)
          return false unless value.is_a?(Array)
          return value.all? { |v| validate_rpc_params(expected.type, v) }
        end

        if expected.is_a?(Lazuli::Types::Union)
          return expected.types.any? { |t| validate_rpc_params(t, value) }
        end
      end

      # Back-compat: Array means array-of, optionally nullable.
      if expected.is_a?(Array)
        return true if expected.include?(NilClass) && value.nil?
        return false unless value.is_a?(Array)
        inner = expected.reject { |t| t == NilClass }
        return value.all? { |v| inner.any? { |t| validate_rpc_params(t, v) } }
      end

      return value.nil? if expected == NilClass

      if defined?(Lazuli::Struct) && expected.respond_to?(:<) && (expected < Lazuli::Struct)
        return false unless value.is_a?(Hash)

        expected.schema.each do |k, t|
          v = value.key?(k.to_s) ? value[k.to_s] : value[k]
          return false unless validate_rpc_params(t, v)
        end
        return true
      end

      case expected
      when String
        value.is_a?(String)
      when Integer
        value.is_a?(Integer)
      when Float, Numeric
        value.is_a?(Numeric)
      when TrueClass, FalseClass
        value == true || value == false
      else
        if expected.is_a?(Class)
          value.is_a?(expected)
        else
          true
        end
      end
    end

    def normalize_json_value(value)
      if value.is_a?(Hash)
        value.transform_values { |v| normalize_json_value(v) }
      elsif value.is_a?(Array)
        value.map { |v| normalize_json_value(v) }
      elsif value.respond_to?(:to_h)
        normalize_json_value(value.to_h)
      else
        value
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
