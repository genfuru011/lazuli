require "test_helper"
require "rack"
require "lazuli/app"
require "lazuli/resource"
require "lazuli/renderer"
require "lazuli/turbo_stream"

class DispatchResource < Lazuli::Resource
  def create
    redirect("/")
  end

  def create_stream
    stream do |t|
      t.update "flash", fragment: "components/Flash", props: { message: "hi" }
    end
  end
end

class TurboStreamDispatchTest < Minitest::Test
  def setup
    @app = Lazuli::App.new(root: Dir.pwd)
  end

  def test_accept_turbo_prefers_stream_action
    captured = nil
    original = Lazuli::Renderer.method(:render_turbo_stream)
    Lazuli::Renderer.define_singleton_method(:render_turbo_stream) do |ops|
      captured = ops
      "<turbo-stream></turbo-stream>"
    end

    status, headers, _body = @app.call(
      Rack::MockRequest.env_for("/dispatch", method: "POST", "HTTP_ACCEPT" => "text/vnd.turbo-stream.html, text/html")
    )

    assert_equal 200, status
    assert_equal "text/vnd.turbo-stream.html; charset=utf-8", headers["content-type"]
    assert_equal :update, captured&.first&.dig(:action)
  ensure
    Lazuli::Renderer.define_singleton_method(:render_turbo_stream, &original)
  end

  def test_non_turbo_uses_html_action
    status, headers, _body = @app.call(
      Rack::MockRequest.env_for("/dispatch", method: "POST", "HTTP_ACCEPT" => "text/html")
    )

    assert_equal 303, status
    assert_equal "/", headers["location"]
  end
end
