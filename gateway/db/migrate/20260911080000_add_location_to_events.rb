# frozen_string_literal: true

# Coarse location of the visitor, derived from the IP at tracking time
# (Analytics::Geolocate). The IP itself is still never stored.
class AddLocationToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :country, :string # ISO 3166-1 alpha-2, e.g. "HN"
    add_column :events, :city, :string    # "San Pedro Sula, Cortés"
    add_index :events, [ :country, :created_at ]
  end
end
