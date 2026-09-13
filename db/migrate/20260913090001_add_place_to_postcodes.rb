class AddPlaceToPostcodes < ActiveRecord::Migration[8.1]
  def change
    add_column :postcodes, :place_key, :string

    add_index :postcodes, [:country, :place_key]
  end
end
