class CreateProjectAllocationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :project_allocation_events do |t|
      t.references :project_allocation, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.references :allocation, null: false, foreign_key: true
      t.references :invitation, foreign_key: true
      t.string :event_type, null: false
      t.string :status
      t.text :message
      t.json :metadata

      t.timestamps
    end

    add_index :project_allocation_events, :event_type
    add_index :project_allocation_events, :status
    add_index :project_allocation_events, :created_at
  end
end
