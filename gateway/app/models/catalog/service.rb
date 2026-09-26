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
                              :status, :price_hnl, :family, :family_label, :family_summary, :behaviour, :job)
    CATEGORIES = %w[Payments Data Verification Translation Procurement].freeze

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
    # `job:` turns an entry into work a person does: what the buyer must supply,
    # how long they are promised, and how many can be in flight at once. With
    # it, `Fulfillers::HumanJob` serves the whole service and no new class is
    # written — the catalog entry *is* the service.
    def initialize(upstream_url: DEFAULT_UPSTREAM, fulfiller: nil, status: "live", price_hnl: nil, price_usdc: nil,
                   family: nil, family_label: nil, family_summary: nil, behaviour: [], job: nil, **attrs) = super

    # What a payer is actually buying, beyond the schema: the decisions this
    # service makes on their behalf. Published because the alternative is that
    # people discover them by paying. The limits every built-in shares
    # (`Fulfillers::Base`) are appended by `shared_behaviour`.
    def documented_behaviour = behaviour + (built_in? ? shared_behaviour : [])

    def shared_behaviour
      [
        [ "Size and time", "Pages over 2 MB are refused with `page too large`. Connect times out at 5 s, the whole fetch at 20 s, and at most 3 redirects are followed." ],
        [ "Who we look like", "Requests go out as `BotTrunk/0.1 (+https://bottrunk.com/docs)`. Sites that block unknown agents will block this one." ],
        [ "Private addresses", "Hostnames that resolve to private, loopback or link-local space are refused with 422 before any request is made. Do not point this at localhost or an intranet." ],
        [ "Method", "`POST` only. A `GET` on the same path returns this page." ]
      ]
    end

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

    # The promise printed on the page and returned to a polling agent. Kept
    # here so the page, the 202 body and the admin queue cannot disagree.
    def job_eta = job&.dig(:eta)

    def job_capacity = job&.dig(:capacity)

    def job_fields = job&.dig(:required) || {}

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
        fulfiller: "Fulfillers::DepositBac", price_hnl: hnl, family: "deposit-bac", family_label: "Pay a person's bank account",
        family_summary: "Put money in a person's bank account. A human makes the transfer within 24 hours and returns the receipt reference. Live corridor: BAC Credomatic accounts, paid in lempiras.",
        summary: "Send L#{pretty} in lempiras to any BAC Credomatic account. A person makes the transfer within 24 hours and you get the receipt.",
        description: "Send #{pretty} lempiras to any BAC Credomatic account in Honduras. Priced in USDC at the day's Banco Central reference rate with a fixed spread and fee; a person makes the bank transfer within 24 hours and returns the receipt reference. Poll GET /orders/{order_id} for status.",
        network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
        inputs: [
          Field.new("beneficiary_name", "string", "Account holder's name as the bank has it.", "María Pérez"),
          Field.new("account_number", "string", "BAC Credomatic account number (digits only).", "123456789"),
          Field.new("concept", "string", "Optional transfer concept, up to 60 characters.", "Pago factura 1043"),
          Field.new("contact_email", "string", "Optional: emailed a receipt now and the bank reference when the transfer lands.", "ops@example.com")
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
      behaviour: [
        [ "What is stripped", "`script`, `style`, `noscript`, `nav`, `footer`, `header`, `aside`, `form`, `iframe`, `svg`, `template` — removed before conversion, so their text never reaches you." ],
        [ "What is kept", "Headings, paragraphs, lists, tables, links and emphasis, as GitHub-flavored markdown. Runs of blank lines are collapsed." ],
        [ "Where it reads from", "Your `selector` if you give one. Otherwise the first of `main`, `article`, `body`." ],
        [ "A selector that matches nothing", "Refused with 422 and not charged, rather than quietly returning the whole page. A malformed selector is refused the same way." ],
        [ "Non-HTML URLs", "A URL that answers with JSON, a PDF or an image is refused with 422. A server that sends no content-type at all is scraped anyway." ],
        [ "No JavaScript", "The page is fetched, not rendered, so a site that builds its content client-side returns almost nothing. When that happens, `scrape-markdown-js` renders it in a real browser first." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("url", "string", "Public http(s) URL to fetch.", "https://example.com/pricing"),
        Field.new("render_js", "boolean", "Deprecated and ignored. Rendering is its own service: `scrape-markdown-js`."),
        Field.new("selector", "string", "Optional CSS selector to scope the extraction.")
      ],
      outputs: [
        Field.new("markdown", "string", "Body content as GitHub-flavored markdown.", "# Pricing\n\nSimple, honest pricing…"),
        Field.new("title", "string", "Document title.", "Pricing — Example"),
        Field.new("word_count", "integer", "Words in markdown, for budgeting tokens.", 412)
      ]
    ),
    Service.new(
      slug: "scrape-markdown-js", name: "Scrape URL to Markdown (rendered)", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::ScrapeMarkdownJs",
      summary: "Any page as clean markdown, after its JavaScript has run.",
      description: "The same clean, LLM-ready markdown as scrape-markdown, except the page is loaded in a real browser first. Use it on anything that builds its content client-side — single-page apps, dashboards, most modern pricing pages — where a plain HTTP fetch returns an empty shell. Optional CSS selector to scope the extraction, and an optional selector to wait for before the page is read.",
      price_usdc: 0.29,
      behaviour: [
        [ "When to pay for this", "Only when plain `scrape-markdown` comes back thin or empty. If the page ships its content in the HTML, that one is a third of the price and returns the same markdown." ],
        [ "What is stripped", "Identical to `scrape-markdown`: `script`, `style`, `noscript`, `nav`, `footer`, `header`, `aside`, `form`, `iframe`, `svg`, `template` — same pipeline, different source." ],
        [ "Waiting for content", "`wait_for` takes a CSS selector the browser waits for before the page is read — the difference between catching a dashboard mid-spinner and catching it after the data arrives." ],
        [ "A selector that matches nothing", "Refused with 422 and not charged, exactly as on `scrape-markdown`." ],
        [ "If the renderer is unavailable", "The call fails and is never settled, so it costs you nothing." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("url", "string", "Public http(s) URL to render.", "https://example.com/app"),
        Field.new("wait_for", "string", "Optional CSS selector to wait for before reading the page.", "table.results"),
        Field.new("selector", "string", "Optional CSS selector to scope the extraction.")
      ],
      outputs: [
        Field.new("markdown", "string", "Body content as GitHub-flavored markdown.", "# Pricing\n\nSimple, honest pricing…"),
        Field.new("title", "string", "Document title.", "Pricing — Example"),
        Field.new("word_count", "integer", "Words in markdown, for budgeting tokens.", 412)
      ]
    ),
    Service.new(
      slug: "screenshot-url", name: "Screenshot a page", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::ScreenshotUrl",
      summary: "A PNG of any page as a browser renders it, base64 in the response.",
      description: "A picture of a page, taken in a real browser after its JavaScript has run. An agent cannot look at a page; this is the closest it gets — checking that a deploy renders, that a banner says what it claims, or handing a person an image of what the agent found. Viewport is yours to set, or capture the full scrolling page.",
      price_usdc: 0.08,
      behaviour: [
        [ "What comes back", "The PNG as base64 in `image_base64`, with the real pixel size read off the file. Base64 is about a third larger than the file itself; budget for that." ],
        [ "Size limit", "A render over 1.5 MB is refused with 422 and not charged, rather than returning a JSON body nobody wants. Narrow the viewport or drop `full_page` and try again." ],
        [ "Viewport", "`width` and `height` are clamped to 240–3840. With `full_page` the height grows to whatever the page needs, so the returned `height` is what was captured, not what was asked for." ],
        [ "Waiting for content", "`wait_for` takes a CSS selector the browser waits for before the shutter — the difference between catching a page mid-spinner and after its data lands." ],
        [ "If the renderer is busy", "The free renderer runs one browser at a time. A busy answer is retried once, then the call fails and is never settled, so it costs you nothing." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("url", "string", "Public http(s) URL to capture.", "https://example.com/pricing"),
        Field.new("full_page", "boolean", "Capture the whole scrolling page instead of one viewport."),
        Field.new("width", "integer", "Viewport width in pixels, 240–3840. Default 1280.", 1280),
        Field.new("height", "integer", "Viewport height in pixels, 240–3840. Default 800.", 800),
        Field.new("wait_for", "string", "Optional CSS selector to wait for before capturing.", "main img")
      ],
      outputs: [
        Field.new("image_base64", "string", "The PNG, base64-encoded.", "iVBORw0KGgoAAAANSUhEUg…"),
        Field.new("width", "integer", "Captured width in pixels.", 1280),
        Field.new("height", "integer", "Captured height in pixels.", 800),
        Field.new("bytes", "integer", "Size of the PNG before encoding.", 22268),
        Field.new("captured_at", "string", "When the shot was taken, UTC.", "2026-09-26T01:12:04Z")
      ]
    ),
    Service.new(
      slug: "pdf-url", name: "Page to PDF", category: "Data", provider: "By BotTrunk", fulfiller: "Fulfillers::PdfUrl",
      summary: "Any page printed to PDF by a real browser, base64 in the response.",
      description: "A page printed to PDF the way a browser prints it, after its JavaScript has run — an invoice, a receipt, a terms page as it stood on the day. The paper a person keeps, produced by an agent that cannot print. Choose the paper size and orientation; backgrounds are printed.",
      price_usdc: 0.10,
      behaviour: [
        [ "What comes back", "The PDF as base64 in `pdf_base64`. Base64 is about a third larger than the file itself; budget for that." ],
        [ "Size limit", "A document over 1.5 MB is refused with 422 and not charged. Long pages hit this before short ones do." ],
        [ "Paper", "`format` accepts a4, letter, legal, tabloid, a3 or a5. Anything else falls back to A4 rather than refusing — you asked for a PDF and you get one, with `paper` saying which was used." ],
        [ "Waiting for content", "`wait_for` takes a CSS selector the browser waits for before printing." ],
        [ "If the renderer is busy", "The free renderer runs one browser at a time. A busy answer is retried once, then the call fails and is never settled, so it costs you nothing." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("url", "string", "Public http(s) URL to print.", "https://example.com/invoice/8812"),
        Field.new("format", "string", "Paper size: a4, letter, legal, tabloid, a3, a5. Default a4.", "a4"),
        Field.new("landscape", "boolean", "Print landscape instead of portrait."),
        Field.new("wait_for", "string", "Optional CSS selector to wait for before printing.", "table.line-items")
      ],
      outputs: [
        Field.new("pdf_base64", "string", "The PDF, base64-encoded.", "JVBERi0xLjQKJeLjz9MK…"),
        Field.new("paper", "string", "Paper size used.", "a4"),
        Field.new("bytes", "integer", "Size of the PDF before encoding.", 48210),
        Field.new("captured_at", "string", "When it was printed, UTC.", "2026-09-26T01:12:04Z")
      ]
    ),
    Service.new(
      slug: "email-check", name: "Email address check", category: "Verification", provider: "By BotTrunk", fulfiller: "Fulfillers::EmailCheck",
      summary: "Syntax, mail records, and whether an address is disposable, free or a role account.",
      description: "What can be told about an email address without sending anything to it: whether the syntax is valid, whether the domain can receive mail at all, and whether it is a known disposable provider, a free consumer provider, or a role address like support@ that no single person reads. For filtering a signup list or deciding whether a contact address is worth writing to.",
      price_usdc: 0.002,
      behaviour: [
        [ "What this is not", "Not a mailbox check. Proving an address exists needs an SMTP probe, which is unreliable and gets the prober blocked, so we do not do it. No mail is ever sent." ],
        [ "Deliverable domain", "True when the domain publishes MX records, or an A record that mail can fall back to. It says the domain can receive mail, not that this mailbox does." ],
        [ "Bad syntax", "Answered 200 with `valid_syntax: false` and no DNS lookup — a malformed address is a fact about the input, not a failure." ],
        [ "Disposable and free lists", "Known-provider lists, not exhaustive. A false on either means we did not recognise it." ],
        [ "If DNS is unreachable", "The call fails and is never settled, so it costs you nothing." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [ Field.new("email", "string", "Address to check.", "support@stripe.com") ],
      outputs: [
        Field.new("valid_syntax", "boolean", "Whether the address parses as an email address.", true),
        Field.new("domain", "string", "Domain part, lowercased.", "stripe.com"),
        Field.new("mx", "array", "Mail exchangers, lowest preference first.", [ "aspmx.l.google.com" ]),
        Field.new("deliverable_domain", "boolean", "Whether the domain can receive mail at all.", true),
        Field.new("disposable", "boolean", "Known disposable-provider domain.", false),
        Field.new("free_provider", "boolean", "Known free consumer provider.", false),
        Field.new("role_account", "boolean", "Role address like support@ or billing@.", true)
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
      slug: "rfq-global", name: "Get real supplier quotes", category: "Procurement", provider: "Human-fulfilled",
      fulfiller: "Fulfillers::HumanJob", price_usdc: 250.00,
      job: { eta: "within 5 business days", capacity: 12, required: {
        "brief" => { min: 40, max: 4_000, hint: "the specification, in your own words" },
        "quantity" => { hint: "how many, in whatever unit the trade uses" },
        "destination" => { hint: "where the goods must be delivered or quoted to" }
      } },
      summary: "A person phones and emails suppliers anywhere and comes back with real quotes.",
      description: "Describe what you want to buy, how much of it and where it has to land. A person contacts up to ten suppliers by phone and email, in English or Spanish, chases the ones who go quiet, and returns structured quotes: unit price, lead time, minimum order, incoterms, and who said what. Five business days, or the payment is returned. An agent can find two hundred suppliers in a minute and cannot get one of them to answer a question; this is that gap, closed by a person.",
      behaviour: [
        [ "What you get back", "One entry per supplier actually reached — price, lead time, MOQ, incoterms, contact and the date of the conversation — plus a note on who never replied. Poll `GET /orders/{order_id}` until status is `delivered`." ],
        [ "How long it takes", "Five business days. Suppliers answer when they answer, and the chasing is most of the work." ],
        [ "If we cannot deliver", "The USDC is returned in full and the refund transaction is recorded on the order. You are never charged for quotes that did not arrive." ],
        [ "When the queue is full", "Answered 429 and not charged. One person carries this, and a promise we cannot keep is worth less than an honest refusal." ],
        [ "What this is not", "Not a directory lookup and not a scrape. If a published price list would answer your question, `scrape-markdown` costs nine cents." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("brief", "string", "What you want quoted: the specification, in your own words.", "500 units of 20 oz double-wall stainless steel water bottles, powder-coated matte black, single-colour logo on one side."),
        Field.new("quantity", "string", "How many, in whatever unit the trade uses.", "500 units"),
        Field.new("destination", "string", "Where the goods must be delivered or quoted to.", "Port of Houston, TX"),
        Field.new("contact_email", "string", "Optional: emailed when the quotes are in.", "buyer@example.com")
      ],
      outputs: [
        Field.new("order_id", "string", "Token to poll at /orders/{order_id}.", "8kPz3nQ4vR7mB2xY6wLd"),
        Field.new("status", "string", "pending until the quotes are in, then delivered.", "pending"),
        Field.new("eta", "string", "Fulfilment promise.", "within 5 business days"),
        Field.new("result", "object", "Quotes per supplier, once delivered."),
        Field.new("status_url", "string", "Where to poll.", "https://api.bottrunk.com/orders/8kPz3nQ4vR7mB2xY6wLd")
      ]
    ),
    *[ 500, 1_000 ].map do |usdc|
      Service.new(
        slug: "btc-#{usdc}", name: "Buy #{usdc} USDC of bitcoin", category: "Payments", provider: "Human-fulfilled",
        fulfiller: "Fulfillers::BtcDelivery", price_usdc: usdc.to_f, status: "on_request",
        family: "btc", family_label: "Bitcoin to an address",
        family_summary: "Pay in USDC on Algorand, receive bitcoin at the address you give. The rate and the spread are quoted before you pay, and frozen into the order.",
        job: { eta: "within 24 hours", capacity: 3, required: {
          "btc_address" => { min: 26, max: 62, hint: "the address the bitcoin should arrive at" }
        } },
        summary: "Pay #{usdc} USDC on Algorand, receive bitcoin at your address within 24 hours.",
        description: "Send #{usdc} USDC on Algorand and receive bitcoin at the address you name. The quote — spot price, your rate, the spread and exactly how much bitcoin arrives — is returned before you pay and frozen into the order, so the number you agreed to is the number that gets sent. A person completes the transfer and records the bitcoin transaction id against your order.",
        behaviour: [
          [ "Arranged first, for now", "This answers 503 until a licensed partner is behind it. Exchanging one asset for another is a regulated activity wherever the buyer is calling from, so nothing can be charged here until the compliance sits with someone authorised to carry it. Write first and we will tell you where that stands." ],
          [ "The spread is stated, not hidden", "You are charged spot plus #{(Pricing::BtcDelivery.spread_bps / 100.0).round(2)} %. The response shows the spot price, your rate and what the delivered bitcoin is worth at spot, so the cost of using this rather than an exchange is a number you can read before you pay." ],
          [ "The quote is frozen", "Taken at the moment you order and recorded on it. If bitcoin moves between your payment and the send, the amount you were quoted is still the amount that arrives." ],
          [ "No fresh price, no quote", "If we cannot get a bitcoin price under half an hour old, the call is refused and nothing is charged. A stale quote is a loss for one of us and we will not guess which." ],
          [ "The address is yours to get right", "We check the shape of it and a person checks it again before sending, but bitcoin sent to a valid address you mistyped cannot be recalled." ]
        ],
        network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
        inputs: [
          Field.new("btc_address", "string", "Where the bitcoin should arrive.", "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"),
          Field.new("contact_email", "string", "Optional: emailed when it is sent.", "buyer@example.com")
        ],
        outputs: [
          Field.new("order_id", "string", "Token to poll at /orders/{order_id}.", "8kPz3nQ4vR7mB2xY6wLd"),
          Field.new("quote", "object", "Spot, your rate, the spread, and the bitcoin that will arrive."),
          Field.new("status", "string", "pending until sent, then delivered.", "pending"),
          Field.new("result", "object", "The bitcoin transaction id, once sent.")
        ]
      )
    end,
    Service.new(
      slug: "prices-hn", name: "What things cost in Honduras", category: "Data", provider: "By BotTrunk",
      fulfiller: "Fulfillers::PricesHn", price_usdc: 0.05, status: "on_request",
      summary: "Farmgate coffee, the basic basket, fuel and the street dollar — observed in person.",
      description: "What things actually cost on the ground in Honduras, recorded by a person who went and asked: coffee at the farmgate, the basic food basket, fuel, and the street rate for dollars. The published number and the real number are different here, and the gap is invisible from outside the country. Every reading carries the day it was observed and how it was learned, so you can judge it rather than trust it.",
      behaviour: [
        [ "Where the numbers come from", "A person on a weekly round — phone calls to exporters, visits to markets and stations. Each reading names its source and the day it was made." ],
        [ "Freshness is stated, never hidden", "Every reading carries `days_old`, and anything older than three weeks is marked `stale: true` rather than served quietly as current." ],
        [ "Asking for something we do not price", "Answered 422 with the list of what is priced, and not charged. You pay for observations, not for an empty list." ],
        [ "Dollars are converted, not observed", "`price_usd` uses the day's Banco Central reference rate. The lempira figure is the observation; the dollar figure is arithmetic." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("items", "array", "Optional: which readings you want. Omit for everything priced.", [ "coffee-quintal", "fuel-diesel" ]),
        Field.new("city", "string", "Optional: Tegucigalpa or San Pedro Sula.", "Tegucigalpa")
      ],
      outputs: [
        Field.new("prices", "array", "One reading per item: price_hnl, price_usd, unit, observed_at, days_old, stale, source."),
        Field.new("as_of", "string", "Newest observation in the response.", "2026-09-22"),
        Field.new("rate_hnl_per_usd", "string", "Reference rate used for the dollar column.", "26.2000")
      ]
    ),
    Service.new(
      slug: "human-review", name: "Human review and sign-off", category: "Verification", provider: "Human-fulfilled",
      fulfiller: "Fulfillers::HumanJob", price_usdc: 3.00,
      job: { eta: "within 24 hours", capacity: 25, required: {
        "question" => { min: 20, max: 2_000, hint: "what you want judged, asked plainly" },
        "material" => { min: 3, max: 4_000, hint: "the text, a URL, or whatever should be looked at" }
      } },
      summary: "A person looks at your work and answers, with their name on the answer.",
      description: "Ask a person to judge something a model cannot settle alone: is this translation right, does this photo show what the seller claims, is this clause unusual, does this page look broken. You get a plain answer and the reasoning behind it, from someone who is accountable for it. Within 24 hours. An opinion a model produces in a second carries no weight because nobody stands behind it; this is the same sentence with a person behind it.",
      behaviour: [
        [ "What you get back", "A direct answer, the reasoning, and how confident the reviewer is. Poll `GET /orders/{order_id}` until status is `delivered`." ],
        [ "What we will not do", "No legal, medical or financial advice — that needs a licensed professional, and this is not one. Questions that need a licence are refused and the payment returned." ],
        [ "Ambiguity is an answer", "If the material does not settle the question, the reviewer says so rather than guessing. That is still delivered and still charged, because looking carefully is the work." ],
        [ "When the queue is full", "Answered 429 and not charged." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("question", "string", "What you want judged, asked plainly.", "Does this photo show a working commercial kitchen, or a domestic one?"),
        Field.new("material", "string", "The text, a URL, or whatever should be looked at.", "https://example.com/listing/8812"),
        Field.new("contact_email", "string", "Optional: emailed with the answer.", "buyer@example.com")
      ],
      outputs: [
        Field.new("order_id", "string", "Token to poll at /orders/{order_id}.", "8kPz3nQ4vR7mB2xY6wLd"),
        Field.new("status", "string", "pending until reviewed, then delivered.", "pending"),
        Field.new("eta", "string", "Fulfilment promise.", "within 24 hours"),
        Field.new("result", "object", "The answer, the reasoning and the reviewer's confidence.")
      ]
    ),
    Service.new(
      slug: "verify-business-hn", name: "Verify a Honduran business", category: "Verification", provider: "Human-fulfilled",
      fulfiller: "Fulfillers::HumanJob", price_usdc: 45.00,
      job: { eta: "within 5 business days", capacity: 6, required: {
        "business_name" => { min: 2, max: 120, hint: "the name as it should appear at the address" },
        "address" => { min: 8, max: 300, hint: "street address and city" }
      } },
      summary: "A local visits the address, photographs the premises and checks the registry.",
      description: "A verified local goes to the address, photographs the premises, confirms the business is operating, and checks the mercantile registry. You get back what was found — photos, what the sign says, whether anyone was there, and the registry excerpt — not a verdict dressed up as data. Five business days, or the payment is returned.",
      behaviour: [
        [ "What you get back", "A written report with the photo album link, what the registry says, and whether the business was operating when the visit happened. Poll `GET /orders/{order_id}` until status is `delivered`." ],
        [ "An address that does not exist", "Still delivered, and still charged: the visit happened and the answer — nothing there — is usually the one worth paying for." ],
        [ "Cities we cover", "Tegucigalpa and San Pedro Sula reliably. Anywhere else, we ask first; if we cannot get there the payment is returned in full." ],
        [ "When the queue is full", "Answered 429 and not charged. One person carries this." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("business_name", "string", "Business name as it should appear at the address.", "Ferretería El Progreso"),
        Field.new("address", "string", "Street address and city.", "Blvd. Morazán, Tegucigalpa"),
        Field.new("contact_email", "string", "Optional: emailed when the report is in.", "buyer@example.com")
      ],
      outputs: [
        Field.new("order_id", "string", "Token to poll at /orders/{order_id}.", "8kPz3nQ4vR7mB2xY6wLd"),
        Field.new("status", "string", "pending until the visit is done, then delivered.", "pending"),
        Field.new("eta", "string", "Fulfilment promise.", "within 5 business days"),
        Field.new("result", "object", "The report: what was found, photos, registry excerpt.")
      ]
    ),
    Service.new(
      slug: "translate-es-en", name: "Translate ES ↔ EN (human)", category: "Translation", provider: "Human-fulfilled",
      fulfiller: "Fulfillers::HumanJob", price_usdc: 60.00,
      job: { eta: "within 3 business days", capacity: 8, required: {
        "text" => { min: 20, max: 12_000, hint: "the text to translate, up to about 1,000 words" },
        "direction" => { min: 5, max: 5, hint: "es-en or en-es" }
      } },
      summary: "Human-reviewed translation with Central American context, up to 1,000 words.",
      description: "A person translates and reviews it — up to 1,000 words — with Central American idiom and legal terminology handled correctly. The difference between a machine translation and something you can put your name on. Three business days, or the payment is returned.",
      behaviour: [
        [ "What you get back", "The translated text and the translator's notes on anything ambiguous. Poll `GET /orders/{order_id}` until status is `delivered`." ],
        [ "Length", "Up to about 1,000 words per call. Longer text is refused with 422 and not charged — split it, or ask us for a quote." ],
        [ "Direction", "`es-en` or `en-es`. Anything else is refused with 422 and not charged." ],
        [ "Not certified", "This is a human translation, not a sworn or notarised one. If you need a translation that a court or a registry will accept, write first." ]
      ],
      network: "Algorand MainNet", asset: "USDC", facilitator: "GoPlausible",
      inputs: [
        Field.new("text", "string", "The text to translate, up to about 1,000 words.", "Estimado cliente, adjuntamos la factura…"),
        Field.new("direction", "string", "es-en or en-es.", "es-en"),
        Field.new("contact_email", "string", "Optional: emailed when it is done.", "buyer@example.com")
      ],
      outputs: [
        Field.new("order_id", "string", "Token to poll at /orders/{order_id}.", "8kPz3nQ4vR7mB2xY6wLd"),
        Field.new("status", "string", "pending until translated, then delivered.", "pending"),
        Field.new("eta", "string", "Fulfilment promise.", "within 3 business days"),
        Field.new("result", "object", "The translation and any translator notes.")
      ]
    )
  ].freeze
end
