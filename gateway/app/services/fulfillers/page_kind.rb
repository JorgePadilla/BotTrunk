# frozen_string_literal: true

module Fulfillers
  # Built-in service: what kind of page is this, and is its content actually
  # there? Tells a crawling agent it hit a login wall, a paywall, a soft 404 or
  # a parked domain before it spends anything reading the page.
  # Input: { url }. Output: { kind, confidence, probabilities,
  # content_present, title, url, truncated, version }.
  #
  # A page that answers 4xx/5xx is not judged: the fetch error comes back and
  # nothing is charged (`url-health` is the service for status codes).
  class PageKind < Judged
    def call
      page = fetch_page { |failure| return failure }
      payload = judge({ page: page.slice(:url, :title, :text) }, Judgment::Rubrics::PAGE_KIND) { |failure| return failure }
      kind = payload.dig("answers", "kind") || {}

      json({
        kind: kind["choice"],
        confidence: kind["confidence"],
        probabilities: kind["probabilities"],
        content_present: payload.dig("answers", "content_present", "p"),
        title: page[:title],
        url: page[:url],
        truncated: page[:truncated],
        version: Judgment::Rubrics::VERSION
      })
    end
  end
end
