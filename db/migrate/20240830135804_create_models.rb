class CreateModels < ActiveRecord::Migration[7.1]
  def change
    create_table :models do |t|
      t.string :make
      t.string :model
      t.timestamps
    end
  end
end
