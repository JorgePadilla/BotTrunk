# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class ScreenshotUrlTest < ActiveSupport::TestCase
    ENDPOINT = "https://api.cloudflare.com/client/v4/accounts/acct-1/browser-rendering/screenshot"

    # Only the first 24 bytes are read (signature + IHDR), so a header plus
    # filler stands in for a real PNG and lets a test name its own size.
    def png(width: 1280, height: 800, padding: 64)
      "\x89PNG\r\n\x1A\n".b + [ 13 ].pack("N") + "IHDR".b + [ width, height ].pack("N2") + ("\0" * padding).b
    end

    def stub_png(bytes, status: 200)
      stub_request(:post, ENDPOINT).to_return(status: status, body: bytes, headers: { "Content-Type" => "image/png" })
    end

    setup do
      ENV["CLOUDFLARE_API_TOKEN"] = "tok"
      ENV["CLOUDFLARE_ACCOUNT_ID"] = "acct-1"
      ScreenshotUrl.retry_delay = 0
    end

    teardown do
      ENV.delete("CLOUDFLARE_API_TOKEN")
      ENV.delete("CLOUDFLARE_ACCOUNT_ID")
      ScreenshotUrl.retry_delay = 1.5
    end

    test "returns the PNG base64 with the size read off the file" do
      bytes = png(width: 1280, height: 2400)
      stub_png(bytes)

      result = ScreenshotUrl.new(input: { "url" => "https://example.com/pricing" }).call
      assert result.success?

      out = JSON.parse(result[:body])
      assert_equal Base64.strict_encode64(bytes), out["image_base64"]
      assert_equal bytes, Base64.strict_decode64(out["image_base64"]), "round-trips to the same file"
      assert_equal "png", out["format"]
      assert_equal 1280, out["width"]
      assert_equal 2400, out["height"], "the real height, not the viewport we asked for"
      assert_equal bytes.bytesize, out["bytes"]
      assert_equal "https://example.com/pricing", out["url"]
      assert out["captured_at"].present?
    end

    test "viewport, full_page and wait_for are forwarded to the renderer" do
      stub_request(:post, ENDPOINT)
        .with(body: { url: "https://example.com/app", viewport: { width: 390, height: 844 },
                      screenshotOptions: { fullPage: true }, waitForSelector: "main img" }.to_json)
        .to_return(status: 200, body: png, headers: { "Content-Type" => "image/png" })

      result = ScreenshotUrl.new(input: {
        "url" => "https://example.com/app", "width" => 390, "height" => 844,
        "full_page" => true, "wait_for" => "main img"
      }).call
      assert result.success?
    end

    test "a viewport outside the allowed range is clamped rather than refused" do
      stub_request(:post, ENDPOINT)
        .with(body: hash_including("viewport" => { "width" => 3840, "height" => 240 }))
        .to_return(status: 200, body: png, headers: { "Content-Type" => "image/png" })

      result = ScreenshotUrl.new(input: { "url" => "https://example.com", "width" => 99_999, "height" => 2 }).call
      assert result.success?
    end

    test "a render over the size limit is refused with 422 and never settled" do
      stub_png(png(padding: RenderedCapture::MAX_RENDER_BYTES))

      result = ScreenshotUrl.new(input: { "url" => "https://example.com/huge" }).call
      assert result.success?, "a refusal is still a successful answer; HandlePaidCall is what declines to settle it"
      assert_equal 422, result[:status]
      assert_match(/over the/, JSON.parse(result[:body])["error"])
    end

    test "a busy renderer is retried once, then succeeds" do
      stub_request(:post, ENDPOINT)
        .to_return({ status: 429, body: "too many requests" },
                   { status: 200, body: png, headers: { "Content-Type" => "image/png" } })

      result = ScreenshotUrl.new(input: { "url" => "https://example.com" }).call
      assert result.success?
      assert_requested :post, ENDPOINT, times: 2
    end

    test "a renderer that stays busy fails, so the buyer is never charged" do
      stub_request(:post, ENDPOINT).to_return(status: 429, body: "too many requests")

      result = ScreenshotUrl.new(input: { "url" => "https://example.com" }).call
      assert_not result.success?
      assert_equal :upstream_error, result.code
      assert_requested :post, ENDPOINT, times: 2
    end

    test "an unreachable renderer fails rather than charging for a shot nobody took" do
      stub_request(:post, ENDPOINT).to_timeout

      result = ScreenshotUrl.new(input: { "url" => "https://example.com" }).call
      assert_not result.success?
      assert_equal :upstream_error, result.code
    end

    test "a missing credential fails instead of pretending to render" do
      ENV.delete("CLOUDFLARE_API_TOKEN")

      result = ScreenshotUrl.new(input: { "url" => "https://example.com" }).call
      assert_not result.success?
      assert_not_requested :post, ENDPOINT
    end

    test "a private address is refused before the renderer is called" do
      result = ScreenshotUrl.new(input: { "url" => "http://169.254.169.254/latest/meta-data" }).call
      assert_equal 422, result[:status]
      assert_not_requested :post, ENDPOINT
    end
  end
end
