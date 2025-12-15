module Lazuli
  class Struct
    def self.attribute(name, type)
      attr_accessor name
      
      # Store schema for later use (e.g. generating TS types)
      @schema ||= {}
      @schema[name] = type
    end

    def self.schema
      @schema || {}
    end

    def initialize(attributes = {})
      attributes.each do |key, value|
        send("#{key}=", value) if respond_to?("#{key}=")
      end
    end

    def self.collect(rows)
      rows.map { |row| new(row) }
    end
    
    # Serialization to JSON for Deno
    def to_json(*args)
      to_h.to_json(*args)
    end

    def to_h
      self.class.schema.keys.each_with_object({}) do |key, hash|
        hash[key] = send(key)
      end
    end
  end
end
