# frozen_string_literal: true

module Fulfillers
  # Built-in service: every link on a page, resolved to absolute URLs and
  # split into internal and external — what a crawling agent needs before it
  # decides where to go next.
  # Input: { url, same_host?, limit? }. Output: { links, internal, external, total }.
  class ExtractLinks < Base
    MAX_LINKS = 500

    def call
      uri = public_uri { |failure| return failure }
      limit = (input["limit"] || MAX_LINKS).to_i.clamp(1, MAX_LINKS)
      same_host = input["same_host"].to_s == "true" || input["same_host"] == true

      response, failure = fetch(uri)
      return failure if failure

      links = links_from(Nokogiri::HTML(response.body), uri)
      links = links.select { |l| l[:internal] } if same_host
      json({
        url: uri.to_s,
        total: links.size,
        internal: links.count { |l| l[:internal] },
        external: links.count { |l| !l[:internal] },
        links: links.first(limit)
      })
    end

    private

    def links_from(doc, uri)
      seen = {}
      doc.css("a[href]").each do |node|
        href = node["href"].to_s.strip
        next if href.blank? || href.start_with?("#", "javascript:", "mailto:", "tel:")

        absolute = begin
          URI.join(uri, href)
        rescue URI::Error
          next
        end
        next unless absolute.is_a?(URI::HTTP)

        key = absolute.to_s
        next if seen.key?(key)

        seen[key] = {
          url: key,
          text: node.text.squish.truncate(120).presence,
          rel: node["rel"].presence,
          internal: absolute.host == uri.host
        }.compact
      end
      seen.values
    end
  end
end
