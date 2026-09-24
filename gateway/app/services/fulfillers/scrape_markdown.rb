# frozen_string_literal: true

module Fulfillers
  # Built-in service: fetch a public page and return it as LLM-ready markdown.
  # Runs in-process (no upstream HTTP hop). Input: { url, selector? }.
  # Output: { markdown, title, word_count }. `render_js` is accepted and
  # ignored for now (documented as such in the catalog).
  class ScrapeMarkdown < Base
    STRIP = %w[script style noscript nav footer header aside form iframe svg template].freeze
    HTML_TYPES = %r{\A\s*(text/|application/(xhtml\+xml|xml))}i

    def call
      uri = public_uri { |failure| return failure }
      html, failure = load_html(uri)
      return failure if failure

      doc = Nokogiri::HTML(html)
      title = (doc.at("title")&.text || "").squish
      doc.css(STRIP.join(",")).remove

      scope = scope_for(doc) { |failure| return failure }
      json(markdown_for(scope, title))
    end

    private

    # Where the HTML comes from, and the only thing that differs between this
    # service and the rendered one. Everything after it -- stripping, the
    # selector, the markdown conversion -- works on an HTML string and does
    # not care how it arrived. `ScrapeMarkdownJs` overrides just this.
    def load_html(uri)
      response, failure = fetch(uri)
      return [ nil, failure ] if failure

      # Only refuse what is clearly not a page: JSON came back as JSON-shaped
      # markdown with an empty title, which is not what anyone paid for. A
      # server that sends no content-type at all still gets the benefit of the
      # doubt, because plenty of real pages do not send one.
      type = response.headers["content-type"].to_s
      return [ nil, bad_request("url returned #{type.split(';').first}, not an HTML page") ] if type.present? && !type.match?(HTML_TYPES)

      [ response.body, nil ]
    end

    # Resolves `selector` against the page, or falls back to the usual content
    # containers when none was given.
    #
    # A selector that matched nothing used to fall through to that same
    # fallback, so the buyer paid full price for the whole page instead of the
    # part they asked for, with nothing in the response to say so. It is a
    # 422 now: the request reached us and was answered, and a 4xx is never
    # settled, so a wrong selector costs nothing.
    def scope_for(doc)
      selector = input["selector"].to_s.strip
      return doc.at("main") || doc.at("article") || doc.at("body") || doc if selector.blank?

      scope = begin
        doc.at_css(selector)
      rescue StandardError
        return yield bad_request("selector #{selector.inspect} is not a valid CSS selector")
      end

      scope || yield(bad_request("selector #{selector.inspect} matched nothing on this page"))
    end

    def markdown_for(scope, title)
      markdown = ReverseMarkdown.convert(scope.to_html, unknown_tags: :bypass, github_flavored: true).strip.gsub(/\n{3,}/, "\n\n")
      { markdown: markdown, title: title, word_count: markdown.split(/\s+/).count { |w| w.present? } }
    end
  end
end
