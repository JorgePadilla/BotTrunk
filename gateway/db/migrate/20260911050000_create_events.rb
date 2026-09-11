# frozen_string_literal: true

# First-party, cookieless analytics. One row per page view / 402 / rejected
# payment. No IP or raw user agent is stored: `visitor` is a daily-rotating
# hash and `client` is the coarse classification we care about.
class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.string :name, null: false
      t.string :path
      t.string :referrer_host
      t.string :client, null: false, default: "other"
      t.string :visitor
      t.string :service_slug
      t.jsonb :properties, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :events, [ :name, :created_at ]
    add_index :events, :created_at
  end
end
