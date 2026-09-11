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

ActiveRecord::Schema[8.1].define(version: 2026_09_11_130501) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "cars", force: :cascade do |t|
    t.text "comments"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "currency"
    t.json "data", default: {}
    t.integer "distance_km"
    t.integer "eur"
    t.integer "km"
    t.bigint "model_id", null: false
    t.string "postcode"
    t.integer "price"
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "version"
    t.boolean "visible", default: true
    t.date "year"
    t.index ["model_id"], name: "index_cars_on_model_id"
    t.index ["url"], name: "index_cars_on_url", unique: true
  end

  create_table "models", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "exclude_versions"
    t.string "make"
    t.integer "min_seats"
    t.string "model"
    t.datetime "updated_at", null: false
  end

  create_table "postcodes", force: :cascade do |t|
    t.string "code", null: false
    t.string "country", null: false
    t.float "latitude", null: false
    t.float "longitude", null: false
    t.index ["country", "code"], name: "index_postcodes_on_country_and_code", unique: true
  end

  add_foreign_key "cars", "models"
end
