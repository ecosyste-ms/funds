class AddIndexToProjectAllocationsFunded < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :project_allocations, [:fund_id, :funded], algorithm: :concurrently
  end
end
