# frozen_string_literal: true

module Dashboard
  # Tiny sub-navigation for the admin pages. `queue:` shows how many deposits wait.
  class AdminNavComponent < ApplicationComponent
    def initialize(active:, queue: 0)
      @active = active
      @queue = queue
    end

    def links
      [ [ "Stats", "/admin/stats" ], [ @queue.positive? ? "Orders · #{@queue} pending" : "Orders", "/admin/orders" ] ]
    end

    def active?(label) = label.start_with?(@active)
  end
end
