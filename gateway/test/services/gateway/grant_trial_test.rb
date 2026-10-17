# frozen_string_literal: true

require "test_helper"

module Gateway
  class GrantTrialTest < ActiveSupport::TestCase
    setup { @service = Catalog::Service.find("page-kind") }

    def grant(ip = "7.7.7.7", now: Time.current) = GrantTrial.new(service: @service, ip: ip, now: now)

    def record_trial(key, at: Time.current)
      Event.create!(name: GrantTrial::EVENT, service_slug: "page-kind", properties: { trial_key: key }, created_at: at)
    end

    test "a caller's fingerprint is stable, salted and not the IP" do
      assert_equal grant.key, grant.key
      assert_not_equal grant("7.7.7.7").key, grant("8.8.8.8").key
      assert_not_includes grant.key, "7.7.7.7"
    end

    test "one trial per caller every 30 days" do
      record_trial(grant.key, at: 29.days.ago)
      assert_equal :trial_used, grant.call.code

      Event.delete_all
      record_trial(grant.key, at: 31.days.ago)
      assert grant.call.success?
    end

    test "no more trials once the day's cap is reached" do
      GrantTrial::DAILY_CAP.times { |i| record_trial("someone-#{i}") }
      assert_equal :trial_cap, grant.call.code
      assert_not grant.available?
      assert grant(now: 1.day.from_now.beginning_of_day + 1.minute).call.success?, "the cap resets with the day"
    end

    test "only the services on the list" do
      @service = Catalog::Service.find("scrape-markdown-js")
      assert_equal :not_eligible, grant.call.code
    end
  end
end
