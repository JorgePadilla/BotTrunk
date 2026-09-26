# frozen_string_literal: true

module Ui
  # Previous / next for a list that has outgrown one screen.
  #
  # Every other query parameter is carried through, so paging never silently
  # drops the search or the category filter the visitor is standing in.
  class PaginationComponent < ApplicationComponent
    def initialize(page:, pages:, path:, params: {})
      @page = page
      @pages = pages
      @path = path
      @params = params.to_h.symbolize_keys.except(:page).compact_blank
    end

    def render? = @pages > 1

    def previous_url = @page > 1 ? url_for_page(@page - 1) : nil

    def next_url = @page < @pages ? url_for_page(@page + 1) : nil

    def label = "Page #{@page} of #{@pages}"

    private

    def url_for_page(number)
      query = @params.merge(number > 1 ? { page: number } : {})
      query.any? ? "#{@path}?#{query.to_query}" : @path
    end
  end
end
