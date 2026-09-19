class AddCorrectionsToCars < ActiveRecord::Migration[8.1]
  def change
    # What you have put right by hand, so the next scrape cannot write the
    # advert's answer back over it.
    add_column :cars, :corrections, :json, default: {}
  end
end
