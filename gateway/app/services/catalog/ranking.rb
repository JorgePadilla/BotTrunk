# frozen_string_literal: true

module Catalog
  # The order the catalog is shown in, decided once so the shopfront, the
  # filtered views and the reference page cannot disagree.
  #
  # Seed order was the order until there were twenty cards; past that it stops
  # being a decision anyone made. The rule now:
  #
  #   1. live before on_request — meet what you can actually call first
  #   2. then by paid calls, so the catalog ranks itself by what people buy
  #   3. then seed order, which keeps it stable for everything with no traffic
  #
  # A new service therefore starts at the bottom of its section and climbs if
  # it earns it, rather than needing someone to decide where it goes.
  class Ranking
    # Human-fulfilled work first: it is the part of this catalog nobody else
    # can copy, and the cheap utilities read better after it than before it.
    SECTIONS = %w[Payments Software Procurement Verification Translation Data].freeze

    Card = Data.define(:primary, :variants, :metrics) do
      def category = primary.category
      def live? = primary.live?
    end

    def initialize(services = Service.all)
      @services = services
      @seed_order = Service.all.each_with_index.to_h { |service, i| [ service.slug, i ] }
    end

    # [Card, …] — one per catalog card, families already collapsed.
    def cards
      Service.grouped(@services).map { |variants|
        Card.new(primary: variants.min_by(&:price_atomic), variants: variants,
                 metrics: Metrics.combined(variants.map(&:slug)))
      }.sort_by { |card| sort_key(card) }
    end

    # { "Payments" => [Card, …], … } in SECTIONS order, empty ones dropped.
    def sections
      grouped = cards.group_by(&:category)
      ordered = SECTIONS.filter_map { |name| [ name, grouped[name] ] if grouped[name]&.any? }
      # A category added to the model but not to SECTIONS still gets shown,
      # after the ones we ordered deliberately.
      ordered + grouped.except(*SECTIONS).sort.to_a
    end

    # The same rule applied to services one by one, for the reference page,
    # where a family's tiers are rows of their own rather than a single card.
    def services = @services.sort_by { |service| service_key(service) }

    # Cheapest first within live-before-on-request. The one alternative order
    # the reference page offers, because price is what a buyer scans for.
    def by_price = @services.sort_by { |service| [ service.live? ? 0 : 1, service.price_atomic ] }

    private

    def service_key(service)
      [ service.live? ? 0 : 1, -Metrics.for(service.slug).calls.to_i, @seed_order.fetch(service.slug, Float::INFINITY) ]
    end

    def sort_key(card)
      [ card.live? ? 0 : 1, -card.metrics.calls.to_i, @seed_order.fetch(card.primary.slug, Float::INFINITY) ]
    end
  end
end
