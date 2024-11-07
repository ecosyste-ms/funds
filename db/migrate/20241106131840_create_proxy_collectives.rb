class CreateProxyCollectives < ActiveRecord::Migration[7.2]
  def change
    create_table :proxy_collectives do |t|
      t.string :uuid
      t.string :legacy_id
      t.string :slug
      t.string :name
      t.string :description
      t.string :type
      t.string :tags, array: true, default: []
      t.string :image_url
      t.string :website

      t.timestamps
    end
  end
end
