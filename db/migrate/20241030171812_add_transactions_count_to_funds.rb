class AddTransactionsCountToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :transactions_count, :integer, default: 0
  end
end
