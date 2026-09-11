# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class PageMetadataTest < ActiveSupport::TestCase
    HTML = <<~HTML
      <html lang="en"><head>
        <title>  Pricing — Example  </title>
        <meta name="description" content="Simple, honest pricing.">
        <meta property="og:title" content="Example Pricing">
        <meta property="og:image" content="/card.png">
        <meta name="twitter:site" content="@example">
        <link rel="canonical" href="https://example.com/pricing">
        <link rel="icon" href="/favicon.png">
        <link rel="alternate" type="application/rss+xml" title="Blog" href="/feed.xml">
        <meta name="robots" content="index,follow">
      </head><body><h1>Pricing</h1></body></html>
    HTML

    test "returns the metadata a machine needs, with relative URLs made absolute" do
      stub_request(:get, "https://example.com/pricing").to_return(status: 200, body: HTML, headers: { "Content-Type" => "text/html" })

      result = PageMetadata.new(input: { "url" => "https://example.com/pricing" }).call
      assert result.success?
      assert_equal 200, result[:status]

      out = JSON.parse(result[:body])
      assert_equal "Pricing — Example", out["title"]
      assert_equal "Simple, honest pricing.", out["description"]
      assert_equal "https://example.com/pricing", out["canonical"]
      assert_equal "en", out["lang"]
      assert_equal "https://example.com/favicon.png", out["favicon"]
      assert_equal "Example Pricing", out.dig("open_graph", "title")
      assert_equal "/card.png", out.dig("open_graph", "image")
      assert_equal "@example", out.dig("twitter", "site")
      assert_equal [ { "title" => "Blog", "url" => "https://example.com/feed.xml" } ], out["feeds"]
      assert_equal "index,follow", out["robots"]
    end

    test "refuses private and malformed URLs without fetching" do
      [ "http://localhost/x", "https://vault.internal/x", "not a url", "" ].each do |url|
        result = PageMetadata.new(input: { "url" => url }).call
        assert_equal 422, result[:status], url
      end
    end

    test "an unreachable page is an upstream failure, not a charge" do
      stub_request(:get, "https://example.com/gone").to_return(status: 404, body: "")
      result = PageMetadata.new(input: { "url" => "https://example.com/gone" }).call
      assert result.failure?
      assert_equal :upstream_error, result.code
      assert_equal 502, result.data[:status]
    end
  end
end
