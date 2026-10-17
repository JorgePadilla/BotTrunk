class CreateSellers < ActiveRecord::Migration[8.1]
  def change
    create_table :sellers do |t|
      t.string :email, null: false
      t.string :name
      t.string :payout_address
      t.string :status, null: false, default: "active"
      t.text :signing_secret, null: false
      t.datetime :last_signed_in_at
      t.timestamps
    end
    add_index :sellers, :email, unique: true
  end
end
