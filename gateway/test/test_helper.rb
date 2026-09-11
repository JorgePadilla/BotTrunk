ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "view_component/test_case"
require "webmock/minitest"

Dir[Rails.root.join("test/support/**/*.rb")].each { |f| require f }

# Deterministic x402 settings for every test, independent of credentials/ENV.
Rails.configuration.x402.pay_to = X402Helpers::TEST_PAY_TO
Rails.configuration.x402.network = :testnet
Rails.configuration.x402.public_host = "https://api.bottrunk.test"

# Lempira prices are deterministic in tests: L26.20 per dollar, no feed.
Rates::UsdHnl.stub_rate = "26.20"

# Everything in the public catalog is either built-in or human-fulfilled, so the
# proxy path and the not-live path get services that exist only in tests.
Catalog::Service.extra = [
  Catalog::Service.new(
    slug: "test-proxy", name: "Proxied test service", category: "Data", provider: "Verified seller",
    summary: "A seller's own API behind our paywall.", description: "Exists only in the test suite.",
    price_usdc: 0.02, network: "Algorand TestNet", asset: "USDC", facilitator: "GoPlausible",
    inputs: [ Catalog::Field.new("url", "string", "Anything.", "https://example.com") ],
    outputs: [ Catalog::Field.new("ok", "boolean", "Whatever the upstream says.") ]
  ),
  Catalog::Service.new(
    slug: "test-on-request", name: "Not live test service", category: "Verification", provider: "Human-fulfilled",
    status: "on_request", summary: "Listed but not callable.", description: "Exists only in the test suite.",
    price_usdc: 1.00, network: "Algorand TestNet", asset: "USDC", facilitator: "GoPlausible",
    inputs: [ Catalog::Field.new("name", "string", "Anything.") ], outputs: [ Catalog::Field.new("ok", "boolean", "Nope.") ]
  )
]

# The paid-call tests drive services that are not live in the seed.
Catalog::Service.treat_all_live = true

# No DNS in tests: every host is "public" except the ones that look private.
Fulfillers::Base.resolver = X402Helpers::FakeResolver

module ActiveSupport
  class TestCase
    include X402Helpers
    include ActiveJob::TestHelper
    include ActionMailer::TestHelper
    include MailHelpers

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
