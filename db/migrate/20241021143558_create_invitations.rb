class CreateInvitations < ActiveRecord::Migration[7.2]
  def change
    create_table :invitations do |t|
      t.integer :project_allocation_id, index: true, null: false
      t.string :email, null: false
      t.string :status
      t.string :member_invitation_id

      t.timestamps
    end
  end
end
