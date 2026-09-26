# frozen_string_literal: true

# A job an agent paid for that a person does at a desk: calls made, quotes
# chased, a question asked of someone who will only answer out loud. The
# lifecycle is shared with deposits (OrderLifecycle); what differs is that the
# deliverable is information, so `result` is where the work lands and there is
# no money to move.
class WorkOrder < ApplicationRecord
  include OrderLifecycle

  STATUSES = OrderLifecycle::STATUSES
  OPEN = OrderLifecycle::OPEN
  DONE = OrderLifecycle::DONE

  # A brief is a specification, and the app tiers sell specification length:
  # 1,000 characters at the small end, 15,000 at the top. The column has to
  # hold the largest thing any service is allowed to ask for.
  MAX_BRIEF = 16_000

  validates :brief, presence: true, length: { maximum: MAX_BRIEF }

  def deliver!(result:, notes: nil)
    update!(status: "delivered", result: result, delivered_at: Time.current, notes: notes.presence || self.notes)
  end

  # The public view an agent polls at GET /orders/:token. `result` is only
  # present once delivered, so a poll before then is cheap and says so.
  def public_status
    {
      order_id: token, status: status, service: service_slug, paid_usdc: paid_usdc,
      brief: brief, eta: (pending? ? eta : nil), delivered_at: delivered_at,
      result: (result.presence if status == "delivered"),
      refund_transaction_id: refund_transaction_id, created_at: created_at
    }.compact
  end

  # The promise comes from the catalog entry, so the page, the 202 body and a
  # polling agent cannot disagree about how long this takes. A slug that has
  # since left the catalog falls back rather than breaking an open order.
  def eta = Catalog::Service.find(service_slug)&.job_eta || "within 5 business days"
end
