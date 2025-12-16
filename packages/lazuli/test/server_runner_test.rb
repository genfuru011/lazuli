require "test_helper"
require "lazuli/server_runner"

class ServerRunnerTest < Minitest::Test
  def test_generate_types_writes_client_d_ts
    Dir.mktmpdir do |dir|
      app_root = File.join(dir, "app_root")
      FileUtils.mkdir_p(File.join(app_root, "app", "structs"))
      FileUtils.mkdir_p(File.join(app_root, "tmp", "sockets"))

      File.write(File.join(app_root, "app", "structs", "user.rb"), <<~RUBY)
        class User < Lazuli::Struct
          attribute :id, Integer
        end
      RUBY

      runner = Lazuli::ServerRunner.new(app_root: app_root, socket: nil, port: 9292, reload: false)
      runner.send(:generate_types)

      out_path = File.join(app_root, "client.d.ts")
      assert File.exist?(out_path)
      assert_includes File.read(out_path), "interface User"
      assert_includes File.read(out_path), "id: number;"
    end
  end
end
