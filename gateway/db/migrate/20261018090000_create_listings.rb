class CreateListings < ActiveRecord::Migration[8.1]
  def change
    create_table :listings do |t|
      t.references :seller, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :name, null: false
      t.string :summary, null: false
      t.text :description
      t.string :category, null: false
      t.string :upstream_url, null: false
      t.bigint :price_atomic, null: false
      t.jsonb :inputs, null: false, default: []
      t.jsonb :outputs, null: false, default: []
      t.string :status, null: false, default: "draft"
      t.text :review_notes
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.datetime :went_live_at
      t.timestamps
    end
    add_index :listings, :slug, unique: true
    add_index :listings, [ :status, :submitted_at ]

    add_reference :calls, :seller, foreign_key: true, null: true
  end
end
