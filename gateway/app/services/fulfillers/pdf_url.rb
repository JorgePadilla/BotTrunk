# frozen_string_literal: true

module Fulfillers
  # Built-in service: a page printed to PDF by a real browser, base64 in JSON.
  # The paper a human keeps — an invoice, a receipt, a terms page as it stood
  # on the day — produced by an agent that cannot print.
  # Input: { url, format, landscape, wait_for }.
  # Output: { pdf_base64, format, paper, bytes, url, captured_at }.
  class PdfUrl < RenderedCapture
    PAPER = %w[a4 letter legal tabloid a3 a5].freeze
    DEFAULT_PAPER = "a4"

    private

    def action = "pdf"
    def format = "pdf"

    def payload(bytes)
      { pdf_base64: Base64.strict_encode64(bytes), format: "pdf", paper: paper }
    end

    def render_options
      { pdfOptions: { format: paper.capitalize, landscape: landscape?, printBackground: true } }.merge(wait_for)
    end

    def landscape? = ActiveModel::Type::Boolean.new.cast(input["landscape"]).present?

    # An unknown paper size falls back to A4 rather than refusing: the buyer
    # asked for a PDF, and we can still give them one.
    def paper
      asked = input["format"].to_s.strip.downcase
      PAPER.include?(asked) ? asked : DEFAULT_PAPER
    end
  end
end
