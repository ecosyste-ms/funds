class AddIndexes < ActiveRecord::Migration[7.2]
  def change
    add_index :allocations, :fund_id
    add_index :project_allocations, :allocation_id
    add_index :project_allocations, :project_id
    add_index :project_allocations, :fund_id
    add_index :project_allocations, :funding_source_id
    add_index :projects, :url, unique: true
    add_index :projects, :funding_source_id
  end
end
