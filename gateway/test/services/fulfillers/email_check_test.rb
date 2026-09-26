# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class EmailCheckTest < ActiveSupport::TestCase
    # Stands in for Resolv::DNS: answers getresources(name, type) from a hash.
    class FakeDns
      def initialize(records) = @records = records
      def getresources(_name, type) = @records.fetch(type, [])
    end

    IN = Resolv::DNS::Resource::IN

    def with_mx
      FakeDns.new(IN::MX => [
        IN::MX.new(10, Resolv::DNS::Name.create("alt1.aspmx.l.google.com.")),
        IN::MX.new(1, Resolv::DNS::Name.create("aspmx.l.google.com."))
      ])
    end

    teardown { EmailCheck.dns_client = nil }

    test "reports syntax, mail exchangers and what kind of address it is" do
      EmailCheck.dns_client = with_mx

      result = EmailCheck.new(input: { "email" => "  Support@Stripe.com " }).call
      assert result.success?
      out = JSON.parse(result[:body])

      assert_equal "support@stripe.com", out["email"], "trimmed and lowercased"
      assert_equal true, out["valid_syntax"]
      assert_equal "stripe.com", out["domain"]
      assert_equal [ "aspmx.l.google.com", "alt1.aspmx.l.google.com" ], out["mx"], "lowest preference first"
      assert_equal true, out["deliverable_domain"]
      assert_equal true, out["role_account"], "support@ is read by a team, not a person"
      assert_equal false, out["free_provider"]
      assert_equal false, out["disposable"]
      assert_match(/No mail was sent/, out["note"])
    end

    test "a disposable provider is flagged" do
      EmailCheck.dns_client = with_mx

      out = JSON.parse(EmailCheck.new(input: { "email" => "throwaway@mailinator.com" }).call[:body])
      assert_equal true, out["disposable"]
      assert_equal false, out["role_account"]
    end

    test "a free consumer provider is flagged without calling it disposable" do
      EmailCheck.dns_client = with_mx

      out = JSON.parse(EmailCheck.new(input: { "email" => "jorge@gmail.com" }).call[:body])
      assert_equal true, out["free_provider"]
      assert_equal false, out["disposable"]
    end

    test "a plus-addressed role account is still a role account" do
      EmailCheck.dns_client = with_mx

      out = JSON.parse(EmailCheck.new(input: { "email" => "billing+stripe@example.com" }).call[:body])
      assert_equal true, out["role_account"]
    end

    test "a domain with no MX but an A record can still receive mail" do
      EmailCheck.dns_client = FakeDns.new(IN::A => [ IN::A.new("34.120.54.55") ])

      out = JSON.parse(EmailCheck.new(input: { "email" => "hello@small-shop.test" }).call[:body])
      assert_equal true, out["deliverable_domain"], "RFC 5321 falls back to the A record"
      assert_equal [ "small-shop.test" ], out["mx"]
    end

    test "a domain with no mail records anywhere is not deliverable" do
      EmailCheck.dns_client = FakeDns.new({})

      out = JSON.parse(EmailCheck.new(input: { "email" => "nobody@nxdomain.test" }).call[:body])
      assert_equal true, out["valid_syntax"]
      assert_equal false, out["deliverable_domain"]
      assert_equal [], out["mx"]
    end

    test "bad syntax is a 200 with valid_syntax false, and costs no DNS lookup" do
      EmailCheck.dns_client = FakeDns.new(IN::MX => [ IN::MX.new(1, Resolv::DNS::Name.create("mx.example.com.")) ])

      [ "not-an-email", "two@@example.com", "no-domain@", "@no-local.com", "spaces in@example.com" ].each do |bad|
        result = EmailCheck.new(input: { "email" => bad }).call
        assert result.success?, "#{bad} is a fact about the input, not a failure"
        out = JSON.parse(result[:body])
        assert_equal false, out["valid_syntax"], bad
        assert_nil out["domain"], bad
      end
    end

    test "a blank or oversized address is refused with 422" do
      [ "", "   ", "#{'a' * 250}@example.com" ].each do |bad|
        result = EmailCheck.new(input: { "email" => bad }).call
        assert_equal 422, result[:status], bad.truncate(20)
      end
    end

    test "a DNS failure fails the call rather than guessing" do
      EmailCheck.dns_client = Object.new.tap do |o|
        def o.getresources(*) = raise(Resolv::ResolvError, "no nameservers")
      end

      result = EmailCheck.new(input: { "email" => "hello@example.com" }).call
      assert_not result.success?
      assert_equal :upstream_error, result.code
    end
  end
end
