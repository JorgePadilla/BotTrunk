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

  def self.call(**overrides)
    Call.new({
      service_slug: "extract-links", pay_to: "UTWS33TM7IT7NINJSFWS5KVGL73G4ERJMYDKHF7KE4WDXHYO4L7V2PNMRE",
      network: "algorand:wGHE2Pwdvd7S12BL5FaOP20EGYesN73ktiC1qzkkit8=", asset: "31566704",
      amount: 20_000, commission: 3_000, seller_amount: 17_000,
      payer_address: "LQAWG3WUMKWTFGEFCCOET6JGPRKD2JFYPIJ6HPIRYAC6QDUJSBDVMCKPFQ",
      transaction_id: "FCWUMYHZINLKODF6YTKPBDRHXITZTOZYCOC7KRXHXXH6MYA5KMKQ",
      upstream_status: 200, upstream_latency_ms: 412, status: "settled", created_at: Time.current
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
