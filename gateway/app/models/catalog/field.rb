# frozen_string_literal: true

module Catalog
  # One row of a service's input or output schema.
  Field = Data.define(:name, :type, :description)
end
