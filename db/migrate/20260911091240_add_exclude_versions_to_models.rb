class AddExcludeVersionsToModels < ActiveRecord::Migration[8.1]
  def change
    add_column :models, :exclude_versions, :string
  end
end
