require "sqlite3"
require "fileutils"

module Lazuli
  class Repository
    def self.default_db_path(app_root: ENV["LAZULI_APP_ROOT"] || Dir.pwd)
      env_path = ENV["LAZULI_DB_PATH"].to_s
      env_path = ENV["LAZULI_DB"].to_s if env_path.empty?
      return File.expand_path(env_path) unless env_path.empty?

      File.join(File.expand_path(app_root), "db", "development.sqlite3")
    end

    def self.open(path = nil, app_root: ENV["LAZULI_APP_ROOT"] || Dir.pwd)
      path ||= default_db_path(app_root: app_root)
      FileUtils.mkdir_p(File.dirname(path))

      db = SQLite3::Database.new(path)
      db.results_as_hash = true

      # Improve concurrency under load (esp. with Falcon/async servers).
      begin
        db.busy_timeout = (ENV["LAZULI_DB_BUSY_TIMEOUT_MS"] || "5000").to_i
        db.execute("PRAGMA journal_mode = WAL")
        db.execute("PRAGMA synchronous = NORMAL")
      rescue StandardError
      end

      db
    end
  end
end
