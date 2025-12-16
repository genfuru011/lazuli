# typed: true

module Rack
  class MockRequest
    sig { params(path: String).returns(T::Hash[T.untyped, T.untyped]) }
    def self.env_for(path); end
  end
end
