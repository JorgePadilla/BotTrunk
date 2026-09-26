# frozen_string_literal: true

# What things actually cost in Honduras, recorded by a person who went and
# looked. One row per observation, never overwritten: the history is the
# product, and an agent asking "what was coffee in August" deserves an answer.
class CreateLocalPrices < ActiveRecord::Migration[8.1]
  def change
    create_table :local_prices do |t|
      t.string :item, null: false           # coffee-quintal, fuel-diesel, basket-basic…
      t.string :unit, null: false           # quintal, gallon, month
      t.string :city, null: false, default: "Tegucigalpa"
      t.decimal :price_hnl, precision: 12, scale: 2, null: false
      t.string :source, null: false         # how it was learned: "phone, 3 exporters"
      t.date :observed_at, null: false      # the day the person looked, not the day it was typed
      t.text :notes

      t.timestamps
    end

    add_index :local_prices, [ :item, :city, :observed_at ]
    add_index :local_prices, :observed_at
  end
end
