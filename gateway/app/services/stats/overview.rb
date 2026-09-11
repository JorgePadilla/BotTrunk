# frozen_string_literal: true

module Stats
  # Everything the admin stats page shows, computed in a handful of grouped
  # queries over `events` (traffic, probes) and `calls` (money). Amounts are
  # integer µUSDC, as everywhere else; the view formats them.
  class Overview
    Window = Data.define(:label, :page_views, :visitors, :probes, :rejected, :settled, :payers, :volume, :commission)
    Day = Data.define(:date, :page_views, :probes, :settled, :volume)
    ServiceRow = Data.define(:slug, :name, :probes, :rejected, :settled, :volume, :status)
    Report = Data.define(:generated_at, :windows, :days, :services, :referrers, :pages, :clients, :countries, :cities, :recent_calls, :recent_probes)

    WINDOWS = { "24 hours" => 1, "7 days" => 7, "30 days" => 30, "All time" => nil }.freeze

    def initialize(days: 30, now: Time.current)
      @days = days
      @now = now
    end

    def call
      Result.success(report: Report.new(
        generated_at: @now,
        windows: WINDOWS.map { |label, days| window(label, days) },
        days: daily_series,
        services: per_service,
        referrers: top(Event.named("page_view").since(from), :referrer_host),
        pages: top(Event.named("page_view").since(from), :path),
        clients: top(Event.where(name: %w[payment_required payment_rejected catalog_api mcp_call]).since(from), :client),
        countries: top(Event.since(from), :country),
        cities: top(Event.since(from), :city),
        recent_calls: Call.order(created_at: :desc).limit(20).to_a,
        recent_probes: Event.where(name: %w[payment_required payment_rejected coming_soon]).order(created_at: :desc).limit(20).to_a
      ))
    end

    private

    def from = @now - @days.days

    def window(label, days)
      events = days ? Event.since(@now - days.days) : Event.all
      calls = days ? Call.since(@now - days.days) : Call.all
      views = events.named("page_view")
      Window.new(
        label: label,
        page_views: views.count,
        visitors: views.distinct.count(:visitor),
        probes: events.named("payment_required").count,
        rejected: events.named("payment_rejected").count,
        settled: calls.count,
        payers: calls.distinct.count(:payer_address),
        volume: calls.sum(:amount),
        commission: calls.sum(:commission)
      )
    end

    def daily_series
      start = (@now - (@days - 1).days).beginning_of_day
      views = count_by_day(Event.named("page_view").since(start))
      probes = count_by_day(Event.named("payment_required").since(start))
      settled = count_by_day(Call.since(start))
      volume = Call.since(start).group(Arel.sql("date(created_at)")).sum(:amount).transform_keys(&:to_date)
      (0...@days).map do |i|
        date = (start + i.days).to_date
        Day.new(date: date, page_views: views[date] || 0, probes: probes[date] || 0, settled: settled[date] || 0, volume: volume[date] || 0)
      end
    end

    def count_by_day(relation)
      relation.group(Arel.sql("date(created_at)")).count.transform_keys(&:to_date)
    end

    def per_service
      probes = Event.named("payment_required").since(from).group(:service_slug).count
      rejected = Event.named("payment_rejected").since(from).group(:service_slug).count
      settled = Call.since(from).group(:service_slug).count
      volume = Call.since(from).group(:service_slug).sum(:amount)
      Catalog::Service.all.map do |s|
        ServiceRow.new(slug: s.slug, name: s.name, status: s.status,
                       probes: probes[s.slug] || 0, rejected: rejected[s.slug] || 0,
                       settled: settled[s.slug] || 0, volume: volume[s.slug] || 0)
      end.sort_by { |r| [ -r.volume, -r.probes ] }
    end

    def top(relation, column, limit: 10)
      relation.where.not(column => [ nil, "" ]).group(column).order(Arel.sql("count(*) DESC")).limit(limit).count.to_a
    end
  end
end
