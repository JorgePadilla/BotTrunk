# frozen_string_literal: true

module Dashboard
  # Plain data table: `columns:` are header labels, `rows:` arrays of cells
  # (strings or already-safe HTML). Numeric columns are right-aligned by
  # passing their indexes in `numeric:`. Empty rows show `empty`.
  class TableComponent < ApplicationComponent
    def initialize(columns:, rows:, numeric: [], empty: "Nothing yet.")
      @columns = columns
      @rows = rows
      @numeric = numeric
      @empty = empty
    end

    attr_reader :columns, :rows, :empty

    def numeric?(index) = @numeric.include?(index)
  end
end
