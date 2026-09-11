# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class CatalogControllerTest < ActionDispatch::IntegrationTest
      test "index lists every service with integer prices" do
        get api_v1_catalog_url
        assert_response :success
        services = response.parsed_body["services"]
        assert_equal Catalog::Service.all.size, services.size
        first = services.find { |s| s["slug"] == "scrape-markdown" }
        assert_equal "5000", first["price"]["amount"]
        assert_equal "https://api.bottrunk.com/s/scrape-markdown", first["endpoint"]
        assert_equal "url", first["inputs"][0]["name"]
        assert_equal "live", first["status"]
        assert_equal "coming_soon", services.find { |s| s["slug"] == "pdf-extract" }["status"]
      end

      test "index filters by category" do
        get api_v1_catalog_url(category: "Messaging")
        assert_equal [ "send-whatsapp" ], response.parsed_body["services"].map { |s| s["slug"] }
      end

      test "show returns one service or 404" do
        get api_v1_catalog_service_url("pdf-extract")
        assert_response :success
        assert_equal "PDF to JSON", response.parsed_body["name"]

        get api_v1_catalog_service_url("nope")
        assert_response :not_found
      end
    end
  end
end
