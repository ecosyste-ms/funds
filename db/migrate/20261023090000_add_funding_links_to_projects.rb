class AddFundingLinksToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :funding_links, :json, default: []
  end
end
