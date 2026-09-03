# frozen_string_literal: true

module Catalog
  # Category filter row. `active: nil` means "All".
  class FilterChipsComponent < ApplicationComponent
    def initialize(categories:, active: nil, path: "/")
      @categories = categories
      @active = active
      @path = path
    end

    def chips
      [ [ "All", nil ] ] + @categories.map { |c| [ c, c ] }
    end

    def chip_classes(value)
      classes("btn btn-sm rounded-full font-medium h-[34px] px-3.5",
              value == @active ? "btn-neutral" : "btn-outline border-base-300 text-muted hover:text-base-content")
    end

    def chip_path(value) = value ? "#{@path}?category=#{ERB::Util.url_encode(value)}" : @path
  end
end
