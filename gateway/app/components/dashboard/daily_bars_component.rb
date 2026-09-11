# frozen_string_literal: true

module Dashboard
  # One bar per day, inline SVG, no library. `series:` is [[Date, Integer], …]
  # in chronological order. Bars use currentColor so both themes work.
  class DailyBarsComponent < ApplicationComponent
    WIDTH = 600
    HEIGHT = 80
    GAP = 2

    def initialize(series:, label:)
      @series = series
      @label = label
    end

    attr_reader :series, :label

    def max = [ series.map(&:last).max.to_i, 1 ].max

    def total = series.sum(&:last)

    def bar_width = (WIDTH - GAP * (series.size - 1)) / series.size.to_f

    def bars
      series.each_with_index.map do |(date, value), i|
        h = (value.to_f / max * HEIGHT).ceil
        { x: (i * (bar_width + GAP)).round(2), y: HEIGHT - h, w: bar_width.round(2), h: h, title: "#{date}: #{value}" }
      end
    end
  end
end
