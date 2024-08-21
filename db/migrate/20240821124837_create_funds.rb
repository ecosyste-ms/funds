class CreateFunds < ActiveRecord::Migration[7.2]
  def change
    create_table :funds do |t|
      t.string :name
      t.string :slug
      t.string :primary_topic
      t.string :secondary_topics, array: true, default: []
      t.string :description
      t.string :wikipedia_url
      t.string :github_url
      t.integer :projects_count, default: 0

      t.timestamps
    end
  end
end
