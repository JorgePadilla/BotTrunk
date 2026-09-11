# frozen_string_literal: true

namespace :rates do
  desc "Show the USD/HNL rate pricing uses right now, and where it came from"
  task show: :environment do
    info = Rates::UsdHnl.info
    puts "USD/HNL #{info.rate.to_s("F")}  source=#{info.source}  as_of=#{info.as_of}  fetched_at=#{info.fetched_at&.utc}"
  end

  desc "Force a refresh from BCH (or the feed) and store it"
  task refresh: :environment do
    Rails.cache.delete(Rates::UsdHnl::CACHE_KEY)
    info = Rates::UsdHnl.new.refresh
    puts info ? "stored USD/HNL #{info.rate.to_s("F")} from #{info.source} (as of #{info.as_of})" : "no source answered; pricing keeps the last stored rate"
  end

  desc "List BCH indicators that look like the reference exchange rate (needs BCH_API_KEY)"
  task bch_indicators: :environment do
    abort "Set BCH_API_KEY first (free account at https://bchapi-am.developer.azure-api.net)" if ENV["BCH_API_KEY"].blank?
    conn = Faraday.new(headers: { "Ocp-Apim-Subscription-Key" => ENV["BCH_API_KEY"] })
    %w[TCR cambio].each do |term|
      res = conn.get("#{Rates::FetchBch::BASE}/indicadores", { nombre: term, formato: "json" })
      abort "BCH answered #{res.status}: #{res.body.truncate(200)}" unless res.success?
      JSON.parse(res.body).each { |i| puts format("%-6s %-40s %s", i["id"], i["nombre"], i["descripcion"].to_s.truncate(80)) }
    end
    puts "\nSet BCH_TCR_INDICATOR_ID to the id of the daily reference rate (default #{Rates::FetchBch::DEFAULT_INDICATOR})."
  end
end
