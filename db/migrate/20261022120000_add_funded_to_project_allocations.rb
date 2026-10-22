class AddFundedToProjectAllocations < ActiveRecord::Migration[8.1]
  def change
    add_column :project_allocations, :funded, :boolean, default: false, null: false
  end
end
