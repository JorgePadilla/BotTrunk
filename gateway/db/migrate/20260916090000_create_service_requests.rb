# frozen_string_literal: true

# The demand side of the queue. `/sell` could only hear from people with
# something to sell; a buyer who needed work nobody lists had a mailto: link
# and a reply-to address the domain does not receive mail on.
#
# `service_slug` is nullable: a request naming nothing is someone telling us
# what the catalog is missing, which is the row worth reading.
class CreateServiceRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :service_requests do |t|
      t.string :email, null: false
      t.string :service_slug
      t.text :details, null: false
      t.bigint :budget_atomic
      t.string :status, null: false, default: "pending"
      t.datetime :reviewed_at
      t.text :review_notes
      t.timestamps
    end

    add_index :service_requests, [ :status, :created_at ]
    add_index :service_requests, :service_slug
  end
end
