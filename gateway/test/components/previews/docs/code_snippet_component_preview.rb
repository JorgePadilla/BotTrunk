# frozen_string_literal: true

module Docs
  class CodeSnippetComponentPreview < ViewComponent::Preview
    def default
      render Docs::CodeSnippetComponent.new(snippets: {
        "curl" => "curl https://api.bottrunk.com/s/scrape-markdown \\\n  -d '{\"url\": \"https://example.com\"}'",
        "Python" => "r = session.post(\"https://api.bottrunk.com/s/scrape-markdown\", json={\"url\": \"https://example.com\"})"
      })
    end
  end
end
