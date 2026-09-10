class CreateSellerInquiries < ActiveRecord::Migration[8.1]
  def change
    create_table :seller_inquiries do |t|
      t.string :email, null: false
      t.string :service_name, null: false
      t.string :upstream_url, null: false
      t.bigint :price_atomic, null: false
      t.text :notes
      t.timestamps
    end

    add_index :seller_inquiries, :email
  end
end
