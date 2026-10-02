# frozen_string_literal: true

require "test_helper"

# Honeybadger sends request headers as keys like HTTP_X_PAYMENT, and gets
# Rails' filter list (config/initializers/honeybadger.rb). The signed payment
# and the deposit's bank account must never leave the server.
class FilterParametersTest < ActiveSupport::TestCase
  setup { @filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  test "payment headers are filtered" do
    filtered = @filter.filter("HTTP_PAYMENT_SIGNATURE" => "eyJ4NDAy", "HTTP_X_PAYMENT" => "eyJ4NDAy", "HTTP_ACCEPT" => "application/json")

    assert_equal "[FILTERED]", filtered["HTTP_PAYMENT_SIGNATURE"]
    assert_equal "[FILTERED]", filtered["HTTP_X_PAYMENT"]
    assert_equal "application/json", filtered["HTTP_ACCEPT"]
  end

  test "a deposit's bank account is filtered" do
    assert_equal "[FILTERED]", @filter.filter("account_number" => "1234567890")["account_number"]
  end

  test "Honeybadger uses the same list" do
    honeybadger_keys = Honeybadger.config.params_filters.map(&:to_s)

    %w[payment signature account].each { |key| assert_includes honeybadger_keys, key }
  end
end
