class AddStatsToFunds < ActiveRecord::Migration[8.1]
  def change
    add_column :funds, :total_donation_amount_cents, :bigint, default: 0
    add_column :funds, :total_donors_count, :integer, default: 0
    add_column :funds, :completed_allocations_total_cents, :bigint, default: 0
  end
end
