# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class ExtractLinksTest < ActiveSupport::TestCase
    HTML = <<~HTML
      <html><body>
        <a href="/pricing">Pricing</a>
        <a href="/pricing">Pricing again</a>
        <a href="https://example.com/docs">Docs</a>
        <a href="https://other.test/blog" rel="nofollow">Their blog</a>
        <a href="#top">Top</a>
        <a href="mailto:hi@example.com">Mail</a>
        <a href="javascript:void(0)">JS</a>
      </body></html>
    HTML

    def stub_page
      stub_request(:get, "https://example.com/").to_return(status: 200, body: HTML, headers: { "Content-Type" => "text/html" })
    end

    test "resolves, de-duplicates and classifies every link" do
      stub_page
      result = ExtractLinks.new(input: { "url" => "https://example.com/" }).call
      out = JSON.parse(result[:body])

      assert_equal 3, out["total"], "anchors, mailto and javascript are skipped and duplicates collapse"
      assert_equal 2, out["internal"]
      assert_equal 1, out["external"]
      urls = out["links"].map { |l| l["url"] }
      assert_includes urls, "https://example.com/pricing"
      assert_includes urls, "https://other.test/blog"
      assert_equal "Pricing", out["links"].first["text"]
      assert_equal "nofollow", out["links"].last["rel"]
      assert_equal false, out["links"].last["internal"]
    end

    test "same_host keeps only internal links and limit caps the list" do
      stub_page
      out = JSON.parse(ExtractLinks.new(input: { "url" => "https://example.com/", "same_host" => true }).call[:body])
      assert_equal 2, out["total"]
      assert out["links"].all? { |l| l["internal"] }

      stub_page
      out = JSON.parse(ExtractLinks.new(input: { "url" => "https://example.com/", "limit" => 1 }).call[:body])
      assert_equal 1, out["links"].size
      assert_equal 3, out["total"], "total counts everything found, the list is what was capped"
    end
  end
end
