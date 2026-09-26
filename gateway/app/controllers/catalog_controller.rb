class CatalogController < ApplicationController
  PER_PAGE = 24        # cards, once a filter or a search narrows the catalog
  PER_PAGE_ALL = 50    # rows on the reference page

  after_action :track_page_view

  # Two modes, because a catalog stops being one list once it is long:
  # unfiltered it is a shopfront — sections, a few cards each — and filtered
  # it is a plain grid with pages, which is what someone narrowing wants.
  def index
    @category = params[:category].presence
    @query = params[:q].to_s.strip.presence
    @services = filtered(Catalog::Service.all)
    @totals = Catalog::Metrics.totals

    ranking = Catalog::Ranking.new(@services)
    @browsing = @category.nil? && @query.nil?
    if @browsing
      @sections = ranking.sections
    else
      @page, @pages, @cards = paginate(ranking.cards, PER_PAGE)
    end
  end

  # Every service, one row each, family variants listed separately. The page
  # you come to knowing what you are looking for — and the one a seller or a
  # judge can read end to end.
  def all
    @query = params[:q].to_s.strip.presence
    @category = params[:category].presence
    ranking = Catalog::Ranking.new(filtered(Catalog::Service.all))
    @sort = params[:sort] == "price" ? "price" : nil
    services = @sort ? ranking.by_price : ranking.services
    @page, @pages, @services = paginate(services, PER_PAGE_ALL)
    @metrics = Catalog::Metrics.all
    @total = Catalog::Service.all.size
  end

  def show
    @service = Catalog::Service.find(params[:slug]) or raise ActionController::RoutingError, "Not found"
    @metrics = Catalog::Metrics.for(@service.slug)
    @variants = @service.variants
  end

  private

  def filtered(services)
    services = services.select { |s| s.category == @category } if @category
    services = services.select { |s| s.matches?(@query) } if @query
    services
  end

  # The catalog is an in-memory array, so this is `each_slice` and two links.
  # A page past the end shows the last page rather than an empty screen.
  def paginate(collection, per_page)
    pages = [ (collection.size.to_f / per_page).ceil, 1 ].max
    page = params[:page].to_i.clamp(1, pages)
    [ page, pages, collection[(page - 1) * per_page, per_page] || [] ]
  end
end
