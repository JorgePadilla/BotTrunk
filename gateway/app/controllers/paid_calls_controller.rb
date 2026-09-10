# frozen_string_literal: true

# POST /s/:slug — the paid endpoint of every service. Everything happens in
# Gateway::HandlePaidCall; this controller only moves bytes in and out.
class PaidCallsController < ApplicationController
  skip_forgery_protection

  def create
    service = Catalog::Service.find(params[:slug]) or return head(:not_found)

    result = Gateway::HandlePaidCall.new(
      service: service,
      payment_header: request.headers[Payments::Payload::HEADER],
      body: request.raw_post,
      headers: { "Content-Type" => request.content_type, "Accept" => request.headers["Accept"] }.compact
    ).call

    data = result.data
    data[:headers]&.each { |k, v| response.set_header(k, v) }
    render body: data[:body] || { error: result.error }.to_json,
           status: data[:status] || 500,
           content_type: data[:content_type] || "application/json"
  end
end
