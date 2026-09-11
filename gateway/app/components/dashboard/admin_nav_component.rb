# frozen_string_literal: true

module Dashboard
  # Tiny sub-navigation for the admin pages. `queue:` shows how many deposits wait.
  class AdminNavComponent < ApplicationComponent
    def initialize(active:, queue: 0, inquiries: nil)
      @active = active
      @queue = queue
      # nil rather than 0, so a page that does not count them says nothing
      # instead of claiming there are none waiting.
      @inquiries = inquiries
    end

    def links
      [
        [ "Stats", "/admin/stats" ],
        [ @queue.positive? ? "Orders · #{@queue} pending" : "Orders", "/admin/orders" ],
        [ @inquiries.to_i.positive? ? "Sellers · #{@inquiries} to review" : "Sellers", "/admin/inquiries" ]
      ]
    end

    def active?(label) = label.start_with?(@active)
  end
end
