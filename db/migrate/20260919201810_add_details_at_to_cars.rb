class AddDetailsAtToCars < ActiveRecord::Migration[8.1]
  def change
    # When we last read this car's own page. Asking again costs a request and
    # usually answers the same thing, so it is worth remembering that we asked.
    add_column :cars, :details_at, :datetime
    add_index :cars, :details_at
  end
end
