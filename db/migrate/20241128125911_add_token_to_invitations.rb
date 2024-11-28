class AddTokenToInvitations < ActiveRecord::Migration[8.0]
  def change
    add_column :invitations, :token, :string
  end
end
