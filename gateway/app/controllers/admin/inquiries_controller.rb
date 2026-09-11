# frozen_string_literal: true

module Admin
  # Seller inquiries and what we decided about them. Nothing a seller submits
  # is listed without a person approving it here first.
  class InquiriesController < BaseController
    def index
      @pending = SellerInquiry.pending
      @reviewed = SellerInquiry.reviewed.limit(50)
    end

    def approve = review(:approve!, "approved")

    def reject = review(:reject!, "rejected")

    private

    def review(action, label)
      inquiry = SellerInquiry.find(params[:id])
      inquiry.public_send(action, notes: params[:review_notes])
      Notifications::AnnounceReview.new(inquiry: inquiry).call
      redirect_to admin_inquiries_path, notice: "#{inquiry.service_name} #{label}. #{inquiry.email} was emailed."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_inquiries_path, alert: e.message
    end
  end
end
