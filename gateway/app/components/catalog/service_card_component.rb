# frozen_string_literal: true

module Catalog
  # One catalog entry: name, one-line summary, price + latency, provider. Nothing else — on purpose.
  class ServiceCardComponent < ApplicationComponent
    def initialize(service:)
      @service = service
    end

    attr_reader :service
  end
end
