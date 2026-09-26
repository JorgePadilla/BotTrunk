# frozen_string_literal: true

module Catalog
  # The catalog as dense rows: one line per service, family variants listed
  # individually rather than collapsed into a card. This is the view that
  # stays readable at a hundred services, where a grid of cards does not.
  #
  # `metrics:` is the hash the controller already loaded (`Catalog::Metrics.all`),
  # because a component never queries. `path:` turns the sortable headers into
  # links; without it they are plain labels, which is what a preview wants.
  class ServiceTableComponent < ApplicationComponent
    SORTS = { "price" => "Price" }.freeze

    def initialize(services:, metrics: {}, path: nil, params: {}, sort: nil)
      @services = services
      @metrics = metrics
      @path = path
      @params = params.to_h.symbolize_keys.except(:page, :sort).compact_blank
      @sort = sort
    end

    attr_reader :services, :sort

    def metrics_for(service) = @metrics[service.slug]

    def calls(service) = metrics_for(service)&.calls.to_i

    # Cents above a dollar, natural precision below it — the same rule the
    # price component uses, so a $42.51 deposit does not read as $42.510122.
    # Delimited too: this column runs from $0.002 to seven figures, and
    # "$1000000.00" is not a number anyone reads at a glance.
    def price(service)
      atomic = service.price_atomic
      whole, cents = helpers.usdc(atomic, decimals: (2 if atomic >= 1_000_000)).delete("$").split(".")
      "$#{helpers.number_with_delimiter(whole)}#{".#{cents}" if cents}"
    end

    def status_label(service) = service.on_request? ? "On request" : "Live"

    def sortable?(key) = @path.present? && SORTS.key?(key)

    # Clicking the active sort turns it off, so the header is a toggle rather
    # than a one-way door back to the default order.
    def sort_url(key)
      query = @params.merge(@sort == key ? {} : { sort: key })
      query.any? ? "#{@path}?#{query.to_query}" : @path
    end
  end
end
