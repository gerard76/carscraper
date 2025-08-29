class AddCommentsToCars < ActiveRecord::Migration[7.1]
  def change
    add_column :cars, :comments, :text
  end
end
