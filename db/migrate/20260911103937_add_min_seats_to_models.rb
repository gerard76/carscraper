class AddMinSeatsToModels < ActiveRecord::Migration[8.1]
  def change
    add_column :models, :min_seats, :integer
  end
end
