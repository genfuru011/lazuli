require "test_helper"
require "rack"
require "lazuli/resource"
require "lazuli/app"

class MyRpcResource < Lazuli::Resource
  rpc :ping, returns: String

  def ping
    { ok: true }
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
      input: { key: "MyRpcResource#ping", params: {} }.to_json,
      "CONTENT_TYPE" => "application/json",
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
      input: { key: "NopeResource#ping", params: {} }.to_json,
      "CONTENT_TYPE" => "application/json",
    )

    status, _headers, _body = @app.call(env)
    assert_equal 404, status
  end
end
