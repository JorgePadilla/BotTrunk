# frozen_string_literal: true

module Dashboard
  class TableComponentPreview < ViewComponent::Preview
    def default
      render(Dashboard::TableComponent.new(columns: [ "Host", "Views" ], numeric: [ 1 ],
                                           rows: [ [ "discord.com", 42 ], [ "npmjs.com", 17 ], [ "github.com", 9 ] ]))
    end

    def empty
      render(Dashboard::TableComponent.new(columns: [ "Host", "Views" ], rows: [], empty: "No referrers yet."))
    end
  end
end
