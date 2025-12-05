# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_03_19_102622) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_stat_statements"

  create_table "allocations", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "fund_id"
    t.integer "funded_projects_count"
    t.json "max_values"
    t.integer "minimum_allocation_cents"
    t.integer "month"
    t.string "slug"
    t.integer "total_cents"
    t.datetime "updated_at", null: false
    t.json "weights"
    t.integer "year"
    t.index ["fund_id"], name: "index_allocations_on_fund_id"
  end

  create_table "funding_sources", force: :cascade do |t|
    t.json "collective", default: {}
    t.datetime "created_at", null: false
    t.integer "current_balance_cents"
    t.json "github_sponsors", default: {}
    t.datetime "last_synced_at"
    t.string "platform"
    t.datetime "updated_at", null: false
    t.string "url"
  end

  create_table "funds", force: :cascade do |t|
    t.float "balance", default: 0.0
    t.datetime "created_at", null: false
    t.string "description"
    t.string "excluded_topics", default: [], array: true
    t.boolean "featured", default: false
    t.string "github_url"
    t.datetime "last_synced_at"
    t.integer "minimum_for_allocation_cents"
    t.string "name"
    t.string "oc_webhook_id"
    t.json "opencollective_project", default: {}
    t.string "opencollective_project_id"
    t.integer "possible_projects_count", default: 0
    t.string "primary_topic"
    t.integer "projects_count", default: 0
    t.string "registry_name"
    t.string "secondary_topics", default: [], array: true
    t.string "slug"
    t.string "topic_logo_url"
    t.integer "transactions_count", default: 0
    t.datetime "updated_at", null: false
    t.string "wikipedia_url"
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.json "data"
    t.datetime "deleted_at"
    t.string "email", null: false
    t.string "member_invitation_id"
    t.integer "project_allocation_id", null: false
    t.datetime "rejected_at"
    t.string "status"
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["project_allocation_id"], name: "index_invitations_on_project_allocation_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "project_allocations", force: :cascade do |t|
    t.integer "allocation_id"
    t.integer "amount_cents"
    t.datetime "created_at", null: false
    t.integer "fund_id"
    t.integer "funding_source_id"
    t.datetime "paid_at"
    t.integer "project_id"
    t.float "score"
    t.datetime "updated_at", null: false
    t.index ["allocation_id"], name: "index_project_allocations_on_allocation_id"
    t.index ["fund_id"], name: "index_project_allocations_on_fund_id"
    t.index ["funding_source_id"], name: "index_project_allocations_on_funding_source_id"
    t.index ["project_id"], name: "index_project_allocations_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.json "commits", default: {}
    t.datetime "created_at", null: false
    t.json "dependencies", default: []
    t.string "description"
    t.json "events", default: {}
    t.boolean "funding_rejected", default: false
    t.integer "funding_source_id"
    t.json "issue_stats", default: {}
    t.string "keywords", default: [], array: true
    t.datetime "last_synced_at"
    t.string "licenses", default: [], array: true
    t.string "name"
    t.json "owner", default: {}
    t.json "packages", default: []
    t.text "readme"
    t.string "registry_names", default: [], array: true
    t.json "repository", default: {}
    t.bigint "total_dependent_packages", default: 0
    t.bigint "total_dependent_repos", default: 0
    t.bigint "total_downloads", default: 0
    t.datetime "updated_at", null: false
    t.citext "url"
    t.index ["funding_source_id"], name: "index_projects_on_funding_source_id"
    t.index ["url"], name: "index_projects_on_url", unique: true
  end

  create_table "proxy_collectives", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "image_url"
    t.string "legacy_id"
    t.string "name"
    t.json "payout_method"
    t.string "slug"
    t.string "tags", default: [], array: true
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.string "website"
  end

  create_table "transactions", force: :cascade do |t|
    t.string "account"
    t.string "account_image_url"
    t.string "account_name"
    t.float "amount"
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "description"
    t.integer "fund_id"
    t.integer "legacy_id"
    t.float "net_amount"
    t.jsonb "order", default: {}
    t.string "transaction_expense_type"
    t.string "transaction_kind"
    t.string "transaction_type"
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.index ["fund_id"], name: "index_transactions_on_fund_id"
    t.index ["uuid"], name: "index_transactions_on_uuid", unique: true
  end
end
