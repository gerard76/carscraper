class AddBargainEurToCars < ActiveRecord::Migration[8.1]
  def change
    add_column :cars, :bargain_eur, :integer

    add_index :cars, :bargain_eur
  end
end
