require_relative "lib/lazuli/version"

Gem::Specification.new do |spec|
  spec.name = "lazuli"
  spec.version = Lazuli::VERSION
  spec.authors = ["Lazuli Team"]
  spec.email = ["hello@example.com"]

  spec.summary = "Super Modern Monolith framework"
  spec.description = "Ruby for Thinking, Solid for Rendering."
  spec.homepage = "https://github.com/example/lazuli"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{lib,assets,bin}/**/*", "README.md", "LICENSE"]
  end
  spec.executables = ["lazuli"]
  spec.require_paths = ["lib"]

  # Core dependencies will be added here
  # spec.add_dependency "sqlite3"
  spec.add_dependency "rack"

  # Development tooling
  spec.add_development_dependency "ruby-lsp"
  spec.add_development_dependency "sorbet"
  spec.add_development_dependency "tapioca"
end
