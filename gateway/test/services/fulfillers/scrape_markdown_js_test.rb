# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class ScrapeMarkdownJsTest < ActiveSupport::TestCase
    ENDPOINT = "https://api.cloudflare.com/client/v4/accounts/acct-1/browser-rendering/content"

    # What a client-side app looks like once a browser has run it. The point of
    # this service is that a plain fetch would have returned the empty shell.
    RENDERED = <<~HTML
      <html><head><title>Dashboard — Example</title></head>
      <body>
        <nav><a href="/">Home</a></nav>
        <main><h1>Results</h1><table class="results"><tr><td>42</td></tr></table></main>
        <script>hydrate()</script>
      </body></html>
    HTML

    setup do
      ENV["CLOUDFLARE_API_TOKEN"] = "tok"
      ENV["CLOUDFLARE_ACCOUNT_ID"] = "acct-1"
    end

    teardown do
      ENV.delete("CLOUDFLARE_API_TOKEN")
      ENV.delete("CLOUDFLARE_ACCOUNT_ID")
    end

    test "renders the page and runs it through the same markdown pipeline" do
      stub_request(:post, ENDPOINT)
        .to_return(status: 200, body: { success: true, result: RENDERED }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = ScrapeMarkdownJs.new(input: { "url" => "https://example.com/app" }).call
      assert result.success?

      out = JSON.parse(result[:body])
      assert_equal "Dashboard — Example", out["title"]
      assert_includes out["markdown"], "# Results"
      assert_includes out["markdown"], "42"
      assert_not_includes out["markdown"], "Home"     # nav stripped, same as the plain service
      assert_not_includes out["markdown"], "hydrate"  # script stripped
    end

    test "a raw HTML body is accepted as well as the v4 envelope" do
      stub_request(:post, ENDPOINT).to_return(status: 200, body: RENDERED, headers: { "Content-Type" => "text/html" })

      result = ScrapeMarkdownJs.new(input: { "url" => "https://example.com/app" }).call
      assert result.success?
      assert_includes JSON.parse(result[:body])["markdown"], "# Results"
    end

    test "wait_for is forwarded to the renderer as waitForSelector" do
      stub_request(:post, ENDPOINT)
        .with(body: { url: "https://example.com/app", waitForSelector: "table.results" }.to_json)
        .to_return(status: 200, body: { success: true, result: RENDERED }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = ScrapeMarkdownJs.new(input: { "url" => "https://example.com/app", "wait_for" => "table.results" }).call
      assert result.success?
    end

    test "selector still scopes the extraction, and one that matches nothing is a 422" do
      stub_request(:post, ENDPOINT)
        .to_return(status: 200, body: { success: true, result: RENDERED }.to_json,
                   headers: { "Content-Type" => "application/json" }).times(2)

      scoped = ScrapeMarkdownJs.new(input: { "url" => "https://example.com/app", "selector" => "table.results" }).call
      assert_includes JSON.parse(scoped[:body])["markdown"], "42"
      assert_not_includes JSON.parse(scoped[:body])["markdown"], "# Results"

      missed = ScrapeMarkdownJs.new(input: { "url" => "https://example.com/app", "selector" => ".nope" }).call
      assert_equal 422, missed[:status]
    end

    # The buyer must never pay for a render that did not happen. Both of these
    # are Result.failure, which HandlePaidCall never settles.
    test "a renderer outage fails rather than returning an empty page" do
      stub_request(:post, ENDPOINT).to_return(status: 503, body: "")

      result = ScrapeMarkdownJs.new(input: { "url" => "https://example.com/app" }).call
      assert_not result.success?
    end

    test "an unconfigured renderer fails instead of silently falling back to a plain fetch" do
      ENV.delete("CLOUDFLARE_API_TOKEN")

      result = ScrapeMarkdownJs.new(input: { "url" => "https://example.com/app" }).call
      assert_not result.success?
    end

    test "the public-URL guard still applies before anything is rendered" do
      result = ScrapeMarkdownJs.new(input: { "url" => "http://169.254.169.254/latest/meta-data" }).call
      assert_equal 422, result[:status]
    end
  end
end
