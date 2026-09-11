# frozen_string_literal: true

module Api
  module V1
    # Public, read-only catalog for machines (the MCP hub reads this — ADR 0007).
    class CatalogController < ActionController::API
      include TracksEvents
      after_action -> { track_event("catalog_api", service_slug: params[:slug].presence) }

      def index
        services = Catalog::Service.all
        services = services.select { |s| s.category == params[:category] } if params[:category].present?
        render json: { services: services.map { |s| serialize(s) } }
      end

      def show
        service = Catalog::Service.find(params[:slug]) or return render(json: { error: "not found" }, status: :not_found)
        render json: serialize(service)
      end

      private

      def serialize(s)
        {
          slug: s.slug, name: s.name, summary: s.summary, description: s.description, category: s.category,
          provider: s.provider, endpoint: s.endpoint_url, method: "POST", status: s.status,
          price: { amount: s.price_atomic.to_s, asset: "USDC", decimals: 6 },
          inputs: s.inputs.map(&:to_h), outputs: s.outputs.map(&:to_h),
          behaviour: s.documented_behaviour.map { |label, body| { topic: label, detail: body.delete("`") } }
        }
      end
    end
  end
end
