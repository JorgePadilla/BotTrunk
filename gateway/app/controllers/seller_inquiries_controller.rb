# frozen_string_literal: true

class SellerInquiriesController < ApplicationController
  include RendersSellPage
  include ThrottlesForms

  def create
    attrs = { email: nil, service_name: nil, upstream_url: nil, price_usdc: nil, notes: nil }.merge(inquiry_params.to_h.symbolize_keys)
    result = Sellers::CreateInquiry.new(**attrs).call

    if result.success?
      redirect_to sell_path(submitted: 1)
    else
      sell_page(inquiry: result[:inquiry])
      render "pages/sell", status: :unprocessable_entity
    end
  end

  private

  # ThrottlesForms: show the form again with what was typed and why it was refused.
  def refuse_submission(message)
    inquiry = SellerInquiry.new(inquiry_params)
    inquiry.errors.add(:base, message)
    sell_page(inquiry: inquiry)
  end

  def inquiry_params
    params.require(:seller_inquiry).permit(:email, :service_name, :upstream_url, :price_usdc, :notes)
  end
end
