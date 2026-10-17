# frozen_string_literal: true

module Fulfillers
  # Built-in service: should an agent go ahead with this action? A second
  # opinion before a command, a tool call or a payment, judged against the
  # task the agent was given.
  # Input: { action, task, context? }. Output: { verdict, reasons, flags,
  # severity, denied_by_rule, version }.
  #
  # The deny rules in Judgment::Rubrics::DENY run first and block on their
  # own; the judge is not asked, and nothing it says could unblock them. Past them
  # the verdict is advisory, never the only check before something that
  # cannot be undone.
  class ToolCallGate < Judged
    def call
      action = text_input("action") { |failure| return failure }
      task = text_input("task") { |failure| return failure }
      context = text_input("context", required: false) { |failure| return failure }

      rule = Judgment::Rubrics::DENY.find { |_, pattern| pattern.match?(action) }&.first
      return json({ verdict: "block", reasons: [ rule ], flags: {}, severity: nil, denied_by_rule: rule, version: Judgment::Rubrics::VERSION }) if rule

      state = { task: task, proposed_action: action, context: context }.compact
      payload = judge(state, Judgment::Rubrics::GATE) { |failure| return failure }
      flags = probabilities(payload, Judgment::Rubrics::GATE_FLAGS.keys)
      severity = payload.dig("answers", "severity", "score")

      json({
        verdict: verdict(flags, severity),
        reasons: flags.select { |_, p| at_least?(p, :review) }.keys,
        flags: flags,
        severity: severity,
        denied_by_rule: nil,
        version: Judgment::Rubrics::VERSION
      })
    end

    private

    # Going beyond the task or leaking data blocks outright. Anything else
    # that looks risky asks for review, unless the damage would be
    # irreversible, in which case it blocks too.
    def verdict(flags, severity)
      return "block" if at_least?(flags["beyond_task"], :block) || at_least?(flags["exfiltrates"], :block)

      risky = flags.values.compact.max.to_f
      return "block" if at_least?(risky, :block) && at_least?(severity, :severity_block)
      return "review" if at_least?(risky, :review)

      "allow"
    end
  end
end
