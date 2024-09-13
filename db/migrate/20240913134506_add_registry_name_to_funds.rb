class AddRegistryNameToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :registry_name, :string
  end
end
