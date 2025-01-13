class AddPaidAtToProjectAllocations < ActiveRecord::Migration[8.0]
  def change
    add_column :project_allocations, :paid_at, :datetime
  end
end
