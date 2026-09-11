# frozen_string_literal: true

module Catalog
  # A catalog entry as the public site sees it.
  #
  # For now this is an in-memory list so the UI can be built and reviewed
  # before the schema exists. When the ActiveRecord model lands (Phase 1:
  # Seller, Service, Endpoint, Call …), keep this public interface —
  # `all`, `find(slug)`, and the readers below — so no component changes.
  class Service < Data.define(:slug, :name, :summary, :description, :category, :provider, :price_usdc,
                              :network, :asset, :facilitator, :inputs, :outputs, :upstream_url, :fulfiller,
                              :status, :price_hnl, :family, :family_label, :family_summary)
    CATEGORIES = %w[Payments Data Verification Translation].freeze

    # live        — callable now, priced, in the Bazaar
    # on_request  — real work we do, arranged by email first (the endpoint answers 503)
    STATUSES = %w[live on_request].freeze

    # Phase 0: any service without its own fulfiller proxies here so the paid
    # loop can be exercised end to end before real upstreams exist.
    DEFAULT_UPSTREAM = "https://httpbin.org/anything"

    # Test hooks: the paid-call tests exercise the proxy path and the
    # not-live path through services that do not exist in the public catalog.
    mattr_accessor :treat_all_live, default: false
    mattr_accessor :extra, default: []

    # `fulfiller:` names a Fulfillers::* class that runs in-process instead of
    # proxying to `upstream_url` (BotTrunk's own services).
    # `price_hnl:` marks a lempira-denominated service: its USDC price comes
    # from the day's exchange rate (Pricing::LempiraDeposit), not a constant.
    # `family:` groups variants of one product (the deposit tiers) into a
    # single catalog card.
    def initialize(upstream_url: DEFAULT_UPSTREAM, fulfiller: nil, status: "live", price_hnl: nil, price_usdc: nil,
                   family: nil, family_label: nil, family_summary: nil, **attrs) = super

    def built_in? = fulfiller.present?

    # Only live services take money. `on_request` ones are listed so people
    # can see what we do, but POST /s/:slug answers 503 for them.
    def live? = status == "live" || self.class.treat_all_live

    def on_request? = status == "on_request"

    def self.categories = CATEGORIES

    def self.all = SEED + extra

    def self.find(slug) = all.find { |s| s.slug == slug }

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

    # Every service sharing this one's family, cheapest first (itself alone when it has none).
    def variants = family ? self.class.all.select { |s| s.family == family } : [ self ]

    # A request body an agent can copy: every input that carries an example.
    def example_body
      pairs = inputs.reject { |f| f.example.nil? }.map { |f| [ f.name, f.example ] }
      pairs = inputs.first(1).map { |f| [ f.name, f.example_value ] } if pairs.empty?
      pairs.to_h
    end

    # The MCP tool name bottrunk-mcp exposes for this service.
    def tool_name = "bottrunk_#{slug.tr("-", "_")}"

    # Case-insensitive substring match on the words people actually type.
    def matches?(query)
      q = query.to_s.downcase
      [ name, summary, description, category, provider, slug, family_label ].compact.any? { |text| text.downcase.include?(q) }
    end

    # Display groups for the catalog: variants of one product collapse into a
    # single card, everything else stands alone. Order is preserved.
    def self.grouped(services = all)
      services.group_by { |s| s.family || s.slug }.values
    end
  end

  Service::SEED = [
    *[ 1_000, 2_500, 5_000, 10_000 ].map do |hnl|
      pretty = hnl.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
      Service.new(
        slug: "deposit-bac-#{hnl}", name: "Deposit L#{pretty} to a BAC account", category: "Payments", provider: "Human-fulfilled",
        fulfiller: "Fulfillers::DepositBac", price_hnl: hnl, family: "deposit-bac", family_label: "Pay someone in Honduras",
        family_summary: "Send lempiras to any BAC Credomatic account in Honduras. A person makes the bank transfer within 24 hours and returns the receipt reference.",
        summary: "Send L#{pretty} in lempiras to any BAC Credomatic account. A person makes the transfer within 24 hours and you get the receipt.",
        description: "Send #{pretty} lempiras to any BAC Credomatic account in Honduras. Priced in USDC at the day's Banco Central reference rate with a fixed spread and fee; a person makes the bank transfer within 24 hours and returns the receipt reference. Poll GET /orders/{order_id} for status.",
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
      slug: "scrape-markdown", name: "Scrape URL to Markdown", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::ScrapeMarkdown",
      summary: "Any public page as clean, LLM-ready markdown.",
      description: "Any public page as clean, LLM-ready markdown. Nav, scripts and footers stripped; links and structure preserved. Optional CSS selector to scope the extraction.",
      price_usdc: 0.09,
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
    Service.new(
      slug: "page-metadata", name: "Page metadata", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::PageMetadata",
      summary: "Title, description, OpenGraph, favicon and feeds — without reading the page.",
      description: "Everything a machine needs to describe a page it has not read: title, meta description, canonical URL, language, favicon, the full OpenGraph and Twitter card sets, any RSS/Atom feeds it advertises, and its robots directive. One request instead of fetching and parsing HTML yourself.",
      price_usdc: 0.02,
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("url", "string", "Public http(s) URL.", "https://stripe.com") ],
      outputs: [
        Field.new("title", "string", "Document title.", "Stripe | Financial Infrastructure"),
        Field.new("description", "string", "Meta or OpenGraph description."),
        Field.new("canonical", "string", "Canonical URL, absolute."),
        Field.new("open_graph", "object", "Every og:* tag, keyed without the prefix."),
        Field.new("twitter", "object", "Every twitter:* tag."),
        Field.new("feeds", "array", "RSS/Atom feeds declared in the head."),
        Field.new("favicon", "string", "Absolute favicon URL.")
      ]
    ),
    Service.new(
      slug: "extract-links", name: "Extract links", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::ExtractLinks",
      summary: "Every link on a page, absolute, de-duplicated, split internal vs external.",
      description: "Every link on a page resolved to an absolute URL, de-duplicated, with its anchor text and rel, and split into internal and external. What a crawling agent needs to decide where to go next, without downloading and parsing the HTML itself.",
      price_usdc: 0.02,
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("url", "string", "Public http(s) URL.", "https://example.com"),
        Field.new("same_host", "boolean", "Only links on the same host. Default false."),
        Field.new("limit", "integer", "Maximum links to return (1–500). Default 500.", 100)
      ],
      outputs: [
        Field.new("links", "array", "Objects with url, text, rel and internal."),
        Field.new("total", "integer", "Links found after de-duplication.", 87),
        Field.new("internal", "integer", "How many are on the same host.", 64),
        Field.new("external", "integer", "How many point elsewhere.", 23)
      ]
    ),
    Service.new(
      slug: "url-health", name: "URL health & TLS check", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::UrlHealth",
      summary: "Status, redirect chain, timing and certificate expiry for any URL.",
      description: "Is this URL alive, where does it end up, and when does its certificate expire? Returns the status code, the full redirect chain with per-hop timings, the response headers that matter, and the TLS issuer and expiry date. The checks a careful human runs before trusting a link.",
      price_usdc: 0.02,
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("url", "string", "Public http(s) URL.", "https://bottrunk.com") ],
      outputs: [
        Field.new("ok", "boolean", "True when the final status is below 400.", true),
        Field.new("status", "integer", "Final HTTP status.", 200),
        Field.new("final_url", "string", "Where the redirects ended."),
        Field.new("chain", "array", "Each hop with its status and response time."),
        Field.new("response_ms", "integer", "Total time across hops.", 284),
        Field.new("tls", "object", "issuer, expires_at, days_left — for https URLs.")
      ]
    ),
    Service.new(
      slug: "domain-dns", name: "Domain DNS records", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::DomainDns",
      summary: "A, AAAA, MX, NS, TXT and CNAME in one call, plus who runs the mail.",
      description: "The full DNS record set of a domain in one call — A, AAAA, MX, NS, TXT, CNAME — with a read on what the records give away: which provider handles the mail, whether SPF and DMARC are set, and which services the domain has verified. Useful for checking whether a company is real and who hosts it.",
      price_usdc: 0.03,
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("domain", "string", "Hostname, with or without scheme.", "stripe.com") ],
      outputs: [
        Field.new("a", "array", "IPv4 addresses.", [ "34.120.54.55" ]),
        Field.new("mx", "array", "Mail exchangers with preference, lowest first."),
        Field.new("ns", "array", "Nameservers."),
        Field.new("txt", "array", "TXT records, joined."),
        Field.new("hints", "object", "email provider, spf, dmarc, verifications.")
      ]
    ),
    Service.new(
      slug: "verify-business-hn", name: "Verify a Honduran business", category: "Verification", provider: "Human-fulfilled", status: "on_request",
      summary: "A local visits the address, photographs the premises and checks the registry.",
      description: "A verified local visits the address, photographs the premises, confirms the business is operating, and checks the mercantile registry. Proof bundle (photos, coordinates, registry excerpt) returned within 48 hours. Arranged by email first so we can agree scope and city; then it is a normal paid call.",
      price_usdc: 25.00,
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("name", "string", "Business name."), Field.new("address", "string", "Street address, city.") ],
      outputs: [ Field.new("verified", "boolean", "Whether the business exists and operates at the address."), Field.new("proof", "object", "Photos, coordinates and registry excerpt.") ]
    ),
    Service.new(
      slug: "translate-es-en", name: "Translate ES ↔ EN (human)", category: "Translation", provider: "Human-fulfilled", status: "on_request",
      summary: "Human-reviewed translation with Central American context, up to 1,000 words.",
      description: "Human translation and review, up to 1,000 words, with Central American idiom and legal terminology handled correctly — the difference between a machine translation and something you can sign. Arranged by email first so we can agree the deadline; then it is a normal paid call.",
      price_usdc: 15.00,
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("text", "string", "Up to 1,000 words."), Field.new("direction", "string", "es-en or en-es.") ],
      outputs: [ Field.new("text", "string", "Translated text."), Field.new("notes", "string", "Translator notes, if any.") ]
    )
  ].freeze
end
