class AddConfirmedProjectContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :confirmed_contact_email, :string
    add_column :projects, :confirmed_contact_recipient, :string
    change_column_null :invitations, :email, true
  end
end
