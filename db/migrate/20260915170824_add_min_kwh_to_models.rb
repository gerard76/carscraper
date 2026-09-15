class AddMinKwhToModels < ActiveRecord::Migration[8.1]
  def change
    add_column :models, :min_kwh, :integer
  end
end
