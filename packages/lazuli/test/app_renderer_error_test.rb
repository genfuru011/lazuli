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

class ExplodeResource < Lazuli::Resource
  def index
    raise "boom"
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

  def test_renderer_error_returns_turbo_stream_when_accepts_turbo_stream
    original = Lazuli::Renderer.method(:render)
    Lazuli::Renderer.define_singleton_method(:render) do |_page, _props|
      raise Lazuli::RendererError.new(status: 400, body: "Bad fragment", message: "Bad fragment")
    end

    status, headers, body = @app.call(
      Rack::MockRequest.env_for("/", "HTTP_ACCEPT" => "text/vnd.turbo-stream.html")
    )

    assert_equal 400, status
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", headers["content-type"]
    assert_includes body.join, "<turbo-stream"
    assert_includes body.join, "Bad fragment"
  ensure
    Lazuli::Renderer.define_singleton_method(:render, &original)
  end

  def test_debug_renders_detailed_error_page_for_standard_error
    old = ENV["LAZULI_DEBUG"]
    ENV["LAZULI_DEBUG"] = "1"

    status, headers, body = @app.call(Rack::MockRequest.env_for("/explode"))
    assert_equal 500, status
    assert_equal "text/html; charset=utf-8", headers["content-type"]
    assert_includes body.join, "Backtrace"
    assert_includes body.join, "RuntimeError"
    assert_includes body.join, "boom"
  ensure
    ENV["LAZULI_DEBUG"] = old
  end

  def test_debug_renders_detailed_error_page_for_renderer_error
    original = Lazuli::Renderer.method(:render)
    Lazuli::Renderer.define_singleton_method(:render) do |_page, _props|
      raise Lazuli::RendererError.new(status: 400, body: "Bad fragment", message: "Bad fragment")
    end

    old = ENV["LAZULI_DEBUG"]
    ENV["LAZULI_DEBUG"] = "1"

    status, headers, body = @app.call(Rack::MockRequest.env_for("/"))
    assert_equal 400, status
    assert_equal "text/html; charset=utf-8", headers["content-type"]
    assert_includes body.join, "Bad fragment"
    assert_includes body.join, "Backtrace"
  ensure
    ENV["LAZULI_DEBUG"] = old
    Lazuli::Renderer.define_singleton_method(:render, &original)
  end
end
