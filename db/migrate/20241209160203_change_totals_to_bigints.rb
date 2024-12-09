class ChangeTotalsToBigints < ActiveRecord::Migration[8.0]
  def change
    remove_column :projects, :total_downloads, :integer
    add_column :projects, :total_downloads, :bigint, default: 0

    remove_column :projects, :total_dependent_repos, :integer
    add_column :projects, :total_dependent_repos, :bigint, default: 0

    remove_column :projects, :total_dependent_packages, :integer
    add_column :projects, :total_dependent_packages, :bigint, default: 0
  end
end