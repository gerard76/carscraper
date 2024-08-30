class CreateCars < ActiveRecord::Migration[7.1]
  def change
    create_table :cars do |t|
      t.string :make
      t.string :version
      t.integer :eur
      t.integer :km
      t.date :year
      t.string :url
      t.string :country
      t.string :crawler
      t.boolean :visible, default: true
      t.string :currency
      t.integer :price
      t.json :data, default: {}
      t.string :model
      t.timestamps
    end
  end
end
