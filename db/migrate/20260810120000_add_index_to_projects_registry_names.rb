class AddIndexToProjectsRegistryNames < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :projects, :registry_names, using: :gin, algorithm: :concurrently
  end
end
