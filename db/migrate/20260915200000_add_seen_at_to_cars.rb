class AddSeenAtToCars < ActiveRecord::Migration[8.1]
  def change
    add_column :cars, :seen_at, :datetime

    add_index :cars, :seen_at
  end
end
