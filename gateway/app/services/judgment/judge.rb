# frozen_string_literal: true

module Judgment
  # The hosted judgment model behind the judgment services: a state plus
  # typed questions in (yes/no, choice, score), typed answers with
  # probabilities out. It never writes text, which is why it can sit behind a
  # 2-cent endpoint: fractions of a cent per call and ~100 ms an answer.
  # Every question, threshold and rule we ask it with lives in
  # Judgment::Rubrics.
  #
  # Which provider and model answer is configuration (JUDGE_API_URL,
  # JUDGE_MODEL, JUDGE_API_KEY), never part of what a buyer sees: responses
  # carry Rubrics::VERSION instead.
  #
  # The provider's own name for a yes/no question is kept in WIRE_YES_NO and
  # translated here, both ways, so the rest of the app speaks `yes_no` and
  # reads its probability from `p`.
  #
  # It retries 408/429/5xx itself, honouring `retry-after`, inside a small
  # budget: a paid call must not hang a Puma thread for a minute.
  #
  # `call` returns [payload, failure]: { "answers", "model", "usage" } with
  # answers normalised, or nil and a message for the caller to wrap.
  class Judge
    WIRE_YES_NO = "noul"
    TIMEOUT = 10
    OPEN_TIMEOUT = 5
    RETRY_STATUSES = [ 408, 429, 500, 502, 503, 504, 529 ].freeze
    MAX_RETRIES = 2
    RETRY_BUDGET = 8.0   # seconds spent waiting across all retries

    class << self
      def url = ENV["JUDGE_API_URL"].presence
      def token = ENV["JUDGE_API_KEY"].presence
      # Pinned in config, never "latest": the thresholds in Rubrics were tuned against one version.
      def model = ENV["JUDGE_MODEL"].presence
      def configured? = url.present? && token.present? && model.present?
    end

    # Test hook: the waits between retries.
    cattr_accessor :sleeper, default: ->(seconds) { sleep(seconds) }

    def initialize(state:, questions:, connection: nil)
      @state = state
      @questions = questions
      @connection = connection
    end

    def call
      return [ nil, "judging is not configured" ] unless self.class.configured?

      waited = 0.0
      (MAX_RETRIES + 1).times do |attempt|
        response, failure = post
        return [ parse(response), nil ] if response&.success?

        delay = retry_delay(response, attempt)
        if attempt == MAX_RETRIES || delay.nil? || waited + delay > RETRY_BUDGET
          return [ nil, failure || "judge answered #{response.status}" ]
        end

        sleeper.call(delay)
        waited += delay
      end
    rescue JSON::ParserError
      [ nil, "judge answered with something that is not JSON" ]
    end

    private

    def post
      response = connection.post(self.class.url) do |req|
        req.headers["Authorization"] = "Bearer #{self.class.token}"
        req.headers["Content-Type"] = "application/json"
        req.body = { model: self.class.model, state: @state, questions: wire_questions }.to_json
      end
      [ response, nil ]
    rescue Faraday::Error => e
      [ nil, "judge unreachable: #{e.message.truncate(120)}" ]
    end

    def wire_questions
      @questions.transform_values do |q|
        q[:type] == "yes_no" ? q.merge(type: WIRE_YES_NO) : q
      end
    end

    # nil means "do not retry". A connection error retries like a 5xx.
    def retry_delay(response, attempt)
      return 0.5 * (2**attempt) if response.nil?
      return nil unless RETRY_STATUSES.include?(response.status)

      after = response.headers["retry-after"].to_s
      after.match?(/\A\d+(\.\d+)?\z/) ? after.to_f : 0.5 * (2**attempt)
    end

    def parse(response)
      payload = JSON.parse(response.body.to_s)
      request_id = response.headers.find { |name, _| name.to_s.downcase.end_with?("request-id") }&.last
      Rails.logger.info("[judge] model=#{payload["model"]} input_tokens=#{payload.dig("usage", "input_tokens")} request_id=#{request_id}")

      answers = (payload["answers"] || {}).transform_values do |answer|
        next answer unless answer["type"] == WIRE_YES_NO

        { "type" => "yes_no", "p" => answer[WIRE_YES_NO] }
      end
      payload.merge("answers" => answers)
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.options.open_timeout = OPEN_TIMEOUT
        f.options.timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end
  end
end
