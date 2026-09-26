# frozen_string_literal: true

module Catalog
  class SectionComponentPreview < ViewComponent::Preview
    # A long category: four cards and a way to the other five.
    def with_more
      render Catalog::SectionComponent.new(category: "Data", cards: cards_for("Data"))
    end

    # A short one: no "see all" link, because there is no all to see.
    def complete
      render Catalog::SectionComponent.new(category: "Translation", cards: cards_for("Translation"))
    end

    private

    def cards_for(category)
      Catalog::Ranking.new(Catalog::Service.all.select { |s| s.category == category }).cards
    end
  end
end
