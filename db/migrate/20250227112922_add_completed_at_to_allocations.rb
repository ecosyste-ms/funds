class AddCompletedAtToAllocations < ActiveRecord::Migration[8.0]
  def change
    add_column :allocations, :completed_at, :datetime
  end
end
