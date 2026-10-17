# frozen_string_literal: true

module Gateway
  # Decides whether a caller may have their one free call. The trial exists
  # because the first thing a new agent meets is "fund a wallet", before it
  # has seen a single answer; one free call shows what the money buys.
  #
  # Nothing moves on-chain for a trial: no payment is verified or settled, and
  # it is recorded as a `trial_call` Event, never a Call, so volume and the
  # ledger stay real money only.
  #
  # One per caller per 30 days, keyed on a secret-salted fingerprint of the IP
  # (the daily-rotating `visitor` token cannot count 30 days). The fingerprint
  # is stored on trial events only. At most DAILY_CAP trials a day across
  # everyone, so a botnet costs us that many cheap calls and nothing more.
  class GrantTrial
    HEADER = "X-BotTrunk-Trial"
    EVENT = "trial_call"
    PER_CALLER = 30.days
    DAILY_CAP = 100

    # Cheap built-ins only: nothing rendered by a paid browser, nothing a
    # person fulfils, nothing that moves money.
    SERVICES = %w[injection-check tool-call-gate page-kind page-fit page-metadata extract-links url-health domain-dns email-check].freeze

    def self.requested?(headers) = headers[HEADER].to_s.strip == "1"

    def initialize(service:, ip:, now: Time.current)
      @service = service
      @ip = ip.to_s
      @now = now
    end

    # Success with the caller's `key` (to record on the trial event), or a
    # failure saying why not.
    def call
      return Result.failure("No free trial for #{@service.slug}.", code: :not_eligible) unless eligible?
      return Result.failure("Free trial already used. Pay to continue.", code: :trial_used) if used?
      return Result.failure("No free trials left today. Pay to continue.", code: :trial_cap) if cap_reached?

      Result.success(key: key)
    end

    # For the 402: is it worth telling this caller about the trial?
    def available? = call.success?

    def key = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base.to_s, "trial|#{@ip}")[0, 32]

    private

    def eligible? = SERVICES.include?(@service.slug) && @service.live?

    def used? = trials.since(@now - PER_CALLER).exists?([ "properties->>'trial_key' = ?", key ])

    def cap_reached? = trials.since(@now.beginning_of_day).count >= DAILY_CAP

    def trials = Event.where(name: EVENT)
  end
end
