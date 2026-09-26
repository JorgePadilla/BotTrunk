# frozen_string_literal: true

module Fulfillers
  # Built-in service: what things actually cost in Honduras, as recorded by a
  # person who went and looked — coffee at the farmgate, the basic basket,
  # fuel, the street rate for dollars.
  #
  # The published number and the real number are different, and the gap is
  # invisible from outside the country. One person's weekly round is collected
  # once and sold many times, which is the only way field work scales into an
  # agent market.
  #
  # Input: { items, city }. Output: { city, prices, rate_hnl_per_usd, as_of }.
  class PricesHn < Base
    MAX_ITEMS = 40

    def call
      items = Array(@input["items"] || @input["item"]).map { |i| i.to_s.strip.downcase.presence }.compact.first(MAX_ITEMS)
      city = @input["city"].to_s.squish.presence

      readings = LocalPrice.latest.for_city(city).for_items(items.presence).to_a
      return no_data(items, city) if readings.empty?

      rate = reference_rate
      json({
        city: city || "all",
        as_of: readings.map(&:observed_at).max.iso8601,
        oldest_observation: readings.map(&:observed_at).min.iso8601,
        rate_hnl_per_usd: rate&.to_s("F"),
        prices: readings.sort_by(&:item).map { |r| r.to_reading(rate) },
        note: "Observed in person, not scraped. `days_old` and `stale` say how fresh each reading is; " \
              "anything over #{LocalPrice::STALE_AFTER.inspect} old is marked stale rather than quietly served as current."
      })
    end

    private

    # The same reference the deposit pricing uses, so a buyer converting these
    # to dollars gets the number we would charge at. Nil rather than a guess if
    # the rate is unavailable — the lempira prices are the observation.
    def reference_rate
      Rates::UsdHnl.current
    rescue StandardError => e
      Rails.logger.info("prices-hn: rate unavailable (#{e.class})")
      nil
    end

    # A request for something nobody has walked out and priced is a 422, so it
    # is never settled: the buyer pays for observations, not for an empty list.
    def no_data(items, city)
      known = LocalPrice.latest.pluck(:item).uniq.sort
      asked = items.presence&.join(", ")
      bad_request(
        [ asked ? "No observations for #{asked}#{city ? " in #{city}" : ""}." : "No observations recorded yet.",
          known.any? ? "Priced today: #{known.join(", ")}." : nil ].compact.join(" ")
      )
    end
  end
end
