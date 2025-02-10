class AddGithubSponsorsToFundingSources < ActiveRecord::Migration[8.0]
  def change
    add_column :funding_sources, :github_sponsors, :json, default: {}
  end
end
