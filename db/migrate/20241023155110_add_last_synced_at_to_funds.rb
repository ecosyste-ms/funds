class AddLastSyncedAtToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :last_synced_at, :datetime
  end
end
