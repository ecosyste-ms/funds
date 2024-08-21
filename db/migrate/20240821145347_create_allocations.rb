class CreateAllocations < ActiveRecord::Migration[7.2]
  def change
    create_table :allocations do |t|
      t.integer :fund_id
      t.integer :year
      t.integer :month
      t.integer :total_cents
      t.integer :funded_projects_count

      t.timestamps
    end
  end
end
