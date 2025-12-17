require "test_helper"
require "rack"
require "lazuli/resource"
require "lazuli/app"

class HelloParams < Lazuli::Struct
  attribute :name, String
end

class MyRpcResource < Lazuli::Resource
  rpc :ping, returns: String
  rpc :hello, params: HelloParams, returns: String

  def ping
    { ok: true }
  end

  def hello
    { ok: true, name: params[:name] }
  end
end

class AppRpcTest < Minitest::Test

  def setup
    @app = Lazuli::App.new(root: Dir.pwd)
  end

  def test_rpc_returns_json
    env = Rack::MockRequest.env_for(
      "/__lazuli/rpc",
      method: "POST",
      input: { key: "my_rpc#ping", params: {} }.to_json,
      "CONTENT_TYPE" => "application/json",
      "HTTP_ORIGIN" => "http://example.org",
      "HTTP_HOST" => "example.org",
    )

    status, headers, body = @app.call(env)
    assert_equal 200, status
    assert_equal "application/json", headers["content-type"]
    assert_equal "{\"ok\":true}", body.join
  end

  def test_rpc_rejects_unknown_key
    env = Rack::MockRequest.env_for(
      "/__lazuli/rpc",
      method: "POST",
      input: { key: "nope#ping", params: {} }.to_json,
      "CONTENT_TYPE" => "application/json",
      "HTTP_ORIGIN" => "http://example.org",
      "HTTP_HOST" => "example.org",
    )

    status, _headers, _body = @app.call(env)
    assert_equal 404, status
  end

  def test_rpc_rejects_cross_origin
    env = Rack::MockRequest.env_for(
      "/__lazuli/rpc",
      method: "POST",
      input: { key: "my_rpc#ping", params: {} }.to_json,
      "CONTENT_TYPE" => "application/json",
      "HTTP_ORIGIN" => "http://evil.example",
      "HTTP_HOST" => "example.org",
    )

    status, _headers, _body = @app.call(env)
    assert_equal 403, status
  end

  def test_rpc_validates_params
    ok_env = Rack::MockRequest.env_for(
      "/__lazuli/rpc",
      method: "POST",
      input: { key: "my_rpc#hello", params: { name: "Alice" } }.to_json,
      "CONTENT_TYPE" => "application/json",
      "HTTP_ORIGIN" => "http://example.org",
      "HTTP_HOST" => "example.org",
    )

    status, _headers, _body = @app.call(ok_env)
    assert_equal 200, status

    bad_env = Rack::MockRequest.env_for(
      "/__lazuli/rpc",
      method: "POST",
      input: { key: "my_rpc#hello", params: { name: 123 } }.to_json,
      "CONTENT_TYPE" => "application/json",
      "HTTP_ORIGIN" => "http://example.org",
      "HTTP_HOST" => "example.org",
    )

    status, _headers, _body = @app.call(bad_env)
    assert_equal 400, status
  end
end
