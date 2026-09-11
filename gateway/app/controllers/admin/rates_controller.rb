# frozen_string_literal: true

module Admin
  # POST /admin/rates/refresh — fetch the USD/HNL rate now instead of waiting for the hourly refresh.
  class RatesController < BaseController
    def refresh
      Rails.cache.delete(Rates::UsdHnl::CACHE_KEY)
      info = Rates::UsdHnl.new.refresh
      if info
        redirect_to admin_stats_path(anchor: "rates"), notice: "USD/HNL refreshed: L#{info.rate.to_s("F")} from #{info.source} (as of #{info.as_of})."
      else
        redirect_to admin_stats_path(anchor: "rates"), alert: "No rate source answered; pricing keeps the last stored rate."
      end
    end
  end
end
