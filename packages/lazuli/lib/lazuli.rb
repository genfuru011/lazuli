module Lazuli
  class Error < StandardError; end
end

require_relative "lazuli/version"
require_relative "lazuli/types"
require_relative "lazuli/struct"
require_relative "lazuli/renderer"
require_relative "lazuli/turbo_stream"
require_relative "lazuli/resource"
require_relative "lazuli/db"
require_relative "lazuli/repository"
require_relative "lazuli/app"
