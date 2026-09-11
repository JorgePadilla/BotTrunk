# frozen_string_literal: true

module Catalog
  # Measured performance per service, straight from the `calls` ledger:
  # how many paid calls, median upstream latency, success rate, volume.
  # Nothing here is hand-written — a service with no calls reports nothing,
  # and the UI says "no calls yet" rather than inventing a number.
  class Metrics
    CACHE_KEY = "catalog/metrics"
    TTL = 60.seconds

    # A percentage over a handful of calls is not a success rate — "100%" from
    # five calls reads as a guarantee and is worth nothing. Below this we
    # publish the raw count instead and let the reader judge.
    MIN_FOR_RATE = 20

    Row = Data.define(:slug, :calls, :p50_ms, :success_rate, :volume, :last_at) do
      def any? = calls.to_i.positive?

      def latency
        return nil unless p50_ms

        p50_ms >= 1_000 ? "#{(p50_ms / 1_000.0).round(1)} s" : "#{p50_ms.round} ms"
      end

      def success
        return nil unless any? && success_rate

        percent = success_rate * 100
        percent == percent.round ? "#{percent.round}%" : "#{percent.round(1)}%"
      end

      def reliability
        return nil unless any? && success_rate
        return "#{success} success" if calls >= MIN_FOR_RATE

        failures = (calls * (1 - success_rate)).round
        failures.zero? ? "none failed yet" : "#{failures} of #{calls} failed"
      end

    end

    Totals = Data.define(:calls, :volume, :services, :last_at) do
      def any? = calls.to_i.positive?
    end

    def self.empty(slug = nil) = Row.new(slug: slug, calls: 0, p50_ms: nil, success_rate: nil, volume: 0, last_at: nil)

    # { slug => Row }, cached briefly so a busy catalog page is one query.
    def self.all
      Rails.cache.fetch(CACHE_KEY, expires_in: TTL) { load }
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("catalog metrics unavailable: #{e.message}")
      {}
    end

    def self.for(slug) = all[slug] || empty(slug)

    # One row for a family of services (the deposit tiers), so a card can show
    # the product's real numbers rather than one variant's. The p50 is the mean
    # of the variants' medians — close enough for a card, and honest about it.
    def self.combined(slugs)
      rows = slugs.filter_map { |slug| all[slug] }.select(&:any?)
      return empty if rows.empty?

      calls = rows.sum(&:calls)
      p50s = rows.filter_map(&:p50_ms)
      Row.new(slug: nil, calls: calls, p50_ms: (p50s.sum / p50s.size if p50s.any?),
              success_rate: rows.sum { |r| (r.success_rate || 0) * r.calls } / calls,
              volume: rows.sum(&:volume), last_at: rows.filter_map(&:last_at).max)
    end

    def self.totals
      rows = all.values
      Totals.new(calls: rows.sum(&:calls), volume: rows.sum(&:volume), services: rows.count(&:any?), last_at: rows.filter_map(&:last_at).max)
    end

    def self.load
      Call.group(:service_slug).pluck(
        Arel.sql("service_slug"),
        Arel.sql("count(*)"),
        Arel.sql("coalesce(sum(amount), 0)"),
        Arel.sql("max(created_at)"),
        Arel.sql("percentile_cont(0.5) within group (order by upstream_latency_ms::float8)"),
        Arel.sql("count(*) filter (where upstream_status is null or upstream_status < 400)")
      ).to_h do |slug, count, volume, last_at, p50, ok|
        [ slug, Row.new(slug: slug, calls: count, p50_ms: p50&.to_f, success_rate: count.positive? ? ok.to_f / count : nil, volume: volume.to_i, last_at: last_at) ]
      end
    end
    private_class_method :load
  end
end
