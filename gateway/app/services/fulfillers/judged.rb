# frozen_string_literal: true

module Fulfillers
  # Shared plumbing for the services that answer with a judgment from the
  # judge model (Judgment::Judge): reading text inputs, fetching a page through the same
  # pipeline as `scrape-markdown`, and turning a judge failure into a 502 so
  # the call is never settled. The questions themselves live in
  # Judgment::Rubrics.
  #
  # Whatever a buyer sends is untrusted. It goes into its own named field in
  # the state and the questions point at it by path; nothing in it is ever
  # read as an instruction to us.
  class Judged < Base
    TEXT_CHARS = 50_000   # inputs: well inside the judge's 32k-token window
    PAGE_CHARS = 30_000   # fetched pages are cut here; `truncated` says so

    private

    # The payload ({ "model", "answers", "usage" }), or yields a 502.
    def judge(state, questions)
      payload, failure = Judgment::Judge.new(state: state, questions: questions).call
      return yield upstream_error(failure) if failure

      payload
    end

    def probabilities(payload, ids) = ids.index_with { |id| payload.dig("answers", id, "p") }

    # A required text input. Objects and arrays (a tool call as JSON) are
    # judged as their JSON, which is how an agent would have written them.
    def text_input(key, max: TEXT_CHARS, required: true)
      raw = input[key]
      value = (raw.is_a?(Hash) || raw.is_a?(Array) ? raw.to_json : raw.to_s).strip
      return yield bad_request("#{key} is required") if value.empty? && required
      return yield bad_request("#{key} is longer than #{max} characters") if value.length > max

      value.presence
    end

    # The page as `scrape-markdown` sees it: { url, title, text, truncated }.
    # Its refusals (bad URL, not HTML, fetch failed) pass through unchanged.
    def fetch_page
      result = ScrapeMarkdown.new(input: { "url" => input["url"] }, connection: @connection).call
      return yield result unless result.success? && result[:status] == 200

      data = JSON.parse(result[:body])
      text = data["markdown"].to_s
      { url: input["url"].to_s.strip, title: data["title"].to_s, text: text.first(PAGE_CHARS), truncated: text.length > PAGE_CHARS }
    end

    def at_least?(value, threshold) = value.to_f >= Judgment::Rubrics::POLICY.fetch(threshold)
  end
end
