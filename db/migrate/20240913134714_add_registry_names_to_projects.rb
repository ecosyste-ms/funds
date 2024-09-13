class AddRegistryNamesToProjects < ActiveRecord::Migration[7.2]
  def change
    add_column :projects, :registry_names, :string, array: true, default: []
  end
end
