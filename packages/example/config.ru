require "bundler/setup"
require "lazuli"

# Load application files
Dir[File.join(__dir__, "app", "**", "*.rb")].sort.each { |f| require f }

run Lazuli::App.new
