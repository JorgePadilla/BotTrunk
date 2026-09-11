# frozen_string_literal: true

# In-memory records for the mailer previews. Nothing here is saved, so the
# previews are safe to open against a production console as well as a local one.
module MailPreviewData
  def self.order(**overrides)
    DepositOrder.new({
      token: "dep_8mK2qR4vXbL", service_slug: "deposit-bac-2500", beneficiary_name: "Juana Martínez Andino",
      bank: "BAC Credomatic", account_number: "731234567890", amount_hnl: 2_500, price_atomic: 106_275_305,
      fee_bps: 500, rate_hnl_per_usd: BigDecimal("26.2000"), status: "pending", concept: "Factura 1042",
      contact_email: "agent-owner@example.com", created_at: 3.hours.ago
    }.merge(overrides))
  end

  def self.inquiry(**overrides)
    SellerInquiry.new({
      email: "dev@example.com", service_name: "Honduran court records lookup",
      upstream_url: "https://api.example.com/v1/records", price_atomic: 250_000,
      notes: "We already run this API for law firms. Rate limit is 20 req/s.", created_at: Time.current
    }.merge(overrides))
  end

  def self.digest(empty: false)
    queue = empty ? [] : [ order(amount_hnl: 2_500, created_at: 19.hours.ago),
                           order(amount_hnl: 1_000, beneficiary_name: "Carlos Fúnez", created_at: 4.hours.ago) ]
    Notifications::DailyDigest::Report.new(
      generated_at: Time.current, queue: queue, oldest: empty ? nil : "19 hours",
      owed_hnl: queue.sum(&:amount_hnl),
      delivered: empty ? [] : [ order(amount_hnl: 5_000, beneficiary_name: "Ana Zelaya", status: "delivered") ],
      refunded: [], calls: empty ? 0 : 14, volume: empty ? 0 : 1_260_000, commission: empty ? 0 : 189_000,
      inquiries: empty ? [] : [ inquiry ]
    ).to_h
  end
end
