# frozen_string_literal: true

module Dashboard
  class StatRowComponentPreview < ViewComponent::Preview
    def default
      render(Dashboard::StatRowComponent.new(stats: [
        { label: "page views", value: 1_284, hint: "612 visitors" },
        { label: "402 probes", value: 97, hint: "3 rejected payments" },
        { label: "settled calls", value: 41, hint: "9 payers" },
        { label: "volume", value: "$0.205", hint: "$0.03 commission" }
      ]))
    end
  end
end
