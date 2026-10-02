# frozen_string_literal: true

# The buyer half of /sell. A request is a request: it creates a row a person
# reads, never a listing and never a charge.
class ServiceRequestsController < ApplicationController
  include RendersSellPage
  include ThrottlesForms

  def create
    attrs = { email: nil, details: nil, service_slug: nil, budget_usdc: nil }.merge(request_params.to_h.symbolize_keys)
    result = Buyers::CreateRequest.new(**attrs).call

    if result.success?
      redirect_to sell_path(requested: 1, anchor: "request")
    else
      sell_page(request: result[:request])
      render "pages/sell", status: :unprocessable_entity
    end
  end

  private

  # ThrottlesForms: show the form again with what was typed and why it was refused.
  def refuse_submission(message)
    service_request = ServiceRequest.new(request_params)
    service_request.errors.add(:base, message)
    sell_page(request: service_request)
  end

  def request_params
    params.require(:service_request).permit(:email, :details, :service_slug, :budget_usdc)
  end
end
