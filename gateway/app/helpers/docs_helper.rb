# frozen_string_literal: true

module DocsHelper
  # Renders `backticks` in plain prose as monospace, so the client notes on
  # /connect read like the docs they were copied from. Everything stays
  # escaped — the text is ours, but there is no reason to build HTML from it.
  def inline_code(text)
    parts = text.to_s.split("`")
    safe_join(parts.each_with_index.map { |part, i| i.odd? ? tag.span(part, class: "font-mono text-base-content") : part })
  end
end
