class AddPayoutMethodToProxyCollectives < ActiveRecord::Migration[8.0]
  def change
    add_column :proxy_collectives, :payout_method, :json
  end
end
