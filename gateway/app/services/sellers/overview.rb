# frozen_string_literal: true

module Sellers
  # What a seller's dashboard shows, from the `calls` ledger and their
  # payouts. Amounts are µUSDC; the view formats them.
  class Overview
    Window = Data.define(:label, :calls, :volume, :earned)
    ListingRow = Data.define(:listing, :calls, :volume, :earned)
    Report = Data.define(:windows, :listings, :recent_calls, :earned, :paid, :owed, :payouts)

    WINDOWS = { "7 days" => 7, "30 days" => 30, "All time" => nil }.freeze

    def initialize(seller:, now: Time.current)
      @seller = seller
      @now = now
    end

    def call
      calls = @seller.calls
      paid = @seller.paid_atomic
      earned = calls.sum(:seller_amount)
      Result.success(report: Report.new(
        windows: WINDOWS.map { |label, days| window(label, days ? calls.since(@now - days.days) : calls) },
        listings: per_listing(calls.since(@now - 30.days)),
        recent_calls: calls.order(created_at: :desc).limit(20).to_a,
        earned: earned, paid: paid, owed: earned - paid,
        payouts: @seller.payouts.order(paid_at: :desc).limit(20).to_a
      ))
    end

    private

    def window(label, calls)
      Window.new(label: label, calls: calls.count, volume: calls.sum(:amount), earned: calls.sum(:seller_amount))
    end

    def per_listing(calls)
      counts = calls.group(:service_slug).count
      volume = calls.group(:service_slug).sum(:amount)
      earned = calls.group(:service_slug).sum(:seller_amount)
      @seller.listings.order(:created_at).map do |l|
        ListingRow.new(listing: l, calls: counts[l.slug] || 0, volume: volume[l.slug] || 0, earned: earned[l.slug] || 0)
      end
    end
  end
end
