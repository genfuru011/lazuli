require "test_helper"
require "lazuli/resource"
require "lazuli/renderer"
require "lazuli/turbo_stream"

class TurboStreamResourceTest < Minitest::Test
  class RequestStub
    def initialize(accept)
      @accept = accept
    end

    def get_header(key)
      return @accept if key == "HTTP_ACCEPT"
      nil
    end
  end

  class EmptyRequest
    def get_header(_key)
      nil
    end
  end

  class MyResource < Lazuli::Resource
    def create
      if turbo_stream?
        turbo_stream do |t|
          t.append "list", fragment: "components/Row", props: { id: 1 }
          t.update "flash", fragment: "components/Flash", props: { message: "hi" }
          t.replace "flash", fragment: "components/Flash", props: { message: "bye" }
          t.remove "row_1"
        end
      else
        redirect_to "/"
      end
    end
  end

  def test_turbo_stream_records_operations_and_returns_stream_content_type
    captured = nil
    original = Lazuli::Renderer.method(:render_turbo_stream)
    Lazuli::Renderer.define_singleton_method(:render_turbo_stream) do |ops|
      captured = ops
      "<turbo-stream></turbo-stream>"
    end

    req = RequestStub.new("text/vnd.turbo-stream.html, text/html")
    status, headers, body = MyResource.new({}, request: req).create
    assert_equal 200, status
    assert_equal "text/vnd.turbo-stream.html", headers["content-type"]
    assert_equal "accept", headers["vary"]
    assert_includes body.join, "turbo-stream"

    assert_kind_of Array, captured
    assert_equal 4, captured.length
    assert_equal :append, captured[0][:action]
    assert_equal :update, captured[1][:action]
    assert_equal :replace, captured[2][:action]
    assert_equal :remove, captured[3][:action]
  ensure
    Lazuli::Renderer.define_singleton_method(:render_turbo_stream, &original)
  end

  def test_format_param_enables_turbo_stream
    original = Lazuli::Renderer.method(:render_turbo_stream)
    Lazuli::Renderer.define_singleton_method(:render_turbo_stream) { |_ops| "<turbo-stream></turbo-stream>" }

    status, headers, _body = MyResource.new({ format: "turbo_stream" }, request: EmptyRequest.new).create
    assert_equal 200, status
    assert_equal "text/vnd.turbo-stream.html", headers["content-type"]
  ensure
    Lazuli::Renderer.define_singleton_method(:render_turbo_stream, &original)
  end

  def test_accept_q_0_disables_turbo_stream
    req = RequestStub.new("text/vnd.turbo-stream.html;q=0, text/html")
    status, headers, _body = MyResource.new({}, request: req).create
    assert_equal 303, status
    assert_equal "/", headers["location"]
  end

  def test_accept_with_q_enables_turbo_stream
    original = Lazuli::Renderer.method(:render_turbo_stream)
    Lazuli::Renderer.define_singleton_method(:render_turbo_stream) { |_ops| "<turbo-stream></turbo-stream>" }

    req = RequestStub.new("text/html;q=1.0, text/vnd.turbo-stream.html;q=0.9")
    status, headers, _body = MyResource.new({}, request: req).create
    assert_equal 200, status
    assert_equal "text/vnd.turbo-stream.html", headers["content-type"]
  ensure
    Lazuli::Renderer.define_singleton_method(:render_turbo_stream, &original)
  end

  def test_redirect_to_defaults_to_303_without_request
    status, headers, _body = Lazuli::Resource.new.redirect_to("/x")
    assert_equal 303, status
    assert_equal "/x", headers["location"]
  end

  def test_redirect_to_defaults_to_302_for_get
    req = Struct.new(:request_method).new("GET")
    status, _headers, _body = Lazuli::Resource.new({}, request: req).redirect_to("/x")
    assert_equal 302, status
  end

  def test_redirect_to_defaults_to_303_for_post
    req = Struct.new(:request_method).new("POST")
    status, _headers, _body = Lazuli::Resource.new({}, request: req).redirect_to("/x")
    assert_equal 303, status
  end
end
