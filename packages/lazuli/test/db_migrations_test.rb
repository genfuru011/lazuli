require "test_helper"
require "tmpdir"
require "fileutils"

require "lazuli/db"

class DbMigrationsTest < Minitest::Test
  def test_create_runs_up_migrations_and_rollback_reverts
    Dir.mktmpdir do |dir|
      db_path = File.join(dir, "db", "development.sqlite3")
      migrations_dir = File.join(dir, "db", "migrate")
      FileUtils.mkdir_p(migrations_dir)

      version = "20251217000000"
      File.write(
        File.join(migrations_dir, "#{version}_create_widgets.up.sql"),
        "CREATE TABLE widgets(id INTEGER PRIMARY KEY, name TEXT);\nINSERT INTO widgets(name) VALUES ('a');\n"
      )
      File.write(
        File.join(migrations_dir, "#{version}_create_widgets.down.sql"),
        "DROP TABLE widgets;\n"
      )

      Lazuli::DB.create(db_path: db_path, migrations_dir: migrations_dir)

      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      begin
        assert_equal 1, db.execute("SELECT COUNT(*) AS n FROM widgets").first["n"]
        assert_equal [version], db.execute("SELECT version FROM schema_migrations").map { |r| r["version"] }
      ensure
        db.close
      end

      Lazuli::DB.rollback(db_path: db_path, migrations_dir: migrations_dir)

      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      begin
        assert_raises(SQLite3::SQLException) { db.execute("SELECT * FROM widgets") }
        assert_equal [], db.execute("SELECT version FROM schema_migrations")
      ensure
        db.close
      end
    end
  end
end
