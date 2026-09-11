# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class CatalogControllerTest < ActionDispatch::IntegrationTest
      test "index lists every service with integer prices and a status" do
        get api_v1_catalog_url
        assert_response :success
        services = response.parsed_body["services"]
        assert_equal Catalog::Service.all.size, services.size

        scrape = services.find { |s| s["slug"] == "scrape-markdown" }
        assert_equal "90000", scrape["price"]["amount"]
        assert_equal "https://api.bottrunk.com/s/scrape-markdown", scrape["endpoint"]
        assert_equal "url", scrape["inputs"][0]["name"]
        assert_equal "live", scrape["status"]

        assert_equal "on_request", services.find { |s| s["slug"] == "verify-business-hn" }["status"]
        assert_equal "live", services.find { |s| s["slug"] == "deposit-bac-1000" }["status"]
      end

      test "the four deposit tiers are priced from the day's rate" do
        get api_v1_catalog_url(category: "Payments")
        tiers = response.parsed_body["services"]
        assert_equal %w[deposit-bac-1000 deposit-bac-2500 deposit-bac-5000 deposit-bac-10000], tiers.map { |s| s["slug"] }
        assert_equal "42510122", tiers.first["price"]["amount"]
        assert_equal "425101215", tiers.last["price"]["amount"]
      end

      test "show returns one service or 404" do
        get api_v1_catalog_service_url("page-metadata")
        assert_response :success
        assert_equal "Page metadata", response.parsed_body["name"]
        assert_equal "20000", response.parsed_body["price"]["amount"]

        get api_v1_catalog_service_url("nope")
        assert_response :not_found
      end
    end
  end
end
