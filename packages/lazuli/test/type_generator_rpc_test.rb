require "test_helper"
require "lazuli/type_generator"
require "fileutils"

class TypeGeneratorRpcTest < Minitest::Test
  def test_generates_rpc_response_types
    Dir.mktmpdir do |dir|
      app_root = File.join(dir, "app_root")
      FileUtils.mkdir_p(File.join(app_root, "app", "structs"))
      FileUtils.mkdir_p(File.join(app_root, "app", "resources"))

      File.write(File.join(app_root, "app", "structs", "user.rb"), <<~RUBY)
        class User < Lazuli::Struct
          attribute :id, Integer
        end
      RUBY

      File.write(File.join(app_root, "app", "resources", "users_resource.rb"), <<~RUBY)
        class UsersResource < Lazuli::Resource
          rpc :index, returns: [User]
        end
      RUBY

      out_path = File.join(app_root, "client.d.ts")
      Lazuli::TypeGenerator.generate(app_root: app_root, out_path: out_path)

      content = File.read(out_path)
      assert_includes content, "export interface RpcRequests"
      assert_includes content, "export interface RpcResponses"
      assert_includes content, '"UsersResource#index": undefined'
      assert_includes content, '"UsersResource#index": User[]'

      client_path = File.join(app_root, "client.rpc.ts")
      assert File.exist?(client_path)
      client = File.read(client_path)
      assert_includes client, "/__lazuli/rpc"

      app_client_path = File.join(app_root, "app", "client.rpc.ts")
      assert File.exist?(app_client_path)
      app_client = File.read(app_client_path)
      assert_includes app_client, "/__lazuli/rpc"
    end
  end
end
