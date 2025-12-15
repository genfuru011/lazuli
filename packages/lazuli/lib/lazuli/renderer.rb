require "socket"
require "json"
require "net/http"

module Lazuli
  class Renderer
    SOCKET_PATH = "tmp/sockets/lazuli-renderer.sock"

    def self.render(page, props)
      new.post("/render", { page: page, props: props })
    end

    def self.asset(path)
      new.get(path)
    end

    def post(path, data)
      request("POST", path, data.to_json)
    end

    def get(path)
      request("GET", path)
    end

    private

    def request(method, path, body = nil)
      begin
        sock = UNIXSocket.new(SOCKET_PATH)
        
        req = "#{method} #{path} HTTP/1.1\r\n" \
              "Host: localhost\r\n" \
              "Connection: close\r\n"
        
        if body
          req += "Content-Type: application/json\r\n" \
                 "Content-Length: #{body.bytesize}\r\n"
        end
        
        req += "\r\n"
        req += body if body
        
        sock.write(req)
        
        # Read response
        response = sock.read
        sock.close
        
        # Extract body (very naive parsing)
        # In a real app, we should parse headers to get Content-Type, etc.
        _headers, body = response.split("\r\n\r\n", 2)
        body
      rescue Errno::ENOENT, Errno::ECONNREFUSED
        "Lazuli Renderer Error: Could not connect to Deno renderer at #{SOCKET_PATH}"
      end
    end
  end
end
