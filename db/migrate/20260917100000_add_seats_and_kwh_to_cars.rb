class AddSeatsAndKwhToCars < ActiveRecord::Migration[8.1]
  def change
    add_column :cars, :seats, :integer
    add_column :cars, :kwh, :integer

    add_index :cars, :seats
    add_index :cars, :kwh
  end
end
