require "sqlite3"

module Lazuli
  class Repository
    def self.open(path)
      db = SQLite3::Database.new(path)
      db.results_as_hash = true
      db
    end
  end
end
