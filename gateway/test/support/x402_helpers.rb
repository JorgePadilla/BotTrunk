# frozen_string_literal: true

require "ipaddr"

module X402Helpers
  # Stand-in for Resolv: hosts named *.internal or "localhost" resolve to
  # private space, everything else to a public address.
  module FakeResolver
    def self.getaddresses(host)
      # A literal IP resolves to itself, as it does in reality — otherwise a
      # fake that answers "public" for http://127.0.0.1/ hides the case the
      # SSRF guard exists for.
      return [ host ] if literal_ip?(host)
      return [ "127.0.0.1" ] if host == "localhost"
      return [ "10.0.0.5" ] if host.end_with?(".internal")
      return [] if host == "nxdomain.test"

      [ "93.184.216.34" ]
    end

    def self.literal_ip?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::InvalidAddressError
      false
    end
  end

  TEST_PAY_TO = "UTWS33TM7IT7NINJSFWS5KVGL73G4ERJMYDKHF7KE4WDXHYO4L7V2PNMRE"
  TESTNET = Payments::Networks.algorand(:testnet)

  def service = Catalog::Service.find("scrape-markdown")          # built-in (Fulfillers::ScrapeMarkdown)
  def proxied_service = Catalog::Service.find("test-proxy")       # proxied to upstream_url (test-only, see test_helper)
  def on_request_service = Catalog::Service.find("test-on-request") # listed but never callable

  def requirements_for(svc = service)
    Payments::BuildRequirements.new(service: svc).call[:requirements]
  end

  # A syntactically valid payment header. The transaction bytes are fake; only
  # the fake adapter or WebMock ever sees them.
  #
  # `style: :v2` is what real clients send — @x402-avm, and anything following
  # the v2 spec — with the scheme and network inside `accepted`. `:v1` is the
  # older flat shape, which our own Python spike client still sends. The
  # gateway has to accept both, so the suite builds both.
  def payment_header(network: TESTNET[:caip2], scheme: "exact", version: 2, style: :v2)
    inner = { paymentGroup: [ Base64.strict_encode64("signed-txn") ], paymentIndex: 0 }
    body =
      if style == :v2
        { x402Version: version, accepted: { scheme: scheme, network: network, asset: TESTNET[:usdc_asa].to_s, payTo: TEST_PAY_TO }, payload: inner }
      else
        { x402Version: version, scheme: scheme, network: network, payload: inner }
      end
    Base64.strict_encode64(body.to_json)
  end

  def stub_upstream(status: 200, body: { ok: true }.to_json)
    stub_request(:post, Catalog::Service::DEFAULT_UPSTREAM)
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end
end
