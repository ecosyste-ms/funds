class AddPossibleProjectsCountToFunds < ActiveRecord::Migration[8.0]
  def change
    add_column :funds, :possible_projects_count, :integer, default: 0
  end
end
