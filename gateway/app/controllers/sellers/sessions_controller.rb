# frozen_string_literal: true

module Sellers
  # Email-link sign-in. The link in the email opens a page with a button
  # rather than signing in on the GET, because mail scanners open links to
  # check them, and a one-time link they open is spent before the seller sees it.
  class SessionsController < ApplicationController
    rate_limit to: 5, within: 15.minutes, store: RATE_LIMIT_STORE, scope: "seller-sign-in", only: :create,
               with: -> { redirect_to seller_sign_in_path, alert: "Too many sign-in emails from your network. Try again in 15 minutes." }

    def new
      @email = params[:email]
    end

    def create
      result = Sellers::SendSignInLink.new(email: params[:email]).call
      if result.success? || result.code == :suspended
        # Suspended accounts get the same page: the email they would have
        # received says nothing either, and the form must not tell them apart.
        redirect_to seller_sign_in_path(sent: 1)
      else
        @email = params[:email]
        flash.now[:alert] = result.error
        render :new, status: :unprocessable_entity
      end
    end

    def confirm
      @token = params[:token]
    end

    def consume
      result = Sellers::SignIn.new(token: params[:token]).call
      return redirect_to(seller_sign_in_path, alert: result.error) if result.failure?

      reset_session
      session[:seller_id] = result[:seller].id
      redirect_to seller_root_path
    end

    def destroy
      reset_session
      redirect_to root_path, notice: "Signed out."
    end
  end
end
