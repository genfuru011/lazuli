require "json"

begin
  require "oj"
rescue LoadError
end

module Lazuli
  module Json
    module_function

    def dump(obj)
      if defined?(::Oj)
        ::Oj.dump(obj, mode: :compat)
      else
        ::JSON.generate(obj)
      end
    end

    def load(str)
      if defined?(::Oj)
        ::Oj.load(str, mode: :compat)
      else
        ::JSON.parse(str)
      end
    end
  end
end
