module Lazuli
  class Resource
    attr_reader :params

    def initialize(params = {})
      @params = params
    end

    def self.rpc(name, options = {})
      # TODO: Store metadata for TypeScript generation
    end

    # Helper to render a page
    # Usage: Render "users/index", users: users
    def Render(page, props = {})
      # Convert structs to hash if needed
      props = props.transform_values do |v|
        if v.is_a?(Array)
          v.map { |i| i.respond_to?(:to_h) ? i.to_h : i }
        elsif v.respond_to?(:to_h)
          v.to_h
        else
          v
        end
      end

      Lazuli::Renderer.render(page, props)
    end
  end
end
