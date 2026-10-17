# frozen_string_literal: true

# A fake judge endpoint for the judgment services: canned answers in the
# provider's wire shape, configuration that is set only for the block, and a
# way to read back what we sent.
module JudgeHelpers
  JUDGE_ENDPOINT = "https://judge.test/v1/answer"
  JUDGE_MODEL = "judge-test-1"

  def with_judge_key(key = "test-key")
    previous = ENV.to_h.slice("JUDGE_API_URL", "JUDGE_API_KEY", "JUDGE_MODEL")
    ENV["JUDGE_API_URL"] = JUDGE_ENDPOINT
    ENV["JUDGE_MODEL"] = JUDGE_MODEL
    ENV["JUDGE_API_KEY"] = key
    yield
  ensure
    %w[JUDGE_API_URL JUDGE_API_KEY JUDGE_MODEL].each { |name| ENV[name] = previous[name] }
  end

  # answers: { "id" => yes_no(0.9), "id2" => choice(…), … }
  def stub_judge(answers)
    body = { model: JUDGE_MODEL, answers: answers, usage: { input_tokens: 300, output_tokens: 20 } }
    stub_request(:post, JUDGE_ENDPOINT)
      .with { |request| (@judge_bodies ||= []) << request.body }
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  # A yes/no answer as the provider sends it.
  def yes_no(p) = { "type" => Judgment::Judge::WIRE_YES_NO, Judgment::Judge::WIRE_YES_NO => p }

  def score(value, confidence: 0.9) = { "type" => "score", "score" => value, "confidence" => confidence }

  def choice(winner, probabilities, confidence: 0.9)
    { "type" => "choice", "choice" => winner, "confidence" => confidence, "probabilities" => probabilities }
  end

  # The body of the last request that reached the endpoint stubbed by `stub_judge`.
  def judge_request_body = JSON.parse(@judge_bodies.last)
end
