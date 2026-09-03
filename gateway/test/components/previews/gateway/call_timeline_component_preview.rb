# frozen_string_literal: true

module Gateway
  class CallTimelineComponentPreview < ViewComponent::Preview
    def settled
      render Gateway::CallTimelineComponent.new(stamp: "2 min ago", steps: [
        { title: "402 Payment Required", meta: "5000 µUSDC requested" },
        { title: "Payment verified", meta: "X-PAYMENT · GoPlausible" },
        { title: "Upstream responded", meta: "812 ms · 200 OK" },
        { title: "Settled on-chain", meta: "txn 4KQ2…M9 · seller 90%" }
      ])
    end

    def in_progress
      render Gateway::CallTimelineComponent.new(steps: [
        { title: "402 Payment Required", meta: "5000 µUSDC requested" },
        { title: "Payment verified", meta: "X-PAYMENT · GoPlausible" },
        { title: "Upstream call", meta: "waiting…", state: :pending },
        { title: "Settlement", state: :pending }
      ])
    end

    def failed
      render Gateway::CallTimelineComponent.new(steps: [
        { title: "402 Payment Required", meta: "5000 µUSDC requested" },
        { title: "Payment rejected", meta: "insufficient balance", state: :failed }
      ])
    end
  end
end
