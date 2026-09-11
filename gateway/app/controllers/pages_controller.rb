# frozen_string_literal: true

# Static-ish marketing and documentation pages. No state, no services.
class PagesController < ApplicationController
  after_action :track_page_view

  def docs
    @example_service = Catalog::Service.find("scrape-markdown")
    @requirements = Payments::BuildRequirements.new(service: @example_service, config: docs_config).call[:requirements]
    @example_402 = Payments::BuildRequirements.body_for(service: @example_service, requirements: @requirements)
  end

  def sell
    @inquiry = SellerInquiry.new
    @submitted = params[:submitted].present?
  end

  def connect
  end

  def sign_in
  end

  # /llms.txt — the agent-readable summary of this site. Rendered from the
  # catalog so it can never drift from what the endpoints actually charge
  # (the Bazaar enriches its listing from this file).
  def llms
    @services = Catalog::Service.all.partition(&:live?).flatten
    render plain: render_to_string(template: "pages/llms", formats: [ :text ], layout: false), content_type: "text/plain"
  end

  private

  # The docs render a real 402 body; when no payTo is configured yet (CI,
  # fresh clone) show a placeholder rather than failing the page.
  def docs_config
    config = Rails.configuration.x402.dup
    config.pay_to = config.pay_to.presence || "PAYTO…58-CHAR-ALGORAND-ADDRESS"
    config
  end
end
