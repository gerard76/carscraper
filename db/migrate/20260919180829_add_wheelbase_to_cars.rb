class AddWheelbaseToCars < ActiveRecord::Migration[8.1]
  def up
    add_column :cars, :wheelbase, :string
    add_index :cars, :wheelbase

    # The titles are already here, so the column can be filled from them at
    # once rather than waiting for every car to be scraped again.
    Car.reset_column_information
    Car.find_each { |car| car.update_columns(wheelbase: Car.wheelbase_in(car.version)) }
  end

  def down
    remove_column :cars, :wheelbase
  end
end
