class CreateTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :transactions do |t|
      t.integer :fund_id, index: true
      t.string :uuid
      t.float :amount
      t.float :net_amount
      t.string :transaction_type
      t.string :currency
      t.string :account
      t.string :description
      t.string :transaction_kind
      t.string :transaction_expense_type

      t.timestamps
    end

    add_index :transactions, :uuid, unique: true
  end
end
