# frozen_string_literal: true

module Ui
  class PaginationComponentPreview < ViewComponent::Preview
    # First page: no "previous", because there is nowhere back to go.
    def first_page
      render Ui::PaginationComponent.new(page: 1, pages: 4, path: "/services")
    end

    def middle_page
      render Ui::PaginationComponent.new(page: 2, pages: 4, path: "/services")
    end

    def last_page
      render Ui::PaginationComponent.new(page: 4, pages: 4, path: "/services")
    end

    # The filter and the search ride along, so paging never drops them.
    def keeps_the_filters
      render Ui::PaginationComponent.new(page: 2, pages: 3, path: "/", params: { q: "markdown", category: "Data" })
    end

    # One page renders nothing at all (`render?` is false).
    def single_page
      render Ui::PaginationComponent.new(page: 1, pages: 1, path: "/services")
    end
  end
end
