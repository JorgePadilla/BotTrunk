# frozen_string_literal: true

# The two public forms on /sell, which share one budget per address
# (config.x.rate_limits[:forms]). Each submission emails us, and Resend's free
# tier stops at 100 a day.
#
# This is Rails' rate_limit, not rack-attack like the agent endpoints, because
# the person who hits it needs to see why. A refusal from rack-attack is a bare
# page outside the app's layout, and Turbo answers that by reloading /sell, so
# the submit button looks like it did nothing. Here the page renders again
# with what they typed and the reason, in the spot where form errors appear.
module ThrottlesForms
  extend ActiveSupport::Concern

  included do
    limit = Rails.configuration.x.rate_limits.fetch(:forms)
    rate_limit to: limit[:limit], within: limit[:period], store: RATE_LIMIT_STORE, scope: "forms",
               with: -> { too_many_submissions }, only: :create
  end

  private

  def too_many_submissions
    Rails.logger.warn("rate-limit: forms throttled POST #{request.path} from #{request.remote_ip}")
    contact = ENV.fetch("MAIL_REPLY_TO", "hello@bottrunk.com")
    refuse_submission("Too many submissions from your network this hour. Nothing was sent; try again later, " \
                      "or write to #{contact} and a person will answer.")
    render "pages/sell", status: :too_many_requests
  end
end
