# frozen_string_literal: true

# Deposit orders and inquiries for mailer tests, plus a way to pretend
# ADMIN_EMAIL is (or is not) configured.
module MailHelpers
  ADMIN = "ops@bottrunk.test"

  def with_admin_email(address = ADMIN)
    previous = ENV["ADMIN_EMAIL"]
    ENV["ADMIN_EMAIL"] = address
    yield
  ensure
    ENV["ADMIN_EMAIL"] = previous
  end

  def build_order(**overrides)
    DepositOrder.create!({
      service_slug: "deposit-bac-1000", beneficiary_name: "Juana Martínez", bank: "BAC Credomatic",
      account_number: "731234567890", amount_hnl: 1_000, price_atomic: 42_510_122, fee_bps: 500,
      rate_hnl_per_usd: BigDecimal("26.20"), status: "pending", concept: "Invoice 42",
      contact_email: "buyer@example.com"
    }.merge(overrides))
  end

  def build_request(**overrides)
    ServiceRequest.create!({
      email: "buyer@example.com", details: "We need daily court filings from three Honduran courts, as JSON.",
      budget_atomic: 5_000_000
    }.merge(overrides))
  end

  def build_inquiry(**overrides)
    SellerInquiry.create!({
      email: "seller@example.com", service_name: "Court records HN", upstream_url: "https://api.example.com/records",
      price_atomic: 250_000, notes: "We have the scraper already."
    }.merge(overrides))
  end
end
