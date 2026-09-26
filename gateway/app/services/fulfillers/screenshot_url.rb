# frozen_string_literal: true

module Fulfillers
  # Built-in service: a PNG of a page as a browser renders it, base64 in JSON.
  # An agent cannot look at a page; this is the closest it gets — for checking
  # that a deploy looks right, that a competitor's banner says what it claims,
  # or for handing a human a picture of what the agent found.
  # Input: { url, full_page, width, height, wait_for }.
  # Output: { image_base64, format, width, height, bytes, url, captured_at }.
  class ScreenshotUrl < RenderedCapture
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    VIEWPORT = { width: 1280, height: 800 }.freeze
    BOUNDS = (240..3840)

    private

    def action = "screenshot"
    def format = "png"

    def payload(bytes)
      width, height = dimensions(bytes)
      { image_base64: Base64.strict_encode64(bytes), format: "png", width: width, height: height }.compact
    end

    def render_options
      { viewport: viewport, screenshotOptions: { fullPage: full_page? } }.merge(wait_for)
    end

    def full_page? = ActiveModel::Type::Boolean.new.cast(input["full_page"]).present?

    def viewport
      width = Integer(input["width"], exception: false) || VIEWPORT[:width]
      height = Integer(input["height"], exception: false) || VIEWPORT[:height]
      { width: width.clamp(BOUNDS), height: height.clamp(BOUNDS) }
    end

    # Read the size off the PNG header rather than reporting what we asked
    # for: with full_page the height is whatever the page turned out to be.
    def dimensions(bytes)
      head = bytes.byteslice(0, 24).to_s.b
      return [ nil, nil ] unless head.start_with?(PNG_SIGNATURE)

      head.byteslice(16, 8).unpack("N2")
    end
  end
end
