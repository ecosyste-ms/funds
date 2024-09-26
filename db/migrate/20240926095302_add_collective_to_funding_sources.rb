class AddCollectiveToFundingSources < ActiveRecord::Migration[7.2]
  def change
    add_column :funding_sources, :collective, :json, default: {}
    add_column :funding_sources, :last_synced_at, :datetime
  end
end
