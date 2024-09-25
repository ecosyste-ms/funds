class AddLicensesToProjects < ActiveRecord::Migration[7.2]
  def change
    add_column :projects, :licenses, :string, array: true, default: []
  end
end
