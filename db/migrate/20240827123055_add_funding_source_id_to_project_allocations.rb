class AddFundingSourceIdToProjectAllocations < ActiveRecord::Migration[7.2]
  def change
    add_column :project_allocations, :funding_source_id, :integer
  end
end
