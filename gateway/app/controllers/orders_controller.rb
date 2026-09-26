# frozen_string_literal: true

# GET /orders/:token — public, free status of a human-fulfilled order of any
# kind: a deposit, or a job somebody is doing at a desk. The token is the only
# handle, and the response never carries bank details.
class OrdersController < ActionController::API
  def show
    order = OrderLookup.find(params[:token]) or return render(json: { error: "not found" }, status: :not_found)
    render json: order.public_status
  end
end
