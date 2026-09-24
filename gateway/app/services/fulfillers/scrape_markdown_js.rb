# frozen_string_literal: true

module Fulfillers
  # scrape-markdown, but the page is rendered in a real browser first.
  #
  # The plain service fetches HTML over HTTP, which returns almost nothing on
  # a site that builds its content client-side -- most React apps, most
  # dashboards, a lot of pricing pages. This one renders, then hands the
  # resulting HTML to exactly the same pipeline: same strip list, same
  # selector handling, same markdown conversion, same 422 semantics.
  #
  # It is a separate slug rather than a flag on the cheap one because the 402
  # quotes a price per service. A render costs us real money and a plain fetch
  # does not, so they cannot honestly share a price.
  class ScrapeMarkdownJs < ScrapeMarkdown
    private

    def load_html(uri)
      html, problem = Rendering::Cloudflare.new(action: "content", url: uri.to_s, options: render_options).call
      return [ nil, upstream_error(problem) ] if problem
      return [ nil, upstream_error("renderer returned an empty page") ] if html.blank?

      [ html, nil ]
    end

    # `wait_for` lets a buyer name a selector to wait on before the snapshot is
    # taken -- the difference between catching a dashboard mid-spinner and
    # after its data has loaded. Left out of the payload when not given, so the
    # renderer applies its own default.
    def render_options
      wait_for = input["wait_for"].to_s.strip
      wait_for.present? ? { waitForSelector: wait_for } : {}
    end
  end
end
