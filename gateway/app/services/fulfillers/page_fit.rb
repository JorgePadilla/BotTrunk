# frozen_string_literal: true

module Fulfillers
  # Built-in service: does this page answer my question, and where? The
  # page is split into paragraphs and the judge picks the one that answers; the
  # `evidence` returned is that paragraph's text as it appears on the page,
  # copied by code, never written by a model. Markdown syntax (images, link
  # targets, table pipes, footnote marks) is removed first: an infobox row is
  # unreadable with it, and the judge reads the same plain text.
  # Input: { url, question }. Output: { answers, relevance, evidence,
  # evidence_confidence, title, url, truncated, version }.
  class PageFit < Judged
    MAX_PARAGRAPHS = 254   # a Choice takes 255 options; one is `none`
    MIN_CHARS = 20         # shorter blocks are headings and buttons, not evidence
    MAX_CHARS = 1_500      # longer blocks are cut at line breaks into pieces about this size
    QUESTION_CHARS = 1_000

    def call
      question = text_input("question", max: QUESTION_CHARS) { |failure| return failure }
      page = fetch_page { |failure| return failure }

      paragraphs = split(page[:text])
      return bad_request("the page has no readable paragraphs") if paragraphs.empty?

      state = { question: question, page: { title: page[:title], paragraphs: paragraphs } }
      payload = judge(state, Judgment::Rubrics.page_fit(paragraphs.keys)) { |failure| return failure }

      answers = payload.dig("answers", "answers", "p")
      evidence = payload.dig("answers", "evidence") || {}
      json({
        answers: answers,
        relevance: payload.dig("answers", "relevance", "score"),
        evidence: at_least?(answers, :evidence) ? paragraphs[evidence["choice"]] : nil,
        evidence_confidence: evidence["confidence"],
        title: page[:title],
        url: page[:url],
        truncated: page[:truncated],
        version: Judgment::Rubrics::VERSION
      })
    end

    private

    # { "p0" => "…", "p1" => "…" }: opaque ids for the Choice, text in the state.
    def split(text)
      blocks = text.split(/\n{2,}/).flat_map { |block| pieces(block) }.map { |block| plain(block) }
      blocks.select { |b| b.length >= MIN_CHARS }.first(MAX_PARAGRAPHS).each_with_index.to_h { |block, i| [ "p#{i}", block ] }
    end

    def pieces(block)
      return [ block ] if block.length <= MAX_CHARS

      block.lines.each_with_object([ +"" ]) do |line, out|
        out << +"" if out.last.length + line.length > MAX_CHARS && out.last.present?
        out.last << line
      end
    end

    def plain(markdown)
      markdown
        .gsub(/!\[[^\]]*\]\([^)]*\)/, "")             # images
        .gsub(/\[\d+\]/, "")                           # footnote marks, before their links
        .gsub(/\[([^\]]*)\]\([^)]*\)/, '\1')          # links keep their text
        .gsub(/^[\s|:-]*-[\s|:-]*$/, "")               # table separator rows
        .gsub("&nbsp;", " ").delete("​﻿")
        .gsub(/(?:\s*\|)+\s*/, " | ").squish                 # empty cells collapse into one separator
        .delete_prefix("| ").delete_suffix(" |").strip
    end
  end
end
