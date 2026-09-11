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

# No DNS in tests: every host is "public" except the ones that look private.
Fulfillers::ScrapeMarkdown.resolver = X402Helpers::FakeResolver

module ActiveSupport
  class TestCase
    include X402Helpers

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
