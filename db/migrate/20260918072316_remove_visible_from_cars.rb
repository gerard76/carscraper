class RemoveVisibleFromCars < ActiveRecord::Migration[8.1]
  # hidden_by has said the same thing all along -- either nil or the reason a
  # car is out of sight -- and nothing has read this column since the deploy
  # before this one. It goes on its own, because a column that disappears
  # while the old job container is halfway through a scrape takes the scrape
  # with it: ALLOW_DESTRUCTIVE_MIGRATION=1 bin/kamal deploy, between rounds.
  def change
    remove_column :cars, :visible, :boolean, default: true
  end
end
