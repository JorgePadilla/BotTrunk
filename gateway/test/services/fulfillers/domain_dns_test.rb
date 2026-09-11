# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class DomainDnsTest < ActiveSupport::TestCase
    # Stands in for Resolv::DNS: answers getresources(name, type) from a hash.
    class FakeDns
      def initialize(records) = @records = records
      def getresources(_name, type) = @records.fetch(type, [])
    end

    IN = Resolv::DNS::Resource::IN

    setup do
      DomainDns.dns_client = FakeDns.new(
        IN::A => [ IN::A.new("34.120.54.55") ],
        IN::AAAA => [ IN::AAAA.new("2600:1901::1") ],
        IN::MX => [ IN::MX.new(10, Resolv::DNS::Name.create("alt1.aspmx.l.google.com.")), IN::MX.new(1, Resolv::DNS::Name.create("aspmx.l.google.com.")) ],
        IN::NS => [ IN::NS.new(Resolv::DNS::Name.create("ns1.example.net.")) ],
        IN::TXT => [ IN::TXT.new("v=spf1 include:_spf.google.com ~all"), IN::TXT.new("v=DMARC1; p=reject"), IN::TXT.new("stripe-site-verification=abc") ]
      )
    end

    teardown { DomainDns.dns_client = nil }

    test "returns the record set, mail exchangers sorted by preference, and provider hints" do
      result = DomainDns.new(input: { "domain" => "HTTPS://Example.com/pricing" }).call
      assert result.success?
      out = JSON.parse(result[:body])

      assert_equal "example.com", out["domain"], "scheme, path and case are stripped"
      assert_equal [ "34.120.54.55" ], out["a"]
      assert_equal [ "2600:1901::1" ], out["aaaa"]
      assert_equal [ 1, 10 ], out["mx"].map { |m| m["preference"] }
      assert_equal "aspmx.l.google.com", out["mx"].first["exchange"]
      assert_equal [ "ns1.example.net" ], out["ns"]
      assert_equal "Google Workspace", out.dig("hints", "email")
      assert_equal true, out.dig("hints", "dmarc")
      assert_match "v=spf1", out.dig("hints", "spf")
      assert_equal [ "stripe" ], out.dig("hints", "verifications")
    end

    test "rejects anything that is not a hostname" do
      [ "", "localhost", "example", "not a domain", "10.0.0.1" ].each do |value|
        assert_equal 422, DomainDns.new(input: { "domain" => value }).call[:status], value
      end
    end

    test "a resolver failure is an upstream failure, not a charge" do
      DomainDns.dns_client = Object.new.tap { |o| o.define_singleton_method(:getresources) { |*| raise Resolv::ResolvError, "nope" } }
      result = DomainDns.new(input: { "domain" => "example.com" }).call
      assert result.failure?
      assert_equal 502, result.data[:status]
    end
  end
end
