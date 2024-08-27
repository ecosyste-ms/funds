class CreateFundingSources < ActiveRecord::Migration[7.2]
  def change
    create_table :funding_sources do |t|
      t.integer :project_id
      t.string :url
      t.string :platform
      t.integer :current_balance_cents

      t.timestamps
    end
  end
end
