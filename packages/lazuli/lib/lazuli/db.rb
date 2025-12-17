require "fileutils"
require "sqlite3"

module Lazuli
  module DB
    Migration = ::Struct.new(:version, :name, :up_path, :down_path, keyword_init: true)

    def self.create(db_path:, migrations_dir:)
      FileUtils.mkdir_p(File.dirname(db_path))

      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      ensure_schema_migrations!(db)
      migrate(db: db, migrations_dir: migrations_dir)
    ensure
      db&.close
    end

    def self.rollback(db_path:, migrations_dir:, steps: 1)
      db = SQLite3::Database.new(db_path)
      db.results_as_hash = true
      ensure_schema_migrations!(db)

      versions = db.execute(
        "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT ?",
        steps
      ).map { |r| r["version"].to_s }

      all = migrations(migrations_dir)
      versions.each do |version|
        m = all.find { |mm| mm.version == version }
        down_path = m&.down_path
        unless down_path && File.exist?(down_path)
          raise Lazuli::Error, "Missing down migration for #{version}"
        end

        db.execute_batch(File.read(down_path))
        db.execute("DELETE FROM schema_migrations WHERE version = ?", version)
      end
    ensure
      db&.close
    end

    def self.migrate(db:, migrations_dir:)
      ensure_schema_migrations!(db)
      applied = applied_versions(db)

      migrations(migrations_dir).each do |m|
        next if applied.include?(m.version)

        db.execute_batch(File.read(m.up_path))
        db.execute("INSERT INTO schema_migrations(version) VALUES (?)", m.version)
      end
    end

    def self.migrations(migrations_dir)
      return [] unless Dir.exist?(migrations_dir)

      Dir[File.join(migrations_dir, "*.up.sql")].sort.map do |up_path|
        base = File.basename(up_path, ".up.sql")
        version, *name_parts = base.split("_")
        down_path = File.join(migrations_dir, "#{base}.down.sql")

        Migration.new(
          version: version.to_s,
          name: name_parts.join("_"),
          up_path: up_path,
          down_path: down_path
        )
      end
    end

    def self.ensure_schema_migrations!(db)
      db.execute("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)")
    end

    def self.applied_versions(db)
      db.execute("SELECT version FROM schema_migrations").map { |r| r["version"].to_s }
    end
  end
end
