class AddHiddenByToCars < ActiveRecord::Migration[8.1]
  def change
    add_column :cars, :hidden_by, :string

    add_index :cars, :hidden_by
  end
end
