class ChangeTotalsToBigints < ActiveRecord::Migration[8.0]
  def change
    change_column :projects, :total_downloads, :bigint
    change_column :projects, :total_dependent_repos, :bigint
    change_column :projects, :total_dependent_packages, :bigint
  end
end
