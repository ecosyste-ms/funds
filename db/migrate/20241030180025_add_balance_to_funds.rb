class AddBalanceToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :balance, :float, default: 0.0
  end
end
