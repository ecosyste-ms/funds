class AddDeletedAtToInvitations < ActiveRecord::Migration[8.0]
  def change
    add_column :invitations, :deleted_at, :datetime
  end
end
