class AddTermsAcceptedAtToSellers < ActiveRecord::Migration[8.1]
  def change
    add_column :sellers, :terms_accepted_at, :datetime
    add_column :sellers, :terms_version, :string
  end
end
