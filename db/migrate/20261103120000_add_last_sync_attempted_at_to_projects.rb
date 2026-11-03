class AddLastSyncAttemptedAtToProjects < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :projects, :last_sync_attempted_at, :datetime
    add_index :projects, 'COALESCE(last_sync_attempted_at, last_synced_at) ASC NULLS FIRST, id',
      name: 'index_projects_on_sync_attempt_order', algorithm: :concurrently
  end
end
