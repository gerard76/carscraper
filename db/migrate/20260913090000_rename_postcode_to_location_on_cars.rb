class RenamePostcodeToLocationOnCars < ActiveRecord::Migration[8.1]
  def change
    # Half the sites name a postcode, the other half a town. The column holds
    # whichever one the listing came with.
    rename_column :cars, :postcode, :location
  end
end
