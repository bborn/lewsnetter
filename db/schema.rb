# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20160503095648) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "authentications", force: true do |t|
    t.integer  "user_id"
    t.string   "provider",      null: false
    t.string   "proid",         null: false
    t.string   "token"
    t.string   "refresh_token"
    t.string   "secret"
    t.datetime "expires_at"
    t.string   "username"
    t.string   "image_url"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "ckeditor_assets", force: true do |t|
    t.string   "data_file_name",               null: false
    t.string   "data_content_type"
    t.integer  "data_file_size"
    t.integer  "assetable_id"
    t.string   "assetable_type",    limit: 30
    t.string   "type",              limit: 30
    t.integer  "width"
    t.integer  "height"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "ckeditor_assets", ["assetable_type", "assetable_id"], name: "idx_ckeditor_assetable", using: :btree
  add_index "ckeditor_assets", ["assetable_type", "type", "assetable_id"], name: "idx_ckeditor_assetable_type", using: :btree

  create_table "finished_mails", force: true do |t|
    t.integer  "mail_campaign_id"
    t.string   "from"
    t.string   "to"
    t.string   "subject"
    t.text     "body_html"
    t.integer  "retries"
    t.datetime "last_retry_at"
    t.string   "last_error"
    t.datetime "sent_at"
    t.integer  "status"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "body_text"
    t.boolean  "opened",           default: false, null: false
    t.string   "key"
    t.integer  "subscription_id"
    t.integer  "mailing_list"
    t.integer  "campaign_id"
    t.datetime "opened_at"
    t.datetime "clicked_at"
    t.datetime "bounced_at"
    t.integer  "bounces_count",    default: 0
    t.datetime "delivered_at"
    t.integer  "complaints_count", default: 0
    t.integer  "opens_count",      default: 0
  end

  add_index "finished_mails", ["key"], name: "index_finished_mails_on_key", unique: true, using: :btree
  add_index "finished_mails", ["mail_campaign_id", "status"], name: "index_finished_mails_on_mail_campain_id_and_status", using: :btree
  add_index "finished_mails", ["to", "mail_campaign_id"], name: "index_finished_mails_on_to_and_mail_campaign_id", using: :btree

  create_table "mail_campaign_attachments", force: true do |t|
    t.integer  "mail_campaign_id",              null: false
    t.string   "filename",                      null: false
    t.string   "path",             limit: 2048
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "mail_campaign_attachments", ["mail_campaign_id"], name: "index_mail_campaign_attachments_on_mail_campaign_id", using: :btree

  create_table "mail_campaigns", force: true do |t|
    t.integer  "mailing_list_id"
    t.string   "from"
    t.string   "subject"
    t.text     "body_html"
    t.integer  "unsubscribe_methods"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text     "body_text"
    t.integer  "sent_mails_count",    default: 0, null: false
    t.integer  "opened_mails_count",  default: 0, null: false
    t.string   "aasm_state"
    t.text     "content_json"
    t.integer  "template_id"
  end

  add_index "mail_campaigns", ["mailing_list_id"], name: "index_mail_campaigns_on_mailing_list_id", using: :btree

  create_table "mail_keys", force: true do |t|
    t.string   "email"
    t.string   "key"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "mail_keys", ["email"], name: "index_mail_keys_on_email", unique: true, using: :btree
  add_index "mail_keys", ["key"], name: "index_mail_keys_on_key", unique: true, using: :btree

  create_table "mailing_lists", force: true do |t|
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "feed"
    t.string   "google_analytics_id"
  end

  create_table "mailing_lists_subscriptions", id: false, force: true do |t|
    t.integer "subscription_id"
    t.integer "mailing_list_id"
  end

  create_table "oauth_caches", id: false, force: true do |t|
    t.integer  "authentication_id", null: false
    t.text     "data_json",         null: false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "oauth_caches", ["authentication_id"], name: "index_oauth_caches_on_authentication_id", using: :btree

  create_table "queued_mails", force: true do |t|
    t.integer  "mail_campaign_id"
    t.string   "to"
    t.integer  "retries",          default: 0,     null: false
    t.datetime "last_retry_at"
    t.string   "last_error"
    t.boolean  "locked",           default: false, null: false
    t.datetime "locked_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "key"
  end

  add_index "queued_mails", ["locked", "locked_at"], name: "index_queued_mails_on_locked_and_locked_at", using: :btree
  add_index "queued_mails", ["locked", "retries", "id"], name: "index_queued_mails_on_locked_retries_and_id", using: :btree
  add_index "queued_mails", ["mail_campaign_id", "to"], name: "index_queued_mails_on_mail_campain_id_and_to", unique: true, using: :btree
  add_index "queued_mails", ["retries", "locked"], name: "index_queued_mails_on_retries_and_locked", using: :btree

  create_table "rails_admin_histories", force: true do |t|
    t.text     "message"
    t.string   "username"
    t.integer  "item"
    t.string   "table"
    t.integer  "month",      limit: 2
    t.integer  "year",       limit: 8
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "rails_admin_histories", ["item", "table", "month", "year"], name: "index_rails_admin_histories", using: :btree

  create_table "sender_addresses", force: true do |t|
    t.string   "email"
    t.boolean  "verified"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "smailer_properties", force: true do |t|
    t.string   "name"
    t.text     "value"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "notes"
  end

  add_index "smailer_properties", ["name"], name: "index_smailer_properties_on_name", unique: true, using: :btree

  create_table "subscriptions", force: true do |t|
    t.string   "email"
    t.string   "name"
    t.boolean  "subscribed"
    t.boolean  "confirmed"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "templates", force: true do |t|
    t.string   "name"
    t.text     "html"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "users", force: true do |t|
    t.string   "first_name"
    t.string   "last_name"
    t.string   "image_url"
    t.string   "email",                  default: "", null: false
    t.string   "encrypted_password",     default: "", null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.string   "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string   "unconfirmed_email"
    t.integer  "failed_attempts",        default: 0,  null: false
    t.string   "unlock_token"
    t.datetime "locked_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "is_admin"
    t.boolean  "approved"
  end

end
