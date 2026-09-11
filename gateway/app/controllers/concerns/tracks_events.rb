# frozen_string_literal: true

# Controller-side entry point for Analytics::Track: pulls the few request
# facts the service needs and hands them over as plain values, so the
# service never touches the request object.
module TracksEvents
  extend ActiveSupport::Concern

  private

  def track_event(name, service_slug: nil, **properties)
    Analytics::Track.new(
      name: name,
      path: request.path,
      referrer: request.referer,
      user_agent: request.user_agent,
      ip: request.remote_ip,
      service_slug: service_slug,
      properties: properties
    ).call
  end

  # after_action for public HTML pages. Only successful GETs count as a view.
  def track_page_view
    return unless request.get? && response.status == 200 && request.format.html?

    track_event("page_view", service_slug: params[:slug].presence)
  end
end
