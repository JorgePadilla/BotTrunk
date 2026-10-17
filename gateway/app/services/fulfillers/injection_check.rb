# frozen_string_literal: true

module Fulfillers
  # Built-in service: is this text trying to hijack the agent that reads it?
  # Meant for whatever an agent is about to put in its context and did not
  # write itself: a scraped page, an email, a tool result.
  # Input: { text, source? }. Output: { verdict, flags, addresses_ai,
  # severity, version }.
  #
  # The verdict comes from the four harmful flags. Merely talking to an AI
  # ("AI assistants: our docs are at /llms.txt") is reported in `addresses_ai`
  # and at most makes the text `suspicious`.
  class InjectionCheck < Judged
    def call
      text = text_input("text") { |failure| return failure }
      source = input["source"].presence || "other"
      return bad_request("source must be one of #{Judgment::Rubrics::INJECTION_SOURCES.join(", ")}") unless Judgment::Rubrics::INJECTION_SOURCES.include?(source)

      payload = judge({ untrusted: { source: source, text: text } }, Judgment::Rubrics::INJECTION) { |failure| return failure }
      flags = probabilities(payload, Judgment::Rubrics::INJECTION_FLAGS.keys)
      addresses_ai = payload.dig("answers", "addresses_ai", "p")

      json({
        verdict: verdict(flags, addresses_ai),
        flags: flags,
        addresses_ai: addresses_ai,
        severity: payload.dig("answers", "severity", "score"),
        version: Judgment::Rubrics::VERSION
      })
    end

    private

    def verdict(flags, addresses_ai)
      worst = flags.values.compact.max.to_f
      return "injection" if at_least?(worst, :block)
      return "suspicious" if at_least?(worst, :review) || at_least?(addresses_ai, :block)

      "clean"
    end
  end
end
