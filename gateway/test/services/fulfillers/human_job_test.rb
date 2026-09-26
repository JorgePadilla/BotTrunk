# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class HumanJobTest < ActiveSupport::TestCase
    BRIEF = "500 units of 20 oz double-wall stainless steel water bottles, powder-coated matte black, one-colour logo."

    def service = Catalog::Service.find("rfq-global")

    def input(**overrides)
      { "brief" => BRIEF, "quantity" => "500 units", "destination" => "Port of Houston, TX" }.merge(overrides)
    end

    test "opens a job awaiting payment and answers 202 with somewhere to poll" do
      result = HumanJob.new(input: input("contact_email" => "buyer@example.com"), service: service).call

      assert result.success?
      assert_equal 202, result[:status]

      order = result[:order]
      assert_equal "awaiting_payment", order.status, "the money has not settled yet"
      assert_equal "rfq-global", order.service_slug
      assert_equal 250_000_000, order.price_atomic
      assert_equal BRIEF, order.brief
      assert_equal "500 units", order.params["quantity"]
      assert_equal "Port of Houston, TX", order.params["destination"]
      assert_equal "buyer@example.com", order.contact_email

      body = JSON.parse(result[:body])
      assert_equal order.token, body["order_id"]
      assert_equal "pending", body["status"], "what it will be a second from now, once settled"
      assert_equal "within 5 business days", body["eta"]
      assert_equal "https://api.bottrunk.test/orders/#{order.token}", body["status_url"]
      assert_nil body["result"], "nothing has been done yet"
    end

    test "a request missing what a person would need is refused for free" do
      [
        [ { "brief" => "too short" }, /brief is required/ ],
        [ { "quantity" => "" }, /quantity is required/ ],
        [ { "destination" => "" }, /destination is required/ ],
        [ { "contact_email" => "not-an-email" }, /contact_email/ ]
      ].each do |overrides, message|
        result = HumanJob.new(input: input(**overrides), service: service).call
        assert result.success?, "a refusal is still an answer"
        assert_equal 422, result[:status], overrides.inspect
        assert_match message, JSON.parse(result[:body])["error"]
      end

      assert_equal 0, WorkOrder.count, "nothing was opened for a request we refused"
    end

    test "a full queue is refused with 429 rather than promised and missed" do
      service.job_capacity.times do
        WorkOrder.create!(service_slug: "rfq-global", price_atomic: 250_000_000, brief: BRIEF, status: "pending")
      end

      result = HumanJob.new(input: input, service: service).call
      assert result.success?
      assert_equal 429, result[:status]
      assert_match(/Nothing was charged/, JSON.parse(result[:body])["error"])
      assert_equal service.job_capacity, WorkOrder.count, "no new job was opened"
    end

    test "jobs that were never paid for do not count against capacity" do
      service.job_capacity.times do
        WorkOrder.create!(service_slug: "rfq-global", price_atomic: 250_000_000, brief: BRIEF, status: "awaiting_payment")
      end

      result = HumanJob.new(input: input, service: service).call
      assert_equal 202, result[:status], "only settled work occupies the queue"
    end
  end
end
