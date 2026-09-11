# frozen_string_literal: true

require "test_helper"

module Analytics
  class GeolocateTest < ActiveSupport::TestCase
    test "returns nil for private, loopback and garbage addresses without touching the database" do
      assert_nil Geolocate.new.call("10.0.0.5")
      assert_nil Geolocate.new.call("127.0.0.1")
      assert_nil Geolocate.new.call("not-an-ip")
      assert_nil Geolocate.new.call(nil)
    end

    test "returns nil when no database file is present" do
      assert_not Geolocate.available?
      assert_nil Geolocate.new.call("8.8.8.8")
    end

    test "events carry the country and city the lookup returns" do
      Geolocate.stubs_lookup = ->(ip) { ip == "190.4.0.1" ? { country: "HN", city: "San Pedro Sula, Cortés" } : nil }
      event = Track.new(name: "page_view", ip: "190.4.0.1", user_agent: "Mozilla/5.0").call[:event]
      assert_equal "HN", event.country
      assert_equal "San Pedro Sula, Cortés", event.city
      other = Track.new(name: "page_view", ip: "1.2.3.4", user_agent: "Mozilla/5.0").call[:event]
      assert_nil other.country
    ensure
      Geolocate.stubs_lookup = nil
    end
  end
end
