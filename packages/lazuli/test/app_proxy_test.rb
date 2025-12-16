require "test_helper"
require "rack"
require "lazuli/app"
require "lazuli/renderer"

class AppProxyTest < Minitest::Test
  def setup
    @app = Lazuli::App.new(root: Dir.pwd)
  end

  def test_proxies___lazuli_paths_to_renderer
    original = Lazuli::Renderer.method(:asset)
    Lazuli::Renderer.define_singleton_method(:asset) do |_path|
      { status: 200, headers: { "Content-Type" => "application/json" }, body: "{\"ok\":true}" }
    end

    status, headers, body = @app.call(Rack::MockRequest.env_for("/__lazuli/reload"))
    assert_equal 200, status
    assert_equal "application/json", headers["content-type"]
    assert_equal "{\"ok\":true}", body.join
  ensure
    Lazuli::Renderer.define_singleton_method(:asset, &original)
  end
end
