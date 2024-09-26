class AddMinimumForAllocationCentsToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :minimum_for_allocation_cents, :integer
  end
end
