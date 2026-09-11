# frozen_string_literal: true

module Catalog
  # One row of a service's input or output schema. `example` feeds the Bazaar
  # discovery extension; when nil a placeholder is derived from `type`.
  Field = Data.define(:name, :type, :description, :example) do
    def initialize(name:, type:, description:, example: nil) = super

    def example_value
      return example unless example.nil?

      case type
      when "boolean" then false
      when "integer", "number" then 1
      when "object" then {}
      when "array" then []
      else "…"
      end
    end

    def json_schema = { type: type, description: description }
  end
end
