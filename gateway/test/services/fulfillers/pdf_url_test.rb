# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class PdfUrlTest < ActiveSupport::TestCase
    ENDPOINT = "https://api.cloudflare.com/client/v4/accounts/acct-1/browser-rendering/pdf"
    PDF = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n".b

    def stub_pdf(body = PDF)
      stub_request(:post, ENDPOINT).to_return(status: 200, body: body, headers: { "Content-Type" => "application/pdf" })
    end

    setup do
      ENV["CLOUDFLARE_API_TOKEN"] = "tok"
      ENV["CLOUDFLARE_ACCOUNT_ID"] = "acct-1"
      PdfUrl.retry_delay = 0
    end

    teardown do
      ENV.delete("CLOUDFLARE_API_TOKEN")
      ENV.delete("CLOUDFLARE_ACCOUNT_ID")
      PdfUrl.retry_delay = 1.5
    end

    test "returns the PDF base64 with the paper size it used" do
      stub_pdf

      result = PdfUrl.new(input: { "url" => "https://example.com/invoice/8812" }).call
      assert result.success?

      out = JSON.parse(result[:body])
      assert_equal PDF, Base64.strict_decode64(out["pdf_base64"])
      assert_equal "pdf", out["format"]
      assert_equal "a4", out["paper"]
      assert_equal PDF.bytesize, out["bytes"]
      assert_equal "https://example.com/invoice/8812", out["url"]
    end

    test "paper size, orientation and wait_for are forwarded to the renderer" do
      stub_request(:post, ENDPOINT)
        .with(body: { url: "https://example.com/report",
                      pdfOptions: { format: "Letter", landscape: true, printBackground: true },
                      waitForSelector: "table.line-items" }.to_json)
        .to_return(status: 200, body: PDF, headers: { "Content-Type" => "application/pdf" })

      result = PdfUrl.new(input: {
        "url" => "https://example.com/report", "format" => "LETTER",
        "landscape" => true, "wait_for" => "table.line-items"
      }).call
      assert result.success?
    end

    test "an unknown paper size falls back to A4 rather than refusing the call" do
      stub_request(:post, ENDPOINT)
        .with(body: hash_including("pdfOptions" => hash_including("format" => "A4")))
        .to_return(status: 200, body: PDF, headers: { "Content-Type" => "application/pdf" })

      result = PdfUrl.new(input: { "url" => "https://example.com", "format" => "poster" }).call
      assert result.success?
      assert_equal "a4", JSON.parse(result[:body])["paper"]
    end

    test "a document over the size limit is refused with 422 and never settled" do
      stub_pdf("%PDF-1.4".b + ("\0" * RenderedCapture::MAX_RENDER_BYTES).b)

      result = PdfUrl.new(input: { "url" => "https://example.com/book" }).call
      assert_equal 422, result[:status]
      assert_match(/over the/, JSON.parse(result[:body])["error"])
    end

    test "an empty render fails rather than returning an empty file" do
      stub_pdf("")

      result = PdfUrl.new(input: { "url" => "https://example.com" }).call
      assert_not result.success?
      assert_equal :upstream_error, result.code
    end

    test "a private address is refused before the renderer is called" do
      result = PdfUrl.new(input: { "url" => "http://10.0.0.5/internal" }).call
      assert_equal 422, result[:status]
      assert_not_requested :post, ENDPOINT
    end
  end
end
