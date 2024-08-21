class CreateProjects < ActiveRecord::Migration[7.2]
  def change
    enable_extension :citext

    create_table :projects do |t|
      t.citext :url
      t.string :name
      t.string :description
      t.json :repository, default: {}
      t.json :packages, default: []
      t.json :commits, default: {}
      t.json :events, default: {}
      t.string :keywords, array: true, default: []
      t.datetime :last_synced_at
      t.json :issue_stats, default: {}
      t.json :dependencies, default: []
      t.json :owner, default: {}
      t.text :readme

      t.timestamps
    end
  end
end
