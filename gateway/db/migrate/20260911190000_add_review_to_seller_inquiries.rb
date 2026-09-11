# frozen_string_literal: true

# A seller inquiry used to be a row and an email, with no record of what we
# decided about it. Nothing listed a service without someone deciding to, but
# "someone decided" lived in a mailbox.
class AddReviewToSellerInquiries < ActiveRecord::Migration[8.1]
  def change
    add_column :seller_inquiries, :status, :string, null: false, default: "pending"
    add_column :seller_inquiries, :reviewed_at, :datetime
    add_column :seller_inquiries, :review_notes, :text
    add_index :seller_inquiries, [ :status, :created_at ]
  end
end
