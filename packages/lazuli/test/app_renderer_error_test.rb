require "test_helper"
require "rack"
require "lazuli/app"
require "lazuli/resource"
require "lazuli/renderer"

class HomeResource < Lazuli::Resource
  def index
    Render "home", {}
  end
end

class AppRendererErrorTest < Minitest::Test

  def setup
    @app = Lazuli::App.new(root: Dir.pwd)
  end

  def test_renderer_error_renders_html_error_page_and_preserves_status
    original = Lazuli::Renderer.method(:render)
    Lazuli::Renderer.define_singleton_method(:render) do |_page, _props|
      raise Lazuli::RendererError.new(status: 400, body: "Bad fragment", message: "Bad fragment")
    end

    status, headers, body = @app.call(Rack::MockRequest.env_for("/"))
    assert_equal 400, status
    assert_equal "text/html; charset=utf-8", headers["content-type"]
    assert_includes body.join, "Bad fragment"
  ensure
    Lazuli::Renderer.define_singleton_method(:render, &original)
  end

  def test_renderer_500_error_is_sanitized_without_debug
    original = Lazuli::Renderer.method(:render)
    Lazuli::Renderer.define_singleton_method(:render) do |_page, _props|
      raise Lazuli::RendererError.new(status: 500, body: "boom", message: "boom")
    end

    old = ENV["LAZULI_DEBUG"]
    ENV["LAZULI_DEBUG"] = nil

    status, _headers, body = @app.call(Rack::MockRequest.env_for("/"))
    assert_equal 500, status
    assert_includes body.join, "Internal Server Error"
    refute_includes body.join, "boom"
  ensure
    ENV["LAZULI_DEBUG"] = old
    Lazuli::Renderer.define_singleton_method(:render, &original)
  end
end
