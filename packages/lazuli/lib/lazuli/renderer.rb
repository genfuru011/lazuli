require "socket"

require_relative "json"

module Lazuli
  class Error < StandardError; end unless const_defined?(:Error)

  class RendererError < Lazuli::Error
    attr_reader :status, :body

    def initialize(status:, body:, message:)
      @status = status
      @body = body
      super(message)
    end
  end

  class Renderer
    class Rendered
      attr_reader :body, :headers

      def initialize(body:, headers: {})
        @body = body.to_s
        @headers = headers
      end

      def to_s
        @body
      end
    end
    DEFAULT_SOCKET_PATH = File.expand_path(
      ENV["LAZULI_SOCKET"] ||
      File.join(ENV["LAZULI_APP_ROOT"] || Dir.pwd, "tmp", "sockets", "lazuli-renderer.sock")
    )

    def self.render_response(path, payload)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = new.post(path, payload)
      dt_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
      response[:timings_ms] = { ipc: dt_ms }
      response
    end

    def self.rendered(page, props)
      response = render_response("/render", { page: page, props: props })
      if response[:status] && response[:status] >= 400
        raise Lazuli::RendererError.new(
          status: response[:status],
          body: response[:body],
          message: "Render failed (#{response[:status]}): #{response[:body]}"
        )
      end

      server_timing = []
      if (ipc = response.dig(:timings_ms, :ipc))
        server_timing << format("ipc;dur=%.1f", ipc)
      end
      if (deno = response.dig(:headers, "server-timing"))
        server_timing << deno
      end

      Rendered.new(
        body: response[:body],
        headers: server_timing.empty? ? {} : { "server-timing" => server_timing.join(", ") }
      )
    end

    def self.render(page, props)
      rendered(page, props).body
    end

    def self.render_turbo_stream_rendered(operations)
      response = render_response("/render_turbo_stream", { streams: operations })
      if response[:status] && response[:status] >= 400
        raise Lazuli::RendererError.new(
          status: response[:status],
          body: response[:body],
          message: "Turbo Stream render failed (#{response[:status]}): #{response[:body]}"
        )
      end

      server_timing = []
      if (ipc = response.dig(:timings_ms, :ipc))
        server_timing << format("ipc;dur=%.1f", ipc)
      end
      if (deno = response.dig(:headers, "server-timing"))
        server_timing << deno
      end

      Rendered.new(
        body: response[:body],
        headers: server_timing.empty? ? {} : { "server-timing" => server_timing.join(", ") }
      )
    end

    def self.render_turbo_stream(operations)
      render_turbo_stream_rendered(operations).body
    end

    def self.asset(path)
      new.get(path)
    end

    def self.configure(socket_path: nil)
      @socket_path = socket_path if socket_path
    end

    def self.socket_path
      @socket_path || DEFAULT_SOCKET_PATH
    end

    def post(path, data)
      request("POST", path, Lazuli::Json.dump(data))
    end

    def get(path)
      request("GET", path)
    end

    private

    def request(method, path, body = nil)
      attempt = 0

      begin
        attempt += 1
        sock = checkout_socket

        req = "#{method} #{path} HTTP/1.1\r\n" \
              "Host: localhost\r\n" \
              "Connection: keep-alive\r\n"

        if body
          req += "Content-Type: application/json\r\n" \
                 "Content-Length: #{body.bytesize}\r\n"
        end

        req += "\r\n"
        req += body if body

        sock.write(req)

        headers_raw, rest = read_headers(sock)
        status, headers = parse_headers(headers_raw)
        response_body, keep_alive = read_body(sock, headers, rest)

        release_socket(sock, keep_alive)
        { status: status, headers: headers, body: response_body }
      rescue Errno::ENOENT, Errno::ECONNREFUSED
        {
          status: 502,
          headers: {},
          body: "Lazuli Renderer Error: Could not connect to Deno renderer at #{self.class.socket_path}"
        }
      rescue StandardError
        reset_socket
        retry if attempt < 2
        raise
      end
    end

    def socket_pool
      Thread.current[:__lazuli_renderer_socket_pool__] ||= {}
    end

    def pool_key
      if defined?(Fiber) && Fiber.respond_to?(:scheduler) && Fiber.scheduler
        Fiber.current.object_id
      else
        :thread
      end
    end

    def socket_key
      [self.class.socket_path, pool_key]
    end

    def checkout_socket
      sock = socket_pool[socket_key]
      return sock if sock

      sock = UNIXSocket.new(self.class.socket_path)
      socket_pool[socket_key] = sock
      sock
    end

    def release_socket(sock, keep_alive)
      return if keep_alive

      reset_socket
      sock.close rescue nil
    end

    def reset_socket
      sock = socket_pool.delete(socket_key)
      sock&.close rescue nil
    end

    def read_headers(sock)
      buffer = +""
      delimiter = "\r\n\r\n"

      until (idx = buffer.index(delimiter))
        buffer << sock.readpartial(4096)
      end

      headers_raw = buffer[0...idx]
      rest = buffer[(idx + delimiter.bytesize)..] || ""
      [headers_raw, rest]
    end

    def parse_headers(headers_raw)
      status = 500
      headers = {}

      header_lines = headers_raw.split("\r\n")
      status_line = header_lines.shift
      if status_line && status_line =~ %r{HTTP/\d\.\d\s+(\d+)}
        status = Regexp.last_match(1).to_i
      end
      header_lines.each do |line|
        key, value = line.split(": ", 2)
        headers[key.downcase] = value if key && value
      end

      [status, headers]
    end

    def read_body(sock, headers, rest)
      connection = headers["connection"].to_s.downcase
      keep_alive = connection != "close"

      if headers["transfer-encoding"].to_s.downcase.include?("chunked")
        body = read_chunked_body(sock, rest)
        return [body, keep_alive]
      end

      content_length = headers["content-length"]
      if content_length
        len = content_length.to_i
        body = rest.byteslice(0, len) || ""
        while body.bytesize < len
          body << sock.readpartial(len - body.bytesize)
        end
        return [body, keep_alive]
      end

      keep_alive = false
      [rest + sock.read.to_s, keep_alive]
    end

    def read_chunked_body(sock, rest)
      buffer = rest.dup
      out = +""

      loop do
        line = read_line(sock, buffer)
        size = line.to_s.strip.to_i(16)
        break if size == 0

        out << read_bytes(sock, buffer, size)
        read_bytes(sock, buffer, 2) # \r\n
      end

      read_line(sock, buffer) # trailing \r\n
      out
    end

    def read_line(sock, buffer)
      delimiter = "\r\n"
      until (idx = buffer.index(delimiter))
        buffer << sock.readpartial(4096)
      end
      line = buffer.slice!(0, idx)
      buffer.slice!(0, delimiter.bytesize)
      line
    end

    def read_bytes(sock, buffer, n)
      while buffer.bytesize < n
        buffer << sock.readpartial(4096)
      end
      buffer.slice!(0, n)
    end
  end
end
