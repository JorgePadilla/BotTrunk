class CatalogController < ApplicationController
  def index
    @category = params[:category].presence
    @services = Catalog::Service.all
    @services = @services.select { |s| s.category == @category } if @category
  end

  def show
    @service = Catalog::Service.find(params[:slug]) or raise ActionController::RoutingError, "Not found"
  end
end
