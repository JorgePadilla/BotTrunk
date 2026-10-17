# frozen_string_literal: true

require "test_helper"

module Fulfillers
  class PageFitTest < ActiveSupport::TestCase
    HTML = <<~HTML
      <html><head><title>Honduras</title></head><body><main>
        <h1>Honduras</h1>
        <p>Honduras is a country in Central America, bordered by Guatemala, El Salvador and Nicaragua.</p>
        <p>Its capital and largest city is Tegucigalpa, in the south-central highlands.</p>
        <p>Short.</p>
      </main></body></html>
    HTML

    setup do
      stub_request(:get, "https://example.com/honduras").to_return(status: 200, body: HTML, headers: { "Content-Type" => "text/html" })
    end

    def fit(question = "What is the capital of Honduras?")
      PageFit.new(input: { "url" => "https://example.com/honduras", "question" => question }).call
    end

    def stub_answers(answers_p, evidence = "p1")
      stub_judge("answers" => yes_no(answers_p), "relevance" => score(1.97),
               "evidence" => choice(evidence, { "p0" => 0.05, "p1" => 0.93, "none" => 0.02 }, confidence: 0.91))
    end

    test "returns the paragraph that answers, copied from the page" do
      with_judge_key do
        stub_answers(0.99)

        out = JSON.parse(fit[:body])
        assert_equal 0.99, out["answers"]
        assert_equal 1.97, out["relevance"]
        assert_equal "Its capital and largest city is Tegucigalpa, in the south-central highlands.", out["evidence"]
        assert_equal 0.91, out["evidence_confidence"]
      end
    end

    test "offers paragraphs as opaque ids plus none, and skips blocks too short to be evidence" do
      with_judge_key do
        stub_answers(0.99)
        fit

        body = judge_request_body
        paragraphs = body.dig("state", "page", "paragraphs")
        assert_equal %w[p0 p1], paragraphs.keys
        assert_equal %w[p0 p1 none], body.dig("questions", "evidence", "criteria").keys
        assert_equal "What is the capital of Honduras?", body.dig("state", "question")
      end
    end

    test "reads an infobox as plain text: no image, link targets, footnote marks or empty cells" do
      infobox = <<~HTML
        <html><body><main><table>
          <tr><td><a href="/wiki/File:Map.svg"><img src="//img.example/map.png" alt="Location of Honduras"></a></td></tr>
          <tr><th>Capital<br>and largest city</th><td><a href="/wiki/Tegucigalpa" title="Tegucigalpa">Tegucigalpa</a><sup><a href="#cite-1">[1]</a></sup></td></tr>
          <tr><th>Currency</th><td>Lempira&nbsp;(HNL)</td></tr>
        </table></main></body></html>
      HTML
      stub_request(:get, "https://example.com/honduras").to_return(status: 200, body: infobox, headers: { "Content-Type" => "text/html" })

      with_judge_key do
        stub_answers(0.99, "p0")
        evidence = JSON.parse(fit[:body])["evidence"]

        assert_includes evidence, "Capital and largest city | Tegucigalpa"
        assert_includes evidence, "Currency | Lempira (HNL)"
        assert_no_match(/\]\(|map\.png|\[1\]|\| \||&nbsp;/, evidence)
        assert_equal evidence, judge_request_body.dig("state", "page", "paragraphs", "p0")
      end
    end

    test "cuts a block too long to be evidence into pieces at line breaks" do
      lines = (1..60).map { |i| "<li>Item #{i}: #{"a fact about the country " * 2}</li>" }.join
      stub_request(:get, "https://example.com/honduras").to_return(status: 200, body: "<html><body><main><ul>#{lines}</ul></main></body></html>", headers: { "Content-Type" => "text/html" })

      with_judge_key do
        stub_answers(0.99, "p0")
        fit

        paragraphs = judge_request_body.dig("state", "page", "paragraphs").values
        assert_operator paragraphs.size, :>, 1
        assert paragraphs.all? { |p| p.length <= PageFit::MAX_CHARS }
        assert_includes paragraphs.last, "Item 60"
      end
    end

    test "returns no evidence when the page does not answer" do
      with_judge_key do
        stub_answers(0.2)
        assert_nil JSON.parse(fit[:body])["evidence"]
      end
    end

    test "needs a question of reasonable length" do
      with_judge_key do
        assert_equal 422, fit("")[:status]
        assert_equal 422, fit("why? " * 300)[:status]
        assert_not_requested :post, JudgeHelpers::JUDGE_ENDPOINT
      end
    end
  end
end
