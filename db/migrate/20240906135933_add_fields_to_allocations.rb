class AddFieldsToAllocations < ActiveRecord::Migration[7.2]
  def change
    add_column :allocations, :max_values, :json
    add_column :allocations, :weights, :json
    add_column :allocations, :minimum_allocation_cents, :integer
  end
end
