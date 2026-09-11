# frozen_string_literal: true

module X402Helpers
  # Stand-in for Resolv: hosts named *.internal or "localhost" resolve to
  # private space, everything else to a public address.
  module FakeResolver
    def self.getaddresses(host)
      return [ "127.0.0.1" ] if host == "localhost"
      return [ "10.0.0.5" ] if host.end_with?(".internal")
      return [] if host == "nxdomain.test"

      [ "93.184.216.34" ]
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

  # A syntactically valid X-PAYMENT header. The transaction bytes are fake;
  # only the fake adapter or WebMock ever sees them.
  def payment_header(network: TESTNET[:caip2], scheme: "exact", version: 2)
    Base64.strict_encode64({
      x402Version: version, scheme: scheme, network: network,
      payload: { paymentGroup: [ Base64.strict_encode64("signed-txn") ], paymentIndex: 0 }
    }.to_json)
  end

  def stub_upstream(status: 200, body: { ok: true }.to_json)
    stub_request(:post, Catalog::Service::DEFAULT_UPSTREAM)
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end
end
