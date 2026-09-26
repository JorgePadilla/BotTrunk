# frozen_string_literal: true

require "test_helper"

module Admin
  class PricesControllerTest < ActionDispatch::IntegrationTest
    setup { ENV["ADMIN_PASSWORD"] = "s3cret" }
    teardown { ENV.delete("ADMIN_PASSWORD") }

    def observation(**attrs)
      LocalPrice.create!({ item: "coffee-quintal", unit: "quintal", city: "Tegucigalpa", price_hnl: 3_200,
                           source: "phone, 3 exporters", observed_at: Date.current }.merge(attrs))
    end

    test "requires the admin password" do
      get admin_prices_url
      assert_response :unauthorized
    end

    test "shows what the endpoint currently serves" do
      observation
      observation(item: "fuel-diesel", unit: "gallon", price_hnl: 128.50, source: "two stations")

      get admin_prices_url, headers: auth
      assert_response :success
      assert_select "td", text: "coffee-quintal"
      assert_select "td", text: "fuel-diesel"
    end

    test "recording an observation adds a row rather than editing the last one" do
      observation(price_hnl: 3_000, observed_at: 1.week.ago.to_date)

      assert_difference -> { LocalPrice.count }, 1 do
        post admin_prices_url, headers: auth, params: { local_price: {
          item: "coffee-quintal", unit: "quintal", city: "Tegucigalpa", price_hnl: "3250.00",
          source: "phone, 3 exporters", observed_at: Date.current.to_s
        } }
      end

      assert_redirected_to admin_prices_path
      assert_equal 2, LocalPrice.where(item: "coffee-quintal").count, "history is kept"
      assert_equal BigDecimal("3250"), LocalPrice.latest.first.price_hnl, "the newest is what gets served"
    end

    test "an observation from the future is refused with the reason" do
      assert_no_difference -> { LocalPrice.count } do
        post admin_prices_url, headers: auth, params: { local_price: {
          item: "coffee-quintal", unit: "quintal", city: "Tegucigalpa", price_hnl: "3250.00",
          source: "guesswork", observed_at: 2.days.from_now.to_date.to_s
        } }
      end

      assert_response :unprocessable_entity
      assert_match(/cannot be in the future/, flash[:alert])
    end

    private

    def auth
      { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("admin", "s3cret") }
    end
  end
end
