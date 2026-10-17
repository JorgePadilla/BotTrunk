# frozen_string_literal: true

module Sellers
  # A seller's signing secret: hidden until they open it, copyable, and
  # rotatable. Rotating takes effect on the next call we forward, so the
  # seller should update their API first and rotate second.
  class SecretRevealComponent < ApplicationComponent
    def initialize(secret:, rotate_url:)
      @secret = secret
      @rotate_url = rotate_url
    end

    attr_reader :secret, :rotate_url

    def masked = "#{secret.first(8)}#{'•' * 16}"
  end
end
