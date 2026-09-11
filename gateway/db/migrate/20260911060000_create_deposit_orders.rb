# frozen_string_literal: true

# A human-fulfilled lempira deposit bought with USDC (Fulfillers::DepositBac).
# The bank account number is encrypted at rest (deterministic, so the daily
# per-account limit can be counted).
class CreateDepositOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :deposit_orders do |t|
      t.string :token, null: false
      t.string :service_slug, null: false
      t.references :call, foreign_key: true, null: true
      t.string :status, null: false, default: "awaiting_payment"
      t.integer :amount_hnl, null: false
      t.bigint :price_atomic, null: false
      t.decimal :rate_hnl_per_usd, precision: 10, scale: 4, null: false
      t.integer :fee_bps, null: false
      t.string :bank, null: false, default: "BAC Credomatic"
      t.string :beneficiary_name, null: false
      t.string :account_number, null: false
      t.string :concept
      t.string :contact_email
      t.string :receipt_reference
      t.datetime :delivered_at
      t.string :refund_transaction_id
      t.datetime :refunded_at
      t.text :notes
      t.timestamps
    end

    add_index :deposit_orders, :token, unique: true
    add_index :deposit_orders, [ :status, :created_at ]
    add_index :deposit_orders, [ :account_number, :created_at ]
  end
end
