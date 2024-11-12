class AddFeaturedToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :featured, :boolean, default: false
  end
end
