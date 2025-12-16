require "test_helper"
require "lazuli/type_generator"
require "fileutils"

class TypeGeneratorIgnoresNonStructTest < Minitest::Test
  def test_ignores_non_struct_files
    Dir.mktmpdir do |dir|
      app_root = File.join(dir, "app_root")
      FileUtils.mkdir_p(File.join(app_root, "app", "structs"))
      FileUtils.mkdir_p(File.join(app_root, "app", "resources"))

      File.write(File.join(app_root, "app", "structs", "user.rb"), <<~RUBY)
        class User < Lazuli::Struct
          attribute :id, Integer
        end
      RUBY

      # This would fail if TypeGenerator tried to require app/resources
      File.write(File.join(app_root, "app", "resources", "broken_resource.rb"), <<~RUBY)
        class BrokenResource < Lazuli::Resource
          def index
            MissingConstant.call
          end
        end
      RUBY

      out_path = File.join(app_root, "client.d.ts")
      Lazuli::TypeGenerator.generate(app_root: app_root, out_path: out_path)

      content = File.read(out_path)
      assert_includes content, "interface User"
      assert_includes content, "id: number;"
    end
  end
end
