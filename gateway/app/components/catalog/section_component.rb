# frozen_string_literal: true

module Catalog
  # One category on the shopfront: a heading, the first few cards, and a way
  # to the rest. The cap is what keeps the front page one screen of sections
  # rather than a wall of cards, however large the catalog gets.
  class SectionComponent < ApplicationComponent
    LIMIT = 4

    BLURBS = {
      "Payments" => "Money and assets moved by a person, settled on-chain.",
      "Software" => "Describe it, receive it built.",
      "Procurement" => "Things an agent cannot do because they happen over the phone.",
      "Verification" => "Someone checks, and puts their name on the answer.",
      "Translation" => "Human translation with the local idiom handled.",
      "Data" => "Utilities your agent calls by the thousand."
    }.freeze

    def initialize(category:, cards:, limit: LIMIT)
      @category = category
      @cards = cards
      @limit = limit
    end

    def shown = @cards.first(@limit)

    def blurb = BLURBS[@category]

    def more? = @cards.size > @limit

    def more_label = "See all #{@cards.size} in #{@category}"

    def more_path = helpers.root_path(category: @category)

    attr_reader :category
  end
end
