require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__)) unless $LOAD_PATH.include?(File.expand_path("../lib", __dir__))

require "lazuli/version"
require "lazuli/struct"
