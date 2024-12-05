class CreateCars < ActiveRecord::Migration[7.1]
  def change
    create_table :cars do |t|
      t.references :model, null: false, foreign_key: true
      t.string :version
      t.integer :km
      t.integer :eur
      t.date :year
      t.string :url
      t.string :country
      t.boolean :visible, default: true
      t.string :currency
      t.integer :price
      t.json :data, default: {}

      t.timestamps
    end

    add_index :cars, :url, unique: true
  end
end
