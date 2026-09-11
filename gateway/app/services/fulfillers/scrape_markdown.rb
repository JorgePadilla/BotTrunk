# frozen_string_literal: true

module Fulfillers
  # Built-in service: fetch a public page and return it as LLM-ready markdown.
  # Runs in-process (no upstream HTTP hop). Input: { url, selector? }.
  # Output: { markdown, title, word_count }. `render_js` is accepted and
  # ignored for now (documented as such).
  class ScrapeMarkdown < Base
    STRIP = %w[script style noscript nav footer header aside form iframe svg template].freeze

    def call
      uri = public_uri { |failure| return failure }
      response, failure = fetch(uri)
      return failure if failure

      json(extract(response.body))
    end

    private

    def extract(html)
      doc = Nokogiri::HTML(html)
      title = (doc.at("title")&.text || "").squish
      doc.css(STRIP.join(",")).remove
      scope = input["selector"].present? ? doc.at_css(input["selector"].to_s) : nil
      scope ||= doc.at("main") || doc.at("article") || doc.at("body") || doc
      markdown = ReverseMarkdown.convert(scope.to_html, unknown_tags: :bypass, github_flavored: true).strip
      markdown = markdown.gsub(/\n{3,}/, "\n\n")
      { markdown: markdown, title: title, word_count: markdown.split(/\s+/).count { |w| w.present? } }
    end
  end
end
