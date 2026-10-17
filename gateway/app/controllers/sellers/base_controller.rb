# frozen_string_literal: true

module Sellers
  # Everything under /seller except signing in. A seller who is signed out,
  # or was suspended since, is sent to the sign-in page.
  class BaseController < ApplicationController
    before_action :require_seller

    helper_method :current_seller

    private

    def current_seller
      @current_seller ||= Seller.find_by(id: session[:seller_id])
    end

    def require_seller
      return if current_seller&.active?

      reset_session
      redirect_to seller_sign_in_path, alert: "Sign in to continue."
    end
  end
end
