class AddAccountDetailsToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :account_name, :string
    add_column :transactions, :account_image_url, :string
  end
end
