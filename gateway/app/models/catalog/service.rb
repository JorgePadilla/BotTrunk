# frozen_string_literal: true

module Catalog
  # A catalog entry as the public site sees it.
  #
  # For now this is an in-memory list so the UI can be built and reviewed
  # before the schema exists. When the ActiveRecord model lands (Phase 1:
  # Seller, Service, Endpoint, Call …), keep this public interface —
  # `all`, `find(slug)`, and the readers below — so no component changes.
  class Service < Data.define(:slug, :name, :summary, :description, :category, :provider, :price_usdc, :latency, :success_rate,
                              :network, :asset, :facilitator, :inputs, :outputs, :upstream_url, :fulfiller)
    CATEGORIES = %w[Data Messaging Verification Translation].freeze

    # Phase 0: every service proxies to httpbin so the paid loop can be exercised
    # end to end before real upstreams exist.
    DEFAULT_UPSTREAM = "https://httpbin.org/anything"

    # `fulfiller:` names a Fulfillers::* class that runs in-process instead of
    # proxying to `upstream_url` (BotTrunk's own services).
    def initialize(upstream_url: DEFAULT_UPSTREAM, fulfiller: nil, **attrs) = super

    def built_in? = fulfiller.present?

    def self.categories = CATEGORIES

    def self.all = SEED

    def self.find(slug) = SEED.find { |s| s.slug == slug }

    def endpoint_url = "https://api.bottrunk.com/s/#{slug}"

    # Price in atomic units (µUSDC, 6 decimals) — the only form the payment layer uses.
    def price_atomic = (BigDecimal(price_usdc.to_s) * 1_000_000).to_i

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
        Field.new("url", "string", "Public http(s) URL to fetch."),
        Field.new("render_js", "boolean", "Reserved: headless rendering is not available yet; the flag is accepted and ignored."),
        Field.new("selector", "string", "Optional CSS selector to scope the extraction.")
      ],
      outputs: [
        Field.new("markdown", "string", "Body content as GitHub-flavored markdown."),
        Field.new("title", "string", "Document title."),
        Field.new("word_count", "integer", "Words in markdown, for budgeting tokens.")
      ]
    ),
    Service.new(
      slug: "pdf-extract", name: "PDF to JSON", category: "Data", provider: "By BotTrunk",
      summary: "Send a PDF and a schema, get the fields back.",
      description: "Send a PDF URL and a JSON schema; get the fields back as JSON. Tables and multi-column layouts included.",
      price_usdc: 0.02, latency: "3.1 s", success_rate: "98.9%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("url", "string", "Public URL of the PDF."), Field.new("schema", "object", "JSON schema of the fields to extract.") ],
      outputs: [ Field.new("data", "object", "Extracted fields, matching the schema."), Field.new("pages", "integer", "Pages processed.") ]
    ),
    Service.new(
      slug: "screenshot", name: "Screenshot a page", category: "Data", provider: "By BotTrunk",
      summary: "Full-page PNG of any URL.",
      description: "Full-page or viewport PNG of any URL, with optional dark mode and device emulation.",
      price_usdc: 0.01, latency: "1.9 s", success_rate: "99.2%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("url", "string", "Public http(s) URL."), Field.new("full_page", "boolean", "Capture the whole page. Default true.") ],
      outputs: [ Field.new("image_url", "string", "Signed URL of the PNG, valid for 1 hour."), Field.new("width", "integer", "Pixels."), Field.new("height", "integer", "Pixels.") ]
    ),
    Service.new(
      slug: "send-whatsapp", name: "Send a WhatsApp message", category: "Messaging", provider: "Verified seller",
      summary: "Reach a phone number your agent can't.",
      description: "Deliver a message to a phone number your agent can't reach otherwise. Delivery receipt returned.",
      price_usdc: 0.05, latency: "2.4 s", success_rate: "97.8%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("to", "string", "E.164 phone number."), Field.new("text", "string", "Message body, up to 1,000 characters.") ],
      outputs: [ Field.new("message_id", "string", "Provider message id."), Field.new("status", "string", "sent, delivered, or failed.") ]
    ),
    Service.new(
      slug: "verify-business-hn", name: "Verify a Honduran business", category: "Verification", provider: "Human-fulfilled",
      summary: "A local visits, photographs, checks the registry.",
      description: "A verified local visits the address, photographs the premises, and checks the mercantile registry. Proof bundle returned within 48 h.",
      price_usdc: 5.00, latency: "~36 h", success_rate: "100%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("name", "string", "Business name."), Field.new("address", "string", "Street address, city.") ],
      outputs: [ Field.new("verified", "boolean", "Whether the business exists at the address."), Field.new("proof", "object", "Photos and registry excerpt.") ]
    ),
    Service.new(
      slug: "translate-es-en", name: "Translate ES ↔ EN", category: "Translation", provider: "Human-fulfilled",
      summary: "Human-reviewed, with Central American context.",
      description: "Human-reviewed translation with Central American idiom and legal terms handled correctly.",
      price_usdc: 0.50, latency: "~4 h", success_rate: "99.1%",
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("text", "string", "Up to 2,000 words."), Field.new("direction", "string", "es-en or en-es.") ],
      outputs: [ Field.new("text", "string", "Translated text."), Field.new("notes", "string", "Translator notes, if any.") ]
    )
  ].freeze
end
