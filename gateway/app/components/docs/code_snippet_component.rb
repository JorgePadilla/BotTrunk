# frozen_string_literal: true

module Docs
  # Tabbed code block. `snippets:` is an ordered hash { "curl" => "...", "Python" => "..." }.
  # Tabs switch client-side (tabs Stimulus controller); a copy button copies the visible one.
  class CodeSnippetComponent < ApplicationComponent
    def initialize(snippets:, copy: true)
      @snippets = snippets
      @copy = copy
    end

    def languages = @snippets.keys
    def copy? = @copy

    def each_snippet
      @snippets.each_with_index { |(lang, code), i| yield lang, code, i }
    end
  end
end
