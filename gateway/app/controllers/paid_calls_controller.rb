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
    return coming_soon(service) unless service.live?

    payment_header = Payments::Payload.header_in(request.headers)
    result = handle(service, payment_header)
    track_paywall(service, result, payment_header)

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

  # A request with a payment is always a paid call. Without one, the trial
  # header asks for the one free call (ADR 0010).
  def handle(service, payment_header)
    trial = Gateway::GrantTrial.new(service: service, ip: request.remote_ip)
    body = request.raw_post
    headers = { "Content-Type" => request.content_type, "Accept" => request.headers["Accept"] }.compact
    if payment_header.blank? && Gateway::GrantTrial.requested?(request.headers)
      result = Gateway::HandleTrialCall.new(service: service, trial: trial, body: body, headers: headers).call
      track_event(Gateway::GrantTrial::EVENT, service_slug: service.slug, trial_key: result[:trial_key]) if result.success?
      result
    else
      Gateway::HandlePaidCall.new(service: service, payment_header: payment_header, body: body, headers: headers, trial: trial).call
    end
  end

  # A 402 without a payment header is a probe (someone looked); a 402 with one
  # is a rejected payment (someone tried), kept with the network it was signed
  # for, so /admin/stats can say which networks people try to pay on.
  # Settled calls are in `calls`.
  def track_paywall(service, result, payment_header)
    return unless result.code == :payment_required
    return track_event("payment_required", service_slug: service.slug, reason: result.error) if payment_header.blank?

    track_event("payment_rejected", service_slug: service.slug, reason: result.error,
                network: Payments::Payload.from_header(payment_header)&.network)
  end

  # Listed but not yet callable. These are jobs a person does, so we agree the
  # scope before any money moves. "Not live yet" read like something broken;
  # an agent hitting this needs the way in, not a dead end. The payment header
  # is never looked at, so nothing can be charged here.
  def coming_soon(service)
    track_event("coming_soon", service_slug: service.slug)
    contact = ENV.fetch("MAIL_REPLY_TO", "hello@bottrunk.com")
    body = {
      error: "#{service.name} is fulfilled by a person, and is arranged before the first call.",
      status: service.status,
      reason: "human_fulfilled_arrange_first",
      charged: false,
      how_to_arrange: "Email #{contact} with the scope. Once it is agreed this endpoint answers 402 " \
                      "and behaves like every other paid call.",
      contact: contact,
      catalog: "https://bottrunk.com/s/#{service.slug}"
    }
    body[:price_usdc] = format("%.2f", service.price_usdc) if service.price_usdc
    render json: body, status: :service_unavailable
  end

  def cors_headers
    response.set_header("Access-Control-Allow-Origin", "*")
    response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Content-Type, Accept, PAYMENT-SIGNATURE, X-PAYMENT, #{Gateway::GrantTrial::HEADER}")
    response.set_header("Access-Control-Expose-Headers", "PAYMENT-REQUIRED, PAYMENT-RESPONSE, X-PAYMENT-RESPONSE, BotTrunk-Trial, BotTrunk-Fund")
    response.set_header("Access-Control-Max-Age", "86400")
  end
end
