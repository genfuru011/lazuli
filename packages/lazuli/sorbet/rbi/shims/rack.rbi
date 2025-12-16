# typed: true

module Rack
  class Request
    sig { params(env: T.untyped).void }
    def initialize(env); end

    sig { returns(String) }
    def path_info; end

    sig { returns(T::Hash[String, T.untyped]) }
    def params; end

    sig { returns(String) }
    def request_method; end
  end
end
