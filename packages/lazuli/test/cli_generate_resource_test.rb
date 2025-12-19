require "test_helper"
require "lazuli/cli"
require "fileutils"

class CliGenerateResourceTest < Minitest::Test
  def test_generate_resource_creates_files
    Dir.mktmpdir do |dir|
      app_root = File.join(dir, "app_root")
      %w[components layouts pages repositories resources structs tmp/sockets].each do |path|
        FileUtils.mkdir_p(File.join(app_root, "app", path))
      end

      Lazuli::CLI.run(["generate", "resource", "book", app_root])

      %w[
        app/structs/book.rb
        app/repositories/book_repository.rb
        app/resources/book_resource.rb
        app/pages/book.tsx
      ].each do |path|
        assert File.exist?(File.join(app_root, path)), "expected #{path} to exist"
      end

      resource = File.read(File.join(app_root, "app", "resources", "book_resource.rb"))
      assert_includes resource, "class BookResource"
      assert_includes resource, "Render \"book\""
      assert_includes resource, "def create_stream"

      repo = File.read(File.join(app_root, "app", "repositories", "book_repository.rb"))
      %w[all find create update delete].each do |method|
        assert_includes repo, "def #{method}"
      end

      %w[index show create update destroy].each do |action|
        assert_includes resource, "def #{action}"
      end
    end
  end

  def test_generate_resource_supports_route_override
    Dir.mktmpdir do |dir|
      app_root = File.join(dir, "app_root")
      %w[components layouts pages repositories resources structs tmp/sockets].each do |path|
        FileUtils.mkdir_p(File.join(app_root, "app", path))
      end

      Lazuli::CLI.run(["generate", "resource", "book", app_root, "--route", "/library/books"])

      resource = File.read(File.join(app_root, "app", "resources", "book_resource.rb"))
      assert_includes resource, "redirect(\"/library/books\")"
    end
  end
end
