class AddLargePhotoToCars < ActiveRecord::Migration[8.1]
  def change
    add_column :cars, :large_photo, :string
  end
end
