# frozen_string_literal: true

# Jobs a person does at a desk rather than at an address: phone calls, quotes
# chased, a question asked of someone who will only answer out loud. Same
# lifecycle as a deposit — the shape the paid loop already understands — but
# none of the bank columns, because nothing here moves money.
class CreateWorkOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :work_orders do |t|
      t.string :token, null: false
      t.string :service_slug, null: false
      t.string :status, null: false, default: "awaiting_payment"
      t.bigint :call_id
      t.bigint :price_atomic, null: false
      t.string :contact_email

      t.text :brief, null: false          # what the buyer asked for, in their words
      t.jsonb :params, null: false, default: {}   # the structured inputs beside the brief
      t.jsonb :result, null: false, default: {}   # what the person came back with

      t.datetime :delivered_at
      t.datetime :refunded_at
      t.string :refund_transaction_id
      t.text :notes

      t.timestamps
    end

    add_index :work_orders, :token, unique: true
    add_index :work_orders, [ :status, :created_at ]
    add_index :work_orders, :call_id
  end
end
