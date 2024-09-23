class MoveFundingSourceRelation < ActiveRecord::Migration[7.2]
  def change
    remove_column :funding_sources, :project_id, :integer
    add_column :projects, :funding_source_id, :integer
  end
end
