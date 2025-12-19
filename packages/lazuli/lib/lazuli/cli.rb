require "optparse"
require "fileutils"
require "timeout"

require_relative "db"
require_relative "server_runner"
require_relative "type_generator"

module Lazuli
  class CLI
    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      cmd = @argv.shift
      case cmd
      when "dev"
        run_server_runner(@argv, cmd_name: "dev")
      when "server"
        run_rack_only(@argv)
      when "db"
        run_db(@argv)
      when "new"
        run_new(@argv)
      when "types"
        run_types(@argv)
      when "generate"
        run_generate(@argv)
      else
        puts usage
        exit(cmd.nil? ? 0 : 1)
      end
    end

    private

    def run_server_runner(argv, cmd_name: "dev")
      options = {
        app_root: Dir.pwd,
        socket: nil,
        port: 9292,
        reload: false,
        rack_server: nil,
        yjit: false
      }

      parser = OptionParser.new do |o|
        o.banner = "Usage: lazuli #{cmd_name} [options]"
        o.on("--app-root PATH", "Path to app root (default: cwd)") { |v| options[:app_root] = File.expand_path(v) }
        o.on("--socket PATH", "Unix socket path for Deno renderer") { |v| options[:socket] = File.expand_path(v) }
        o.on("--port PORT", Integer, "Rack port (default: 9292)") { |v| options[:port] = v }
        o.on("--reload", "Enable naive file watcher to restart servers on change") { options[:reload] = true }
        o.on("--falcon", "Use Falcon for Rack server (requires falcon gem)") { options[:rack_server] = :falcon }
        o.on("--yjit", "Enable YJIT for Ruby process") { options[:yjit] = true }
      end
      parser.parse!(argv)

      runner = Lazuli::ServerRunner.new(**options)
      runner.start
    end

    def run_rack_only(argv)
      options = {
        app_root: Dir.pwd,
        socket: nil,
        port: 9292,
        rack_server: nil,
        yjit: false
      }

      parser = OptionParser.new do |o|
        o.banner = "Usage: lazuli server [options]"
        o.on("--app-root PATH", "Path to app root (default: cwd)") { |v| options[:app_root] = File.expand_path(v) }
        o.on("--socket PATH", "Unix socket path for Deno renderer") { |v| options[:socket] = File.expand_path(v) }
        o.on("--port PORT", Integer, "Rack port (default: 9292)") { |v| options[:port] = v }
        o.on("--falcon", "Use Falcon for Rack server (requires falcon gem)") { options[:rack_server] = :falcon }
        o.on("--yjit", "Enable YJIT for Ruby process") { options[:yjit] = true }
      end
      parser.parse!(argv)

      app_root = File.expand_path(options[:app_root])
      socket_path = File.expand_path(options[:socket] || File.join(app_root, "tmp", "sockets", "lazuli-renderer.sock"))

      ENV["LAZULI_APP_ROOT"] = app_root
      ENV["LAZULI_SOCKET"] = socket_path

      Dir.chdir(app_root) do
        if options[:yjit]
          ENV["RUBYOPT"] = [ENV["RUBYOPT"], "--yjit"].compact.join(" ")
        end

        if options[:rack_server] == :falcon
          begin
            Gem::Specification.find_by_name("falcon")
          rescue Gem::LoadError
            warn "[Lazuli] falcon gem not found; falling back to rackup"
            options[:rack_server] = nil
          end
        end

        if options[:rack_server] == :falcon
          exec "bundle", "exec", "falcon", "serve", "--bind", "http://0.0.0.0:#{options[:port]}"
        else
          exec "bundle", "exec", "rackup", "-p", options[:port].to_s
        end
      end
    end

    def run_new(argv)
      name = argv.shift
      if name.nil? || name.strip.empty?
        abort "Usage: lazuli new <project_name>"
      end

      app_root = File.expand_path(name)
      FileUtils.mkdir_p(app_root)

      %w[components layouts pages repositories resources structs].each do |dir|
        FileUtils.mkdir_p(File.join(app_root, "app", dir))
      end
      FileUtils.mkdir_p(File.join(app_root, "tmp", "sockets"))
      FileUtils.mkdir_p(File.join(app_root, "db", "migrate"))

      write_file(File.join(app_root, "config.ru"), <<~RACK)
        require "bundler/setup"
        require "lazuli"

        Dir[File.join(__dir__, "app", "**", "*.rb")].sort.each { |f| require f }

        run Lazuli::App.new(root: __dir__)
      RACK

      write_file(File.join(app_root, "Gemfile"), <<~GEM)
        source "https://rubygems.org"
        gem "lazuli", path: "../lazuli"
      GEM

      write_file(File.join(app_root, "deno.json"), <<~JSON)
        {
          "imports": {
            "hono": "npm:hono@^4",
            "hono/": "npm:hono@^4/",
            "hono/jsx": "npm:hono@^4/jsx",
            "hono/jsx/dom": "npm:hono@^4/jsx/dom",
            "lazuli/island": "../lazuli/assets/components/Island.tsx"
          },
          "compilerOptions": {
            "jsx": "react-jsx",
            "jsxImportSource": "hono/jsx"
          }
        }
      JSON

      write_file(File.join(app_root, "app", "layouts", "Application.tsx"), <<~TSX)
        import { FC } from "hono/jsx";

        const Application: FC = (props) => (
          <html>
            <head>
              <title>#{name.capitalize}</title>
              <meta charset="utf-8" />
            </head>
            <body>
              <div id="root">{props.children}</div>
            </body>
          </html>
        );

        export default Application;
      TSX

      write_file(File.join(app_root, "app", "pages", "home.tsx"), <<~TSX)
        export default function Home() {
          return (
            <div>
              <h1>Welcome to #{name.capitalize}</h1>
              <p>Powered by Lazuli.</p>
            </div>
          );
        }
      TSX

      write_file(File.join(app_root, "app", "resources", "home_resource.rb"), <<~RUBY)
        class HomeResource < Lazuli::Resource
          def index
            Render "home"
          end
        end
      RUBY

      puts "Created Lazuli app at #{app_root}"
      puts "Next steps:"
      puts "  cd #{name}"
      puts "  bundle install"
      puts "  lazuli dev --reload"
    end

    def run_generate(argv)
      sub = argv.shift
      case sub
      when "resource"
        name = argv.shift
        if name.nil? || name.strip.empty?
          abort "Usage: lazuli generate resource <name> [app_root] [--route PATH]"
        end

        app_root = File.expand_path(argv.shift || Dir.pwd)
        options = { route: nil }

        OptionParser.new do |o|
          o.banner = "Usage: lazuli generate resource <name> [app_root] [--route PATH]"
          o.on("--route PATH", "Base route for redirects (default: /#{underscore(name)}s)") { |v| options[:route] = v }
        end.parse!(argv)

        generate_resource(app_root, name, route: options[:route])
      else
        abort "Usage: lazuli generate resource <name> [app_root] [--route PATH]"
      end
    end

    def run_db(argv)
      sub = argv.shift
      case sub
      when "create"
        run_db_create(argv)
      when "rollback"
        run_db_rollback(argv)
      else
        abort "Usage: lazuli db <create|rollback> [options]"
      end
    end

    def run_db_create(argv)
      options = {
        app_root: Dir.pwd,
        db: nil,
        migrations: nil
      }

      parser = OptionParser.new do |o|
        o.banner = "Usage: lazuli db create [options]"
        o.on("--app-root PATH", "Path to app root (default: cwd)") { |v| options[:app_root] = File.expand_path(v) }
        o.on("--db PATH", "SQLite DB path (default: db/development.sqlite3)") { |v| options[:db] = File.expand_path(v) }
        o.on("--migrations PATH", "Migrations dir (default: db/migrate)") { |v| options[:migrations] = File.expand_path(v) }
      end
      parser.parse!(argv)

      app_root = File.expand_path(options[:app_root])
      db_path = options[:db] || File.join(app_root, "db", "development.sqlite3")
      migrations_dir = options[:migrations] || File.join(app_root, "db", "migrate")

      Lazuli::DB.create(db_path: db_path, migrations_dir: migrations_dir)
      puts "DB ready at #{db_path}"
    end

    def run_db_rollback(argv)
      options = {
        app_root: Dir.pwd,
        db: nil,
        migrations: nil,
        steps: 1
      }

      parser = OptionParser.new do |o|
        o.banner = "Usage: lazuli db rollback [options]"
        o.on("--app-root PATH", "Path to app root (default: cwd)") { |v| options[:app_root] = File.expand_path(v) }
        o.on("--db PATH", "SQLite DB path (default: db/development.sqlite3)") { |v| options[:db] = File.expand_path(v) }
        o.on("--migrations PATH", "Migrations dir (default: db/migrate)") { |v| options[:migrations] = File.expand_path(v) }
        o.on("--steps N", Integer, "Rollback steps (default: 1)") { |v| options[:steps] = v }
      end
      parser.parse!(argv)

      app_root = File.expand_path(options[:app_root])
      db_path = options[:db] || File.join(app_root, "db", "development.sqlite3")
      migrations_dir = options[:migrations] || File.join(app_root, "db", "migrate")

      Lazuli::DB.rollback(db_path: db_path, migrations_dir: migrations_dir, steps: options[:steps])
      puts "Rolled back #{options[:steps]} migration(s)"
    end

    def generate_resource(app_root, name, route: nil)
      classified = classify(name)
      resource_class = "#{classified}Resource"
      struct_class = classified
      repo_module = "#{classified}Repository"
      route ||= "/#{underscore(name)}s"
      route = "/#{route}" unless route.start_with?("/")

      write_file(File.join(app_root, "app", "structs", "#{underscore(name)}.rb"), <<~RUBY)
        class #{struct_class} < Lazuli::Struct
          attribute :id, Integer
          attribute :name, String
        end
      RUBY

      write_file(File.join(app_root, "app", "repositories", "#{underscore(name)}_repository.rb"), <<~RUBY)
        module #{repo_module}
          extend self

          def all
            []
          end

          def find(id)
            nil
          end

          def create(attrs)
            nil
          end

          def update(id, attrs)
            nil
          end

          def delete(id)
            nil
          end
        end
      RUBY

      write_file(File.join(app_root, "app", "resources", "#{underscore(name)}_resource.rb"), <<~RUBY)
        class #{resource_class} < Lazuli::Resource
          def index
            items = #{repo_module}.all
            Render "#{underscore(name)}", #{underscore(name)}: items
          end

          def show
            item = #{repo_module}.find(params[:id])
            Render "#{underscore(name)}", #{underscore(name)}: item
          end

          def create
            #{repo_module}.create(params[:#{underscore(name)}] || {})
            redirect("#{route}")
          end

          def create_stream
            item = #{repo_module}.create(params[:#{underscore(name)}] || {})

            # Ruby returns operations; Deno renders the <template> fragment.
            stream do |t|
              t.prepend :#{underscore(name)}s_list, "components/#{classified}Row", #{underscore(name)}: item
              t.update :flash, "components/FlashMessage", message: "Created"
            end
          end

          def update
            # #{repo_module}.update(params[:id], params[:#{underscore(name)}])
            Render "#{underscore(name)}", #{underscore(name)}: []
          end

          def destroy
            #{repo_module}.delete(params[:id])
            redirect("#{route}")
          end

          def destroy_stream
            #{repo_module}.delete(params[:id])

            stream do |t|
              t.remove "#{underscore(name)}_\#{params[:id]}"
              t.update :flash, "components/FlashMessage", message: "Deleted"
            end
          end
        end
      RUBY

      write_file(File.join(app_root, "app", "pages", "#{underscore(name)}.tsx"), <<~TSX)
        type #{struct_class} = {
          id: number;
          name: string;
        };

        export default function #{classified}Page(props: { #{underscore(name)}: #{struct_class}[] | #{struct_class} | null }) {
          const items = Array.isArray(props.#{underscore(name)}) ? props.#{underscore(name)} as #{struct_class}[] : props.#{underscore(name)} ? [props.#{underscore(name)} as #{struct_class}] : [];
          return (
            <div>
              <h1>#{classified}</h1>
              <ul>
                {items.map((item) => (
                  <li key={item.id}>{item.name}</li>
                ))}
              </ul>
            </div>
          );
        }
      TSX

      puts "Generated resource #{resource_class} at #{app_root}"
    end

    def classify(name)
      name.split("_").map(&:capitalize).join
    end

    def underscore(name)
      name.gsub(/::/, "/")
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2')
          .gsub(/([a-z\d])([A-Z])/, '\\1_\\2')
          .tr("-", "_")
          .downcase
    end

    def run_types(argv)
      app_root = argv.shift || Dir.pwd
      app_root = File.expand_path(app_root)
      out_path = File.join(app_root, "client.d.ts")
      Lazuli::TypeGenerator.generate(app_root: app_root, out_path: out_path)
      puts "Generated #{out_path}"
    end

    def write_file(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end

    def usage
      <<~TXT
        Usage: lazuli <command> [options]

        Commands:
          dev          Start Rack + Deno (development; use --reload for watcher)
          server       Start Rack only (expects separately-managed Deno renderer)
          db           SQLite migrations (create/rollback)
          new NAME     Create a new Lazuli project
          generate     Generate code (resource)
          types [PATH] Generate client.d.ts from Structs (default: cwd)
      TXT
    end
  end
end
