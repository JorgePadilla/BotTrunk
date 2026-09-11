# frozen_string_literal: true

# One row per rate refresh: where it came from, the value, and the date the
# source says it applies to. The newest row is what pricing uses when the
# hourly refresh fails; the history is for the admin page.
class CreateExchangeRates < ActiveRecord::Migration[8.1]
  def change
    create_table :exchange_rates do |t|
      t.string :pair, null: false, default: "USD/HNL"
      t.string :source, null: false
      t.decimal :rate, precision: 10, scale: 4, null: false
      t.date :as_of, null: false
      t.datetime :fetched_at, null: false
    end

    add_index :exchange_rates, [ :pair, :fetched_at ]
  end
end
