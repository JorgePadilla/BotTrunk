# frozen_string_literal: true

module Catalog
  # A catalog entry as the public site sees it.
  #
  # For now this is an in-memory list so the UI can be built and reviewed
  # before the schema exists. When the ActiveRecord model lands (Phase 1:
  # Seller, Service, Endpoint, Call …), keep this public interface —
  # `all`, `find(slug)`, and the readers below — so no component changes.
  class Service < Data.define(:slug, :name, :summary, :description, :category, :provider, :price_usdc, :latency, :success_rate,
                              :network, :asset, :facilitator, :inputs, :outputs, :upstream_url, :fulfiller, :status, :price_hnl)
    CATEGORIES = %w[Data Payments Messaging Verification Translation].freeze
    STATUSES = %w[live coming_soon].freeze

    # Test hook: the paid-call tests exercise the proxy path through a
    # coming-soon service, so they flip this on (see test_helper).
    mattr_accessor :treat_all_live, default: false

    # Phase 0: every service proxies to httpbin so the paid loop can be exercised
    # end to end before real upstreams exist.
    DEFAULT_UPSTREAM = "https://httpbin.org/anything"

    # `fulfiller:` names a Fulfillers::* class that runs in-process instead of
    # proxying to `upstream_url` (BotTrunk's own services).
    # `price_hnl:` marks a lempira-denominated service: its USDC price is
    # derived from the day's exchange rate (Pricing::LempiraDeposit), not fixed.
    def initialize(upstream_url: DEFAULT_UPSTREAM, fulfiller: nil, status: "live", price_hnl: nil, price_usdc: nil, **attrs) = super

    def built_in? = fulfiller.present?

    # Only live services take money. The rest stay in the catalog so agents and
    # people can see what is coming, but POST /s/:slug answers 503 for them.
    def live? = status == "live" || self.class.treat_all_live

    def self.categories = CATEGORIES

    def self.all = SEED

    def self.find(slug) = SEED.find { |s| s.slug == slug }

    def endpoint_url = "https://api.bottrunk.com/s/#{slug}"

    # Price in atomic units (µUSDC, 6 decimals) — the only form the payment layer uses.
    def price_atomic
      return Pricing::LempiraDeposit.new(amount_hnl: price_hnl).price_atomic if price_hnl

      (BigDecimal(price_usdc.to_s) * 1_000_000).to_i
    end

    # Price in USD for display; always derived from price_atomic so both kinds agree.
    def usd_price = BigDecimal(price_atomic) / 1_000_000

    def lempira? = price_hnl.present?

    def human_fulfilled? = provider == "Human-fulfilled"

    def to_param = slug

    # Case-insensitive substring match on the words people actually type.
    def matches?(query)
      q = query.to_s.downcase
      [ name, summary, description, category, provider, slug ].any? { |text| text.downcase.include?(q) }
    end
  end

  Service::SEED = [
    Service.new(
      slug: "scrape-markdown", name: "Scrape URL to Markdown", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::ScrapeMarkdown",
      summary: "Any public page as clean, LLM-ready markdown.",
      description: "Any public page as clean, LLM-ready markdown. Handles JS-rendered sites; links preserved, nav and footer stripped.",
      price_usdc: 0.005, latency: "0.8 s", success_rate: "99.6%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("url", "string", "Public http(s) URL to fetch.", "https://example.com/pricing"),
        Field.new("render_js", "boolean", "Reserved: headless rendering is not available yet; the flag is accepted and ignored."),
        Field.new("selector", "string", "Optional CSS selector to scope the extraction.")
      ],
      outputs: [
        Field.new("markdown", "string", "Body content as GitHub-flavored markdown.", "# Pricing\n\nSimple, honest pricing…"),
        Field.new("title", "string", "Document title.", "Pricing — Example"),
        Field.new("word_count", "integer", "Words in markdown, for budgeting tokens.", 412)
      ]
    ),
    *[ 1_000, 2_500, 5_000, 10_000 ].map do |hnl|
      Service.new(
        slug: "deposit-bac-#{hnl}", name: "Deposit L#{hnl.to_s.reverse.scan(/\d{1,3}/).join(",").reverse} to a BAC account", category: "Payments", provider: "Human-fulfilled",
        fulfiller: "Fulfillers::DepositBac", price_hnl: hnl,
        summary: "Pay someone in Honduras: L#{hnl.to_s.reverse.scan(/\d{1,3}/).join(",").reverse} lands in their BAC Credomatic account.",
        description: "Send #{hnl.to_s.reverse.scan(/\d{1,3}/).join(",").reverse} lempiras to any BAC Credomatic account in Honduras. Priced in USDC at the day's reference rate with a fixed spread and fee; a person makes the bank transfer within 24 hours and you get the receipt reference. Poll GET /orders/{order_id} for status.",
        latency: "≤ 24 h", success_rate: "100%",
        network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
        inputs: [
          Field.new("beneficiary_name", "string", "Account holder's name as the bank has it.", "María Pérez"),
          Field.new("account_number", "string", "BAC Credomatic account number (digits only).", "123456789"),
          Field.new("concept", "string", "Optional transfer concept, up to 60 characters.", "Pago factura 1043"),
          Field.new("contact_email", "string", "Optional: where to send the receipt.", "ops@example.com")
        ],
        outputs: [
          Field.new("order_id", "string", "Token to poll at /orders/{order_id}.", "8kPz3n…"),
          Field.new("status", "string", "pending until a person completes the transfer, then delivered.", "pending"),
          Field.new("amount_hnl", "integer", "Lempiras the beneficiary receives.", hnl),
          Field.new("eta", "string", "Fulfilment promise.", "within 24 hours"),
          Field.new("status_url", "string", "Where to poll.", "https://api.bottrunk.com/orders/8kPz3n…")
        ]
      )
    end,
    Service.new(
      slug: "pdf-extract", status: "coming_soon", name: "PDF to JSON", category: "Data", provider: "By BotTrunk",
      summary: "Send a PDF and a schema, get the fields back.",
      description: "Send a PDF URL and a JSON schema; get the fields back as JSON. Tables and multi-column layouts included.",
      price_usdc: 0.02, latency: "3.1 s", success_rate: "98.9%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("url", "string", "Public URL of the PDF."), Field.new("schema", "object", "JSON schema of the fields to extract.") ],
      outputs: [ Field.new("data", "object", "Extracted fields, matching the schema."), Field.new("pages", "integer", "Pages processed.") ]
    ),
    Service.new(
      slug: "screenshot", status: "coming_soon", name: "Screenshot a page", category: "Data", provider: "By BotTrunk",
      summary: "Full-page PNG of any URL.",
      description: "Full-page or viewport PNG of any URL, with optional dark mode and device emulation.",
      price_usdc: 0.01, latency: "1.9 s", success_rate: "99.2%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("url", "string", "Public http(s) URL."), Field.new("full_page", "boolean", "Capture the whole page. Default true.") ],
      outputs: [ Field.new("image_url", "string", "Signed URL of the PNG, valid for 1 hour."), Field.new("width", "integer", "Pixels."), Field.new("height", "integer", "Pixels.") ]
    ),
    Service.new(
      slug: "send-whatsapp", status: "coming_soon", name: "Send a WhatsApp message", category: "Messaging", provider: "Verified seller",
      summary: "Reach a phone number your agent can't.",
      description: "Deliver a message to a phone number your agent can't reach otherwise. Delivery receipt returned.",
      price_usdc: 0.05, latency: "2.4 s", success_rate: "97.8%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("to", "string", "E.164 phone number."), Field.new("text", "string", "Message body, up to 1,000 characters.") ],
      outputs: [ Field.new("message_id", "string", "Provider message id."), Field.new("status", "string", "sent, delivered, or failed.") ]
    ),
    Service.new(
      slug: "verify-business-hn", status: "coming_soon", name: "Verify a Honduran business", category: "Verification", provider: "Human-fulfilled",
      summary: "A local visits, photographs, checks the registry.",
      description: "A verified local visits the address, photographs the premises, and checks the mercantile registry. Proof bundle returned within 48 h.",
      price_usdc: 5.00, latency: "~36 h", success_rate: "100%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("name", "string", "Business name."), Field.new("address", "string", "Street address, city.") ],
      outputs: [ Field.new("verified", "boolean", "Whether the business exists at the address."), Field.new("proof", "object", "Photos and registry excerpt.") ]
    ),
    Service.new(
      slug: "translate-es-en", status: "coming_soon", name: "Translate ES ↔ EN", category: "Translation", provider: "Human-fulfilled",
      summary: "Human-reviewed, with Central American context.",
      description: "Human-reviewed translation with Central American idiom and legal terms handled correctly.",
      price_usdc: 0.50, latency: "~4 h", success_rate: "99.1%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("text", "string", "Up to 2,000 words."), Field.new("direction", "string", "es-en or en-es.") ],
      outputs: [ Field.new("text", "string", "Translated text."), Field.new("notes", "string", "Translator notes, if any.") ]
    )
  ].freeze
end
