class AddOrderToTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :transactions, :order, :jsonb, default: {}
  end
end
