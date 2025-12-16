require "test_helper"
require "lazuli/resource"

class ResourceRpcTest < Minitest::Test
  class MyResource < Lazuli::Resource
    rpc :index, returns: [Integer]
  end

  def test_rpc_definitions_are_recorded
    defs = MyResource.rpc_definitions
    assert defs.key?(:index)
    assert_equal([Integer], defs[:index][:returns])
  end
end
