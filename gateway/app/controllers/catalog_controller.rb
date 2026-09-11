class CatalogController < ApplicationController
  after_action :track_page_view

  def index
    @category = params[:category].presence
    @query = params[:q].to_s.strip.presence
    @services = Catalog::Service.all
    @services = @services.select { |s| s.category == @category } if @category
    @services = @services.select { |s| s.matches?(@query) } if @query
    # [primary, variants, metrics] per catalog card; a family collapses into one.
    @groups = Catalog::Service.grouped(@services).map do |variants|
      primary = variants.min_by(&:price_atomic)
      [ primary, variants, Catalog::Metrics.combined(variants.map(&:slug)) ]
    end
    @totals = Catalog::Metrics.totals
  end

  def show
    @service = Catalog::Service.find(params[:slug]) or raise ActionController::RoutingError, "Not found"
    @metrics = Catalog::Metrics.for(@service.slug)
    @variants = @service.variants
  end
end
