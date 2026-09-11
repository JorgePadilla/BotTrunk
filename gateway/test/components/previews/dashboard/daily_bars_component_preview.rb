# frozen_string_literal: true

module Dashboard
  class DailyBarsComponentPreview < ViewComponent::Preview
    def default
      series = (0...30).map { |i| [ Date.new(2026, 8, 13) + i, [ 0, i * 3 % 17, i ].max ] }
      render(Dashboard::DailyBarsComponent.new(series: series, label: "Page views per day"))
    end
  end
end
