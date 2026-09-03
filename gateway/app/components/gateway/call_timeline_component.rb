# frozen_string_literal: true

module Gateway
  # The x402 story of one call: 402 → payment verified → upstream → settled.
  # `steps:` is an array of { title:, meta:, state: :done | :pending | :failed }.
  class CallTimelineComponent < ApplicationComponent
    Step = Data.define(:title, :meta, :state) do
      def initialize(title:, meta: nil, state: :done) = super
    end

    def initialize(steps:, heading: "Last call", stamp: nil)
      @steps = steps.map { |s| s.is_a?(Step) ? s : Step.new(**s) }
      @heading = heading
      @stamp = stamp
    end

    attr_reader :steps, :heading, :stamp

    def marker_classes(step)
      case step.state
      when :done    then "bg-base-200 text-success"
      when :failed  then "bg-base-200 text-error"
      else               "bg-base-200 text-muted"
      end
    end

    def marker_icon(step)
      { done: "check", failed: "x", pending: "clock" }.fetch(step.state)
    end
  end
end
