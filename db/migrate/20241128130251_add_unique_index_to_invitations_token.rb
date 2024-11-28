class AddUniqueIndexToInvitationsToken < ActiveRecord::Migration[8.0]
  def change
    add_index :invitations, :token, unique: true
  end
end
