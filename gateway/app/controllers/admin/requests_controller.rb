# frozen_string_literal: true

module Admin
  # What buyers asked for. The rows with no `service_slug` are the ones worth
  # reading twice: they are the catalog's missing entries, named by someone
  # who would have paid for them.
  class RequestsController < BaseController
    def index
      @pending = ServiceRequest.pending
      @reviewed = ServiceRequest.reviewed.limit(50)
      @gaps = @pending.select(&:for_catalog_gap?)
    end

    def answer = review(:answer!, "marked answered")

    def close = review(:close!, "closed")

    private

    def review(action, label)
      request = ServiceRequest.find(params[:id])
      request.public_send(action, notes: params[:review_notes])
      redirect_to admin_requests_path, notice: "Request from #{request.email} #{label}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_requests_path, alert: e.message
    end
  end
end
