class AddSlugToAllocations < ActiveRecord::Migration[8.0]
  def change
    add_column :allocations, :slug, :string
  end
end
