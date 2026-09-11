# frozen_string_literal: true

module Rates
  # Reads the Tipo de Cambio de Referencia from the Banco Central de Honduras
  # Web API (https://bchapi-am.developer.azure-api.net — free account, the
  # key goes in BCH_API_KEY). One request: the most recent figure of the TCR
  # indicator. Returns Result with { rate:, as_of: } or a failure.
  class FetchBch
    BASE = "https://bchapi-am.azure-api.net/api/v1"
    DEFAULT_INDICATOR = 97 # EC-TCR-01 in the BCH catalogue; override with BCH_TCR_INDICATOR_ID
    SANE = (15..45) # lempiras per dollar; anything else means the wrong indicator

    def initialize(api_key: ENV["BCH_API_KEY"], indicator_id: ENV.fetch("BCH_TCR_INDICATOR_ID", DEFAULT_INDICATOR), connection: nil)
      @api_key = api_key
      @indicator_id = indicator_id.to_i
      @connection = connection
    end

    def configured? = @api_key.present?

    def call
      return Result.failure("BCH_API_KEY not set", code: :not_configured) unless configured?

      response = connection.get("#{BASE}/indicadores/#{@indicator_id}/cifras", { reciente: 1, formato: "json" })
      return Result.failure("BCH answered #{response.status}", code: :bch_error) unless response.success?

      row = Array(JSON.parse(response.body)).first
      value = row && row["valor"]
      return Result.failure("BCH returned no figure", code: :bch_empty) unless value.is_a?(Numeric)
      return Result.failure("BCH figure #{value} is not a USD/HNL rate — check BCH_TCR_INDICATOR_ID", code: :bch_unexpected) unless SANE.cover?(value)

      Result.success(rate: BigDecimal(value.to_s), as_of: Date.parse(row["fecha"].to_s))
    rescue Faraday::Error, JSON::ParserError, Date::Error => e
      Result.failure("BCH feed failed: #{e.message.truncate(120)}", code: :bch_error)
    end

    private

    def connection
      @connection ||= Faraday.new(headers: { "Ocp-Apim-Subscription-Key" => @api_key, "Accept" => "application/json" },
                                  request: { open_timeout: 3, timeout: 8 })
    end
  end
end
