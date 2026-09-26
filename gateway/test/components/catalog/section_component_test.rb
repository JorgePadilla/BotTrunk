# frozen_string_literal: true

require "test_helper"

class Catalog::SectionComponentTest < ViewComponent::TestCase
  test "caps the cards and links to the rest" do
    render_inline Catalog::SectionComponent.new(category: "Data", cards: cards_for("Data"), limit: 2)

    assert_selector "h2", text: "Data"
    assert_selector "a[href^='/s/']", count: 2
    assert_selector "a[href='/?category=Data']", text: /See all \d+ in Data/
  end

  test "no link when the whole category is on show" do
    cards = cards_for("Translation")
    assert_operator cards.size, :<=, Catalog::SectionComponent::LIMIT

    render_inline Catalog::SectionComponent.new(category: "Translation", cards: cards)
    assert_selector "a[href='/?category=Translation']", count: 0
    assert_selector "a[href^='/s/']", count: cards.size
  end

  test "a family renders as one card" do
    render_inline Catalog::SectionComponent.new(category: "Payments", cards: cards_for("Payments"))

    assert_selector "a[href='/s/deposit-bac-1000']"
    assert_selector "a[href='/s/deposit-bac-10000']", count: 0
  end

  private

  def cards_for(category)
    Catalog::Ranking.new(Catalog::Service.all.select { |s| s.category == category }).cards
  end
end
