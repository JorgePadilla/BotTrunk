# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class ScrapeMarkdownTest < ActiveSupport::TestCase
    HTML = <<~HTML
      <html><head><title>  Pricing — Example  </title><style>p{}</style></head>
      <body>
        <nav><a href="/">Home</a></nav>
        <main>
          <h1>Pricing</h1>
          <p>Simple, <strong>honest</strong> pricing.</p>
          <ul><li>Free</li><li>Pro</li></ul>
          <div id="faq"><h2>FAQ</h2><p>Yes.</p></div>
        </main>
        <footer>© Example</footer>
        <script>alert(1)</script>
      </body></html>
    HTML

    test "converts the main content to markdown with title and word count" do
      stub_request(:get, "https://example.com/pricing").to_return(status: 200, body: HTML, headers: { "Content-Type" => "text/html" })
      result = ScrapeMarkdown.new(input: { "url" => "https://example.com/pricing" }).call
      assert result.success?
      assert_equal 200, result[:status]

      out = JSON.parse(result[:body])
      assert_equal "Pricing — Example", out["title"]
      assert_includes out["markdown"], "# Pricing"
      assert_includes out["markdown"], "**honest**"
      assert_includes out["markdown"], "- Free"
      assert_not_includes out["markdown"], "Home"      # nav stripped
      assert_not_includes out["markdown"], "alert"     # script stripped
      assert_not_includes out["markdown"], "© Example" # footer stripped
      assert_operator out["word_count"], :>, 5
    end

    test "selector scopes the extraction" do
      stub_request(:get, "https://example.com/pricing").to_return(status: 200, body: HTML)
      out = JSON.parse(ScrapeMarkdown.new(input: { "url" => "https://example.com/pricing", "selector" => "#faq" }).call[:body])
      assert_includes out["markdown"], "FAQ"
      assert_not_includes out["markdown"], "# Pricing"
    end

    test "rejects non-http and private URLs as 422 without fetching" do
      [ "ftp://x", "not a url", "", "http://localhost/admin", "http://db.internal/", "http://nxdomain.test/" ].each do |url|
        result = ScrapeMarkdown.new(input: { "url" => url }).call
        assert result.success?, url
        assert_equal 422, result[:status], url
      end
      assert_not_requested :get, /.*/
    end

    test "upstream 404 and timeouts are 502 failures" do
      stub_request(:get, "https://example.com/missing").to_return(status: 404)
      r = ScrapeMarkdown.new(input: { "url" => "https://example.com/missing" }).call
      assert r.failure?
      assert_equal 502, r[:status]

      stub_request(:get, "https://example.com/slow").to_timeout
      assert_equal :upstream_error, ScrapeMarkdown.new(input: { "url" => "https://example.com/slow" }).call.code
    end
  end
end
