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

ActiveRecord::Schema[8.1].define(version: 2026_09_10_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "calls", force: :cascade do |t|
    t.bigint "amount", null: false
    t.string "asset", null: false
    t.bigint "commission", null: false
    t.datetime "created_at", null: false
    t.string "network", null: false
    t.string "pay_to", null: false
    t.string "payer_address"
    t.bigint "seller_amount", null: false
    t.string "service_slug", null: false
    t.string "status", default: "settled", null: false
    t.string "transaction_id"
    t.datetime "updated_at", null: false
    t.integer "upstream_latency_ms"
    t.integer "upstream_status"
    t.index ["service_slug"], name: "index_calls_on_service_slug"
    t.index ["transaction_id"], name: "index_calls_on_transaction_id", unique: true, where: "(transaction_id IS NOT NULL)"
  end

  create_table "seller_inquiries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.text "notes"
    t.bigint "price_atomic", null: false
    t.string "service_name", null: false
    t.datetime "updated_at", null: false
    t.string "upstream_url", null: false
    t.index ["email"], name: "index_seller_inquiries_on_email"
  end
end
