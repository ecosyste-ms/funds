class AddTotalDownloadsToProjects < ActiveRecord::Migration[8.0]
  def change
    add_column :projects, :total_downloads, :integer, default: 0
    add_column :projects, :total_dependent_repos, :integer, default: 0
    add_column :projects, :total_dependent_packages, :integer, default: 0
  end
end
