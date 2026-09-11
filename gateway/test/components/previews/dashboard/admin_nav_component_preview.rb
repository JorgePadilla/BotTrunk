# frozen_string_literal: true

module Dashboard
  class AdminNavComponentPreview < ViewComponent::Preview
    def default
      render(Dashboard::AdminNavComponent.new(active: "Orders", queue: 3))
    end
  end
end
