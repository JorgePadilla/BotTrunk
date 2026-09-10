# frozen_string_literal: true

module X402Helpers
  TEST_PAY_TO = "UTWS33TM7IT7NINJSFWS5KVGL73G4ERJMYDKHF7KE4WDXHYO4L7V2PNMRE"
  TESTNET = Payments::Networks.algorand(:testnet)

  def service = Catalog::Service.find("scrape-markdown")

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
