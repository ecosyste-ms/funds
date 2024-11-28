class AddFundingRejectedToProjects < ActiveRecord::Migration[8.0]
  def change
    add_column :projects, :funding_rejected, :boolean, default: false
  end
end
