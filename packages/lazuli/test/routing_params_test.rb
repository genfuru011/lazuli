require "test_helper"
require "rack"
require "lazuli/app"
require "lazuli/resource"
require "lazuli/renderer"

class UsersResource < Lazuli::Resource
  def show
    "id=#{params[:id]}"
  end
end

class RoutingParamsTest < Minitest::Test
  def setup
    @app = Lazuli::App.new(root: Dir.pwd)
  end

  def test_path_id_is_exposed_as_params_id
    status, _headers, body = @app.call(Rack::MockRequest.env_for("/users/123"))
    assert_equal 200, status
    assert_equal "id=123", body.join
  end

  def test_missing_action_returns_405
    status, _headers, _body = @app.call(Rack::MockRequest.env_for("/users/123", method: "PUT"))
    assert_equal 405, status
  end
end
