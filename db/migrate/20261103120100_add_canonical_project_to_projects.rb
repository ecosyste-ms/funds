class AddCanonicalProjectToProjects < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_reference :projects, :canonical_project, index: { algorithm: :concurrently },
      foreign_key: { to_table: :projects, validate: false }
    reversible do |direction|
      direction.up { validate_foreign_key :projects, :projects, column: :canonical_project_id }
    end
  end
end
