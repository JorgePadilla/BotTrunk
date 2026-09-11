# frozen_string_literal: true

# Display helpers for /admin/stats.
module StatsHelper
  # "HN" → "Honduras" for the handful of codes we see most; unknown codes pass through.
  COUNTRY_NAMES = { "HN" => "Honduras", "US" => "United States", "MX" => "Mexico", "GT" => "Guatemala", "SV" => "El Salvador",
                    "NI" => "Nicaragua", "CR" => "Costa Rica", "PA" => "Panama", "CO" => "Colombia", "AR" => "Argentina", "BR" => "Brazil",
                    "CL" => "Chile", "PE" => "Peru", "ES" => "Spain", "GB" => "United Kingdom", "DE" => "Germany", "FR" => "France",
                    "NL" => "Netherlands", "IN" => "India", "SG" => "Singapore", "JP" => "Japan", "CA" => "Canada", "AU" => "Australia" }.freeze

  def country_name(code)
    return "—" if code.blank?

    "#{COUNTRY_NAMES.fetch(code, code)} (#{code})"
  end
end
