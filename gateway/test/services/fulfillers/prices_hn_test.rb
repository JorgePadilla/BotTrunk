# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class PricesHnTest < ActiveSupport::TestCase
    def observe(**attrs)
      LocalPrice.create!({ item: "coffee-quintal", unit: "quintal", city: "Tegucigalpa", price_hnl: 3_200,
                           source: "phone, 3 exporters", observed_at: Date.current }.merge(attrs))
    end

    test "serves the newest observation of each item, with the day it was made" do
      observe(observed_at: 2.weeks.ago.to_date, price_hnl: 3_000)
      newest = observe(price_hnl: 3_250)
      observe(item: "fuel-diesel", unit: "gallon", price_hnl: 128.50, source: "two stations on Blvd. Morazán")

      result = PricesHn.new(input: {}).call
      assert result.success?
      out = JSON.parse(result[:body])

      assert_equal %w[coffee-quintal fuel-diesel], out["prices"].map { |p| p["item"] }
      coffee = out["prices"].first
      assert_equal "3250.0", coffee["price_hnl"], "the newest reading wins, not the first"
      assert_equal newest.observed_at.iso8601, coffee["observed_at"]
      assert_equal 0, coffee["days_old"]
      assert_equal false, coffee["stale"]
      assert_equal "phone, 3 exporters", coffee["source"], "how it was learned travels with the number"
      assert_equal "26.2", out["rate_hnl_per_usd"]
      assert_equal "124.0458", coffee["price_usd"], "converted at the reference rate, not observed"
    end

    test "an old reading is marked stale rather than served as current" do
      observe(observed_at: 40.days.ago.to_date)

      out = JSON.parse(PricesHn.new(input: {}).call[:body])
      assert_equal true, out["prices"].first["stale"]
      assert_equal 40, out["prices"].first["days_old"]
    end

    test "filters by item and by city" do
      observe
      observe(item: "fuel-diesel", unit: "gallon", price_hnl: 128.50)
      observe(item: "coffee-quintal", city: "San Pedro Sula", price_hnl: 3_400)

      by_item = JSON.parse(PricesHn.new(input: { "items" => [ "fuel-diesel" ] }).call[:body])
      assert_equal [ "fuel-diesel" ], by_item["prices"].map { |p| p["item"] }

      by_city = JSON.parse(PricesHn.new(input: { "city" => "San Pedro Sula" }).call[:body])
      assert_equal [ "3400.0" ], by_city["prices"].map { |p| p["price_hnl"] }
    end

    test "asking for something nobody has priced is refused for free, and says what is priced" do
      observe

      result = PricesHn.new(input: { "items" => [ "avocado" ] }).call
      assert result.success?, "a refusal is still an answer"
      assert_equal 422, result[:status], "never settled — you pay for observations, not an empty list"
      error = JSON.parse(result[:body])["error"]
      assert_match(/No observations for avocado/, error)
      assert_match(/coffee-quintal/, error, "tells the buyer what they could have asked for")
    end

    test "an empty feed refuses rather than returning nothing" do
      result = PricesHn.new(input: {}).call
      assert_equal 422, result[:status]
      assert_match(/No observations recorded yet/, JSON.parse(result[:body])["error"])
    end
  end
end
