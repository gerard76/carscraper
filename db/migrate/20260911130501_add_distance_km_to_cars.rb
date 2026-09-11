class AddDistanceKmToCars < ActiveRecord::Migration[8.1]
  def change
    add_column :cars, :distance_km, :integer
  end
end
