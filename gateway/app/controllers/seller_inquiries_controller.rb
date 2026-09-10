# frozen_string_literal: true

class SellerInquiriesController < ApplicationController
  def create
    attrs = { email: nil, service_name: nil, upstream_url: nil, price_usdc: nil, notes: nil }.merge(inquiry_params.to_h.symbolize_keys)
    result = Sellers::CreateInquiry.new(**attrs).call

    if result.success?
      redirect_to sell_path(submitted: 1)
    else
      @inquiry = result[:inquiry]
      @submitted = false
      render "pages/sell", status: :unprocessable_entity
    end
  end

  private

  def inquiry_params
    params.require(:seller_inquiry).permit(:email, :service_name, :upstream_url, :price_usdc, :notes)
  end
end
