class AddAcceptedAtToInvitations < ActiveRecord::Migration[8.0]
  def change
    add_column :invitations, :accepted_at, :datetime
    add_column :invitations, :rejected_at, :datetime
  end
end
