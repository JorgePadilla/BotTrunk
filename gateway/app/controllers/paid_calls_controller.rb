# frozen_string_literal: true

# POST /s/:slug — the paid endpoint of every service. Everything happens in
# Gateway::HandlePaidCall; this controller only moves bytes in and out.
#
# Headers (x402 v2 names first, v1 aliases kept for older clients):
#   request : PAYMENT-SIGNATURE | X-PAYMENT   — base64 payment payload
#   402     : PAYMENT-REQUIRED               — base64 of the challenge body
#   200     : PAYMENT-RESPONSE | X-PAYMENT-RESPONSE — base64 settlement receipt
class PaidCallsController < ApplicationController
  skip_forgery_protection
  before_action :cors_headers

  def create
    service = Catalog::Service.find(params[:slug]) or return head(:not_found)

    result = Gateway::HandlePaidCall.new(
      service: service,
      payment_header: request.headers["PAYMENT-SIGNATURE"].presence || request.headers[Payments::Payload::HEADER],
      body: request.raw_post,
      headers: { "Content-Type" => request.content_type, "Accept" => request.headers["Accept"] }.compact
    ).call

    data = result.data
    data[:headers]&.each { |k, v| response.set_header(k, v) }
    if result.code == :payment_required && data[:body]
      response.set_header("PAYMENT-REQUIRED", Base64.strict_encode64(data[:body]))
    end
    if (receipt = data.dig(:headers, Payments::Receipt::HEADER))
      response.set_header("PAYMENT-RESPONSE", receipt)
    end
    render body: data[:body] || { error: result.error }.to_json,
           status: data[:status] || 500,
           content_type: data[:content_type] || "application/json"
  end

  # CORS preflight so browser-based payers (wallet dApps) can call us.
  def preflight
    head :no_content
  end

  private

  def cors_headers
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Content-Type, Accept, PAYMENT-SIGNATURE, X-PAYMENT")
    response.set_header("Access-Control-Expose-Headers", "PAYMENT-REQUIRED, PAYMENT-RESPONSE, X-PAYMENT-RESPONSE")
    response.set_header("Access-Control-Max-Age", "86400")
  end
end
