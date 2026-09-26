# frozen_string_literal: true

module Admin
  # Where the weekly round gets typed in. Rows are never edited: a new week is
  # a new row, because the history is what makes the latest number believable.
  class PricesController < BaseController
    def index
      @latest = LocalPrice.latest.order(:item).to_a
      @recent = LocalPrice.recent.limit(40)
      @price = LocalPrice.new(observed_at: Date.current)
    end

    def create
      @price = LocalPrice.new(price_params)
      return redirect_to(admin_prices_path, notice: "Recorded #{@price.item} at L#{@price.price_hnl}.") if @price.save

      @latest = LocalPrice.latest.order(:item).to_a
      @recent = LocalPrice.recent.limit(40)
      flash.now[:alert] = @price.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end

    private

    def price_params
      params.expect(local_price: [ :item, :unit, :city, :price_hnl, :source, :observed_at, :notes ])
    end
  end
end
