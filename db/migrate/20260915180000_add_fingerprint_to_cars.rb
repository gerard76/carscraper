class AddFingerprintToCars < ActiveRecord::Migration[8.1]
  def change
    add_column :cars, :fingerprint, :string

    add_index :cars, :fingerprint
  end
end
