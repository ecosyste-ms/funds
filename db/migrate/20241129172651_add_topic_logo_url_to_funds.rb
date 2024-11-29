class AddTopicLogoUrlToFunds < ActiveRecord::Migration[8.0]
  def change
    add_column :funds, :topic_logo_url, :string
  end
end
