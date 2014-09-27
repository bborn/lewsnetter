class CreateSmailerTables < ActiveRecord::Migration
  def self.up
    create_table "mailing_lists", :force => true do |t|
      t.string   "name"
      t.datetime "created_at"
      t.datetime "updated_at"
    end

    create_table "mail_campaigns", :force => true do |t|
      t.integer  "mailing_list_id"
      t.string   "from"
      t.string   "subject"
      t.text     "body_html"
      t.integer  "unsubscribe_methods"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.text     "body_text"
      t.integer  "sent_mails_count",    :default => 0, :null => false
      t.integer  "opened_mails_count",  :default => 0, :null => false
    end
    add_index "mail_campaigns", ["mailing_list_id"], :name => "index_mail_campaigns_on_mailing_list_id"

    create_table "queued_mails", :force => true do |t|
      t.integer  "mail_campaign_id"
      t.string   "to"
      t.integer  "retries",          :default => 0, :null => false
      t.datetime "last_retry_at"
      t.string   "last_error"
      t.boolean  "locked",           :default => false, :null => false
      t.datetime "locked_at"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.string   "key"
    end
    add_index "queued_mails", ["mail_campaign_id", "to"], :name => "index_queued_mails_on_mail_campain_id_and_to", :unique => true
    add_index "queued_mails", ["retries", "locked"], :name => "index_queued_mails_on_retries_and_locked"
    add_index "queued_mails", ["locked", "retries", "id"], :name => "index_queued_mails_on_locked_retries_and_id"
    add_index "queued_mails", ["locked", "locked_at"], :name => "index_queued_mails_on_locked_and_locked_at"

    create_table "mail_campaign_attachments", :force => true do |t|
      t.integer "mail_campaign_id", :null => false
      t.string "filename", :null => false
      t.string "path", :limit => 2048
      t.datetime "created_at"
      t.datetime "updated_at"
    end
    add_index "mail_campaign_attachments", "mail_campaign_id"

    create_table "finished_mails", :force => true do |t|
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
      t.boolean  "opened",           :default => false, :null => false
      t.string   "key"
    end
    add_index "finished_mails", ["key"], :name => "index_finished_mails_on_key", :unique => true
    add_index "finished_mails", ["mail_campaign_id", "status"], :name => "index_finished_mails_on_mail_campain_id_and_status"
    add_index "finished_mails", ["to", "mail_campaign_id"], :name => "index_finished_mails_on_to_and_mail_campaign_id"

    create_table "mail_keys", :force => true do |t|
      t.string   "email"
      t.string   "key"
      t.datetime "created_at"
      t.datetime "updated_at"
    end
    add_index "mail_keys", ["email"], :name => "index_mail_keys_on_email", :unique => true
    add_index "mail_keys", ["key"], :name => "index_mail_keys_on_key", :unique => true

    create_table "smailer_properties", :force => true do |t|
      t.string   "name"
      t.text     "value"
      t.datetime "created_at"
      t.datetime "updated_at"
      t.string   "notes"
    end
    add_index "smailer_properties", ["name"], :name => "index_smailer_properties_on_name", :unique => true
  end

  def self.down
    drop_table :smailer_properties
    drop_table :mail_keys
    drop_table :finished_mails
    drop_table :queued_mails
    drop_table :mail_campaign_attachments
    drop_table :mail_campaigns
    drop_table :mailing_lists
  end
end