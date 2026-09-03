# frozen_string_literal: true

module Docs
  # Input/output schema rows: name (mono) · type (mono, muted) · description.
  class SchemaTableComponent < ApplicationComponent
    def initialize(fields:)
      @fields = fields
    end

    attr_reader :fields
  end
end
