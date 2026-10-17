# frozen_string_literal: true

require "test_helper"

module Judgment
  class JudgeTest < ActiveSupport::TestCase
    QUESTIONS = { "q" => { type: "yes_no", instructions: "Is `text` a greeting?" } }.freeze
    URL = JudgeHelpers::JUDGE_ENDPOINT

    setup do
      @waits = []
      Judge.sleeper = ->(seconds) { @waits << seconds }
    end

    teardown { Judge.sleeper = ->(seconds) { sleep(seconds) } }

    def ask = Judge.new(state: { text: "hello" }, questions: QUESTIONS).call

    test "sends the configured model, the key and the question, and normalises yes/no answers" do
      with_judge_key("k-123") do
        stub_judge({ "q" => yes_no(0.97) })

        payload, failure = ask
        assert_nil failure
        assert_equal({ "type" => "yes_no", "p" => 0.97 }, payload.dig("answers", "q"))

        assert_requested :post, URL, headers: { "Authorization" => "Bearer k-123" }
        body = judge_request_body
        assert_equal JudgeHelpers::JUDGE_MODEL, body["model"]
        assert_equal({ "text" => "hello" }, body["state"])
        assert_equal Judge::WIRE_YES_NO, body.dig("questions", "q", "type")
      end
    end

    test "passes choice and score answers through untouched" do
      with_judge_key do
        stub_judge({ "q" => choice("a", { "a" => 0.9, "b" => 0.1 }) })

        payload, = ask
        assert_equal "a", payload.dig("answers", "q", "choice")
      end
    end

    test "is not configured without a key, and asks nothing" do
      with_judge_key(nil) do
        payload, failure = ask
        assert_nil payload
        assert_equal "judging is not configured", failure
        assert_not_requested :post, URL
      end
    end

    test "retries a 429 after the time the server asks for" do
      with_judge_key do
        stub_request(:post, URL)
          .to_return({ status: 429, headers: { "retry-after" => "2" } },
                     { status: 200, body: { model: "m", answers: { "q" => yes_no(0.1) } }.to_json })

        payload, failure = ask
        assert_nil failure
        assert_equal 0.1, payload.dig("answers", "q", "p")
        assert_equal [ 2.0 ], @waits
      end
    end

    test "gives up after two retries" do
      with_judge_key do
        stub_request(:post, URL).to_return(status: 529)

        payload, failure = ask
        assert_nil payload
        assert_equal "judge answered 529", failure
        assert_requested :post, URL, times: 3
      end
    end

    test "gives up when the server asks for a wait longer than the budget" do
      with_judge_key do
        stub_request(:post, URL).to_return(status: 429, headers: { "retry-after" => "30" })

        _, failure = ask
        assert_equal "judge answered 429", failure
        assert_requested :post, URL, times: 1
        assert_empty @waits
      end
    end

    test "does not retry a refused key" do
      with_judge_key do
        stub_request(:post, URL).to_return(status: 401)

        _, failure = ask
        assert_equal "judge answered 401", failure
        assert_requested :post, URL, times: 1
      end
    end

    test "retries a connection error, then reports it" do
      with_judge_key do
        stub_request(:post, URL).to_timeout

        _, failure = ask
        assert_match(/\Ajudge unreachable/, failure)
        assert_requested :post, URL, times: 3
      end
    end
  end
end
