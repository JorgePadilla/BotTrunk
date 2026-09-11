# frozen_string_literal: true

module Analytics
  # IP → { country:, city: } from a local MaxMind GeoLite2 database. Returns
  # nil (no location) when the database is absent, the IP is private, or the
  # lookup misses — never raises, never calls the network.
  class Geolocate
    DEFAULT_DB = "tmp/geoip/GeoLite2-City.mmdb"

    # Test hook: a lambda ip → hash, so tests need no database file.
    cattr_accessor :stubs_lookup

    class << self
      def call(ip) = stubs_lookup ? stubs_lookup.call(ip) : new.call(ip)

      def reader
        return @reader if defined?(@reader) && @reader_path == db_path

        @reader_path = db_path
        @reader = File.exist?(db_path) ? MaxMind::DB.new(db_path, mode: MaxMind::DB::MODE_MEMORY) : nil
      end

      def db_path = Rails.root.join(ENV.fetch("GEOIP_DB", DEFAULT_DB)).to_s

      def available? = reader.present?
    end

    def call(ip)
      return nil if ip.blank? || private?(ip)

      record = self.class.reader&.get(ip)
      return nil unless record

      country = record.dig("country", "iso_code")
      city = record.dig("city", "names", "en")
      region = record.dig("subdivisions", 0, "names", "en")
      return nil unless country

      { country: country, city: [ city, region ].compact.presence&.join(", ") }
    rescue StandardError => e
      Rails.logger.warn("geoip: lookup failed: #{e.class}: #{e.message}")
      nil
    end

    private

    def private?(ip)
      addr = IPAddr.new(ip)
      addr.private? || addr.loopback? || addr.link_local?
    rescue IPAddr::Error
      true
    end
  end
end
