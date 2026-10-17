# frozen_string_literal: true

module Gateway
  # The free first call (ADR 0010): the service runs and nothing is verified
  # or settled. Only a 200 uses up the trial; a refusal or failure is passed
  # through and the caller can try again. A caller who may not have a trial
  # gets the ordinary 402, with the reason.
  class HandleTrialCall
    FUND_URL = "https://bottrunk.com/connect"

    def initialize(service:, trial:, body:, headers: {})
      @service = service
      @trial = trial
      @body = body
      @headers = headers
    end

    def call
      granted = @trial.call
      return refused(granted.error) if granted.failure?

      upstream = Gateway::ProxyCall.new(service: @service, body: @body, headers: @headers).call
      return Result.failure(upstream.error, code: upstream.code, data: { status: 502, body: { error: upstream.error }.to_json }) if upstream.failure?
      return Result.failure("service rejected the request", code: :rejected_by_service, data: upstream.data.slice(:status, :body, :content_type)) if upstream[:status] >= 400

      Result.success(status: upstream[:status], body: upstream[:body], content_type: upstream[:content_type], trial_key: granted[:key],
                     headers: { "BotTrunk-Trial" => "used", "BotTrunk-Fund" => FUND_URL })
    end

    private

    def refused(reason)
      built = Payments::BuildRequirements.new(service: @service).call
      return built if built.failure?

      body = Payments::BuildRequirements.body_for(service: @service, requirements: built[:accepts]).merge(error: reason)
      Result.failure(reason, code: :payment_required, data: { status: 402, body: body.to_json, content_type: "application/json" })
    end
  end
end
