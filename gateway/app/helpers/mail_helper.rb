# frozen_string_literal: true

# Formatting that only emails need. Views elsewhere have the full design
# system; an email has inline styles and no CSS file, so the shared bits live
# here instead of being retyped in every template.
module MailHelper
  MUTED = "#666666"
  INK = "#171717"
  HAIRLINE = "#e5e5e5"

  # L1,000 — the amount a person will compare against their bank app.
  def hnl(amount) = "L#{number_with_delimiter(amount.to_i)}"

  # Bank account numbers are encrypted at rest and we do not repeat them in
  # full over email; the last four are enough to recognise an order, and the
  # admin queue has the rest.
  def masked_account(number)
    digits = number.to_s.gsub(/\D/, "")
    return "—" if digits.blank?

    digits.length <= 4 ? digits : "••••#{digits[-4, 4]}"
  end

  def explorer_url(transaction_id) = "https://allo.info/tx/#{transaction_id}"

  # One labelled line of a receipt. `mono:` for anything a person may compare
  # character by character: references, addresses, transaction ids.
  def receipt_row(label, value, mono: false)
    return "".html_safe if value.blank?

    tag.tr do
      tag.td(label, style: "padding:6px 16px 6px 0;color:#{MUTED};font-size:14px;vertical-align:top;white-space:nowrap") +
        tag.td(value, style: "padding:6px 0;color:#{INK};font-size:14px;#{'font-family:ui-monospace,SFMono-Regular,Menlo,monospace;' if mono}word-break:break-word")
    end
  end

  def mail_button(label, url)
    tag.a(label, href: url,
          style: "display:inline-block;background:#{INK};color:#ffffff;text-decoration:none;" \
                 "padding:11px 18px;border-radius:8px;font-size:14px;font-weight:600")
  end
end
