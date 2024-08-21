class CreateProjectAllocations < ActiveRecord::Migration[7.2]
  def change
    create_table :project_allocations do |t|
      t.integer :allocation_id
      t.integer :project_id
      t.integer :fund_id
      t.integer :amount_cents
      t.float :score

      t.timestamps
    end
  end
end
