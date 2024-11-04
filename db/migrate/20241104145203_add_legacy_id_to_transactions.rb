class AddLegacyIdToTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :transactions, :legacy_id, :integer
  end
end
