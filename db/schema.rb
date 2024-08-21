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

ActiveRecord::Schema[7.2].define(version: 2024_08_21_135713) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "plpgsql"

  create_table "funds", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "primary_topic"
    t.string "secondary_topics", default: [], array: true
    t.string "description"
    t.string "wikipedia_url"
    t.string "github_url"
    t.integer "projects_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "projects", force: :cascade do |t|
    t.citext "url"
    t.string "name"
    t.string "description"
    t.json "repository", default: {}
    t.json "packages", default: []
    t.json "commits", default: {}
    t.json "events", default: {}
    t.string "keywords", default: [], array: true
    t.datetime "last_synced_at"
    t.json "issue_stats", default: {}
    t.json "dependencies", default: []
    t.json "owner", default: {}
    t.text "readme"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
