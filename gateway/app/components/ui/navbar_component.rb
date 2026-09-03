# frozen_string_literal: true

module Ui
  class NavbarComponent < ApplicationComponent
    LINKS = [ [ "Catalog", "/" ], [ "Docs", "/docs" ], [ "Sell", "/sell" ] ].freeze

    def initialize(active: "Catalog")
      @active = active.presence || "Catalog"
    end

    def links = LINKS

    def link_classes(label)
      classes("text-sm font-medium transition-colors hover:text-base-content", label == @active ? "text-base-content" : "text-muted")
    end
  end
end
