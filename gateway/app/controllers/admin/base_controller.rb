# frozen_string_literal: true

module Admin
  # Everything under /admin is behind HTTP basic auth. One shared password,
  # from credentials `admin.password` or ENV ADMIN_PASSWORD; no password, no
  # admin (the routes answer 401 rather than opening up).
  class BaseController < ApplicationController
    before_action :authenticate!

    private

    def authenticate!
      expected = self.class.password
      authenticated = expected.present? && authenticate_with_http_basic do |_user, given|
        ActiveSupport::SecurityUtils.secure_compare(given.to_s, expected)
      end
      request_http_basic_authentication("BotTrunk admin") unless authenticated
    end

    def self.password
      ENV["ADMIN_PASSWORD"].presence || Rails.application.credentials.dig(:admin, :password).presence
    end
  end
end
