class AddPostcodeToCars < ActiveRecord::Migration[8.1]
  def change
    add_column :cars, :postcode, :string
  end
end
