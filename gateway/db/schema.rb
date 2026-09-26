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

ActiveRecord::Schema[8.1].define(version: 2026_09_26_010000) do
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

  create_table "deposit_orders", force: :cascade do |t|
    t.string "account_number", null: false
    t.integer "amount_hnl", null: false
    t.string "bank", default: "BAC Credomatic", null: false
    t.string "beneficiary_name", null: false
    t.bigint "call_id"
    t.string "concept"
    t.string "contact_email"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.integer "fee_bps", null: false
    t.text "notes"
    t.bigint "price_atomic", null: false
    t.decimal "rate_hnl_per_usd", precision: 10, scale: 4, null: false
    t.string "receipt_reference"
    t.string "refund_transaction_id"
    t.datetime "refunded_at"
    t.string "service_slug", null: false
    t.string "status", default: "awaiting_payment", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["account_number", "created_at"], name: "index_deposit_orders_on_account_number_and_created_at"
    t.index ["call_id"], name: "index_deposit_orders_on_call_id"
    t.index ["status", "created_at"], name: "index_deposit_orders_on_status_and_created_at"
    t.index ["token"], name: "index_deposit_orders_on_token", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.string "city"
    t.string "client", default: "other", null: false
    t.string "country"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "path"
    t.jsonb "properties", default: {}, null: false
    t.string "referrer_host"
    t.string "service_slug"
    t.string "visitor"
    t.index ["country", "created_at"], name: "index_events_on_country_and_created_at"
    t.index ["created_at"], name: "index_events_on_created_at"
    t.index ["name", "created_at"], name: "index_events_on_name_and_created_at"
  end

  create_table "exchange_rates", force: :cascade do |t|
    t.date "as_of", null: false
    t.datetime "fetched_at", null: false
    t.string "pair", default: "USD/HNL", null: false
    t.decimal "rate", precision: 10, scale: 4, null: false
    t.string "source", null: false
    t.index ["pair", "fetched_at"], name: "index_exchange_rates_on_pair_and_fetched_at"
  end

  create_table "local_prices", force: :cascade do |t|
    t.string "city", default: "Tegucigalpa", null: false
    t.datetime "created_at", null: false
    t.string "item", null: false
    t.text "notes"
    t.date "observed_at", null: false
    t.decimal "price_hnl", precision: 12, scale: 2, null: false
    t.string "source", null: false
    t.string "unit", null: false
    t.datetime "updated_at", null: false
    t.index ["item", "city", "observed_at"], name: "index_local_prices_on_item_and_city_and_observed_at"
    t.index ["observed_at"], name: "index_local_prices_on_observed_at"
  end

  create_table "seller_inquiries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.text "notes"
    t.bigint "price_atomic", null: false
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.string "service_name", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.string "upstream_url", null: false
    t.index ["email"], name: "index_seller_inquiries_on_email"
    t.index ["status", "created_at"], name: "index_seller_inquiries_on_status_and_created_at"
  end

  create_table "service_requests", force: :cascade do |t|
    t.bigint "budget_atomic"
    t.datetime "created_at", null: false
    t.text "details", null: false
    t.string "email", null: false
    t.text "review_notes"
    t.datetime "reviewed_at"
    t.string "service_slug"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["service_slug"], name: "index_service_requests_on_service_slug"
    t.index ["status", "created_at"], name: "index_service_requests_on_status_and_created_at"
  end

  create_table "work_orders", force: :cascade do |t|
    t.text "brief", null: false
    t.bigint "call_id"
    t.string "contact_email"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.text "notes"
    t.jsonb "params", default: {}, null: false
    t.bigint "price_atomic", null: false
    t.string "refund_transaction_id"
    t.datetime "refunded_at"
    t.jsonb "result", default: {}, null: false
    t.string "service_slug", null: false
    t.string "status", default: "awaiting_payment", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["call_id"], name: "index_work_orders_on_call_id"
    t.index ["status", "created_at"], name: "index_work_orders_on_status_and_created_at"
    t.index ["token"], name: "index_work_orders_on_token", unique: true
  end

  add_foreign_key "deposit_orders", "calls"
end
