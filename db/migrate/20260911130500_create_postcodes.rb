class CreatePostcodes < ActiveRecord::Migration[8.1]
  def change
    create_table :postcodes do |t|
      t.string :country, null: false
      t.string :code,    null: false
      t.float  :latitude,  null: false
      t.float  :longitude, null: false
    end

    add_index :postcodes, [:country, :code], unique: true
  end
end
