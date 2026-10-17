# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class PageKindTest < ActiveSupport::TestCase
    HTML = <<~HTML
      <html><head><title>Sign in · Example</title></head>
      <body><nav>Home</nav><main><h1>Sign in to continue</h1><p>Use your email and password.</p></main></body></html>
    HTML

    def stub_page(status: 200, body: HTML)
      stub_request(:get, "https://example.com/report").to_return(status: status, body: body, headers: { "Content-Type" => "text/html" })
    end

    def kind(url = "https://example.com/report") = PageKind.new(input: { "url" => url }).call

    test "names the kind of page from what scrape-markdown would have read" do
      with_judge_key do
        stub_page
        stub_judge("kind" => choice("login_wall", { "login_wall" => 0.91, "article" => 0.09 }, confidence: 0.9),
                 "content_present" => yes_no(0.08))

        result = kind
        assert result.success?
        out = JSON.parse(result[:body])
        assert_equal "login_wall", out["kind"]
        assert_equal 0.9, out["confidence"]
        assert_equal 0.08, out["content_present"]
        assert_equal "Sign in · Example", out["title"]
        assert_equal false, out["truncated"]

        page = judge_request_body.dig("state", "page")
        assert_equal "https://example.com/report", page["url"]
        assert_includes page["text"], "Sign in to continue"
        assert_not_includes page["text"], "Home"   # same stripping as scrape-markdown
      end
    end

    test "cuts long pages and says so" do
      with_judge_key do
        stub_page(body: "<html><body><main><p>#{"word " * 10_000}</p></main></body></html>")
        stub_judge("kind" => choice("article", { "article" => 1.0 }), "content_present" => yes_no(0.99))

        assert JSON.parse(kind[:body])["truncated"]
        assert_equal Judged::PAGE_CHARS, judge_request_body.dig("state", "page", "text").length
      end
    end

    test "passes a refused URL or a failed fetch through, without asking the judge" do
      with_judge_key do
        assert_equal 422, kind("http://127.0.0.1/admin")[:status]

        stub_page(status: 404)
        assert_equal 502, kind[:status]
        assert_not_requested :post, JudgeHelpers::JUDGE_ENDPOINT
      end
    end
  end
end
