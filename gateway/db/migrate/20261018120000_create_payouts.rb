class CreatePayouts < ActiveRecord::Migration[8.1]
  def change
    create_table :payouts do |t|
      t.references :seller, null: false, foreign_key: true
      t.bigint :amount, null: false
      t.string :asset, null: false, default: "31566704"
      t.string :transaction_id, null: false
      t.datetime :paid_at, null: false
      t.text :notes
      t.timestamps
    end
    add_index :payouts, :transaction_id, unique: true
  end
end
