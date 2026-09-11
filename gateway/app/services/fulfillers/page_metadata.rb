# frozen_string_literal: true

module Fulfillers
  # Built-in service: everything a machine needs to describe a page without
  # reading it — title, description, canonical URL, OpenGraph and Twitter
  # cards, favicon, language, and any feeds it advertises.
  # Input: { url }. Output: { title, description, canonical, lang, favicon,
  # open_graph, twitter, feeds, robots }.
  class PageMetadata < Base
    def call
      uri = public_uri { |failure| return failure }
      response, failure = fetch(uri)
      return failure if failure

      doc = Nokogiri::HTML(response.body)
      json(extract(doc, uri))
    end

    private

    def extract(doc, uri)
      {
        url: uri.to_s,
        title: text(doc.at("title")) || meta(doc, "og:title"),
        description: meta(doc, "description") || meta(doc, "og:description"),
        canonical: absolute(doc.at("link[rel='canonical']")&.[]("href"), uri),
        lang: doc.at("html")&.[]("lang"),
        favicon: absolute(favicon_href(doc), uri),
        open_graph: namespaced(doc, "og:"),
        twitter: namespaced(doc, "twitter:"),
        feeds: feeds(doc, uri),
        robots: meta(doc, "robots")
      }.compact
    end

    def text(node) = node&.text&.squish.presence

    def meta(doc, name)
      node = doc.at("meta[property='#{name}']") || doc.at("meta[name='#{name}']")
      node&.[]("content")&.squish.presence
    end

    def namespaced(doc, prefix)
      pairs = doc.css("meta[property^='#{prefix}'], meta[name^='#{prefix}']").filter_map do |node|
        key = (node["property"] || node["name"]).to_s.delete_prefix(prefix)
        value = node["content"].to_s.squish
        [ key, value ] if key.present? && value.present?
      end
      pairs.to_h.presence
    end

    def favicon_href(doc)
      node = doc.at("link[rel='icon']") || doc.at("link[rel='shortcut icon']") || doc.at("link[rel='apple-touch-icon']")
      node&.[]("href") || "/favicon.ico"
    end

    def feeds(doc, uri)
      doc.css("link[type='application/rss+xml'], link[type='application/atom+xml']").filter_map do |node|
        url = absolute(node["href"], uri)
        { title: node["title"].to_s.squish.presence, url: url }.compact if url
      end.presence
    end

    def absolute(href, uri)
      return nil if href.blank?

      URI.join(uri, href).to_s
    rescue URI::Error
      nil
    end
  end
end
