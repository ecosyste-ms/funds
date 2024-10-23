class AddOcWebhookIdToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :oc_webhook_id, :string
  end
end
