class DropTypeFromProxyCollectives < ActiveRecord::Migration[7.2]
  def change
    remove_column :proxy_collectives, :type, :string
  end
end
