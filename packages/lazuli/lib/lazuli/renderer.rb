require "socket"
require "json"
require "net/http"

module Lazuli
  class Renderer
    SOCKET_PATH = "tmp/sockets/lazuli-renderer.sock"

    def self.render(page, props)
      new.call(page, props)
    end

    def call(page, props)
      payload = { page: page, props: props }.to_json
      
      begin
        sock = UNIXSocket.new(SOCKET_PATH)
        
        request = "POST /render HTTP/1.1\r\n" \
                  "Host: localhost\r\n" \
                  "Connection: close\r\n" \
                  "Content-Type: application/json\r\n" \
                  "Content-Length: #{payload.bytesize}\r\n" \
                  "\r\n" \
                  "#{payload}"
        
        sock.write(request)
        
        # Read response (simplified)
        response = sock.read
        sock.close
        
        # Extract body (very naive parsing)
        _headers, body = response.split("\r\n\r\n", 2)
        body
      rescue Errno::ENOENT, Errno::ECONNREFUSED
        "<h1>Lazuli Renderer Error</h1><p>Could not connect to Deno renderer at #{SOCKET_PATH}</p>"
      end
    end
  end
end
