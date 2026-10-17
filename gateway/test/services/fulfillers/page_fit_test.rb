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
