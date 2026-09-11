class CatalogController < ApplicationController
  after_action :track_page_view

  def index
    @category = params[:category].presence
    @query = params[:q].to_s.strip.presence
    @services = Catalog::Service.all
    @services = @services.select { |s| s.category == @category } if @category
    @services = @services.select { |s| s.matches?(@query) } if @query
  end

  def show
    @service = Catalog::Service.find(params[:slug]) or raise ActionController::RoutingError, "Not found"
  end
end
