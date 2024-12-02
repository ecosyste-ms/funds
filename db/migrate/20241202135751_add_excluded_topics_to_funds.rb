class AddExcludedTopicsToFunds < ActiveRecord::Migration[8.0]
  def change
    add_column :funds, :excluded_topics, :string, array: true, default: []
  end
end
