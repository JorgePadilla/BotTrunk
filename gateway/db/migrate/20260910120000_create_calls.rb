class CreateCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :calls do |t|
      t.string :service_slug, null: false
      t.string :payer_address
      t.string :pay_to, null: false
      t.string :network, null: false
      t.string :asset, null: false
      t.bigint :amount, null: false
      t.bigint :commission, null: false
      t.bigint :seller_amount, null: false
      t.string :transaction_id
      t.integer :upstream_status
      t.integer :upstream_latency_ms
      t.string :status, null: false, default: "settled"
      t.timestamps
    end

    add_index :calls, :service_slug
    add_index :calls, :transaction_id, unique: true, where: "transaction_id IS NOT NULL"
  end
end
