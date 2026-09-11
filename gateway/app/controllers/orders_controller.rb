# frozen_string_literal: true

# GET /orders/:token — public, free status of a human-fulfilled order. The
# token is the only handle (no bank details in the response).
class OrdersController < ActionController::API
  def show
    order = DepositOrder.find_by(token: params[:token]) or return render(json: { error: "not found" }, status: :not_found)
    render json: order.public_status
  end
end
