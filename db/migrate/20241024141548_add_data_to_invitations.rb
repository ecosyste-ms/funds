class AddDataToInvitations < ActiveRecord::Migration[7.2]
  def change
    add_column :invitations, :data, :json
  end
end
