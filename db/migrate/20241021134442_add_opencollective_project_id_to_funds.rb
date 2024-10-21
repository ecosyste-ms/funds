class AddOpencollectiveProjectIdToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :opencollective_project_id, :string
    add_column :funds, :opencollective_project, :json, default: {}
  end
end
