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

ActiveRecord::Schema[8.1].define(version: 2026_05_15_195400) do
  create_table "account_onboarding_invitation_lists", force: :cascade do |t|
    t.integer "team_id", null: false
    t.json "invitations"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_account_onboarding_invitation_lists_on_team_id"
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.integer "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.integer "record_id", null: false
    t.integer "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "addressable_type", null: false
    t.integer "addressable_id", null: false
    t.string "address_one"
    t.string "address_two"
    t.string "city"
    t.integer "region_id"
    t.string "region_name"
    t.integer "country_id"
    t.string "postal_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["addressable_type", "addressable_id"], name: "index_addresses_on_addressable"
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "team_id", null: false
    t.integer "email_template_id"
    t.integer "segment_id"
    t.integer "sender_address_id"
    t.string "subject"
    t.string "preheader"
    t.text "body_mjml"
    t.text "body_html"
    t.string "status", default: "draft", null: false
    t.datetime "scheduled_for"
    t.datetime "sent_at"
    t.json "stats", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body_markdown"
    t.index ["email_template_id"], name: "index_campaigns_on_email_template_id"
    t.index ["segment_id"], name: "index_campaigns_on_segment_id"
    t.index ["sender_address_id"], name: "index_campaigns_on_sender_address_id"
    t.index ["team_id", "scheduled_for"], name: "index_campaigns_on_team_id_and_scheduled_for"
    t.index ["team_id", "status"], name: "index_campaigns_on_team_id_and_status"
    t.index ["team_id"], name: "index_campaigns_on_team_id"
  end

  create_table "chats", force: :cascade do |t|
    t.integer "team_id", null: false
    t.integer "user_id", null: false
    t.string "title"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "model_id"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["team_id", "user_id"], name: "index_chats_on_team_id_and_user_id"
    t.index ["team_id"], name: "index_chats_on_team_id"
    t.index ["user_id"], name: "index_chats_on_user_id"
  end

  create_table "companies", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "name", null: false
    t.string "external_id"
    t.string "intercom_id"
    t.json "custom_attributes", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "external_id"], name: "index_companies_on_team_id_and_external_id", unique: true, where: "external_id IS NOT NULL"
    t.index ["team_id", "intercom_id"], name: "index_companies_on_team_id_and_intercom_id", unique: true, where: "intercom_id IS NOT NULL"
    t.index ["team_id"], name: "index_companies_on_team_id"
  end

  create_table "email_templates", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "name", null: false
    t.text "mjml_body"
    t.text "rendered_html"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "name"], name: "index_email_templates_on_team_id_and_name"
    t.index ["team_id"], name: "index_email_templates_on_team_id"
  end

  create_table "events", force: :cascade do |t|
    t.integer "team_id", null: false
    t.integer "subscriber_id", null: false
    t.string "name", null: false
    t.datetime "occurred_at", null: false
    t.json "properties", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscriber_id", "name"], name: "index_events_on_subscriber_id_and_name"
    t.index ["subscriber_id"], name: "index_events_on_subscriber_id"
    t.index ["team_id", "name"], name: "index_events_on_team_id_and_name"
    t.index ["team_id", "occurred_at"], name: "index_events_on_team_id_and_occurred_at"
    t.index ["team_id"], name: "index_events_on_team_id"
  end

  create_table "integrations_stripe_installations", force: :cascade do |t|
    t.integer "team_id", null: false
    t.integer "oauth_stripe_account_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["oauth_stripe_account_id"], name: "index_stripe_installations_on_stripe_account_id"
    t.index ["team_id"], name: "index_integrations_stripe_installations_on_team_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.string "email"
    t.string "uuid"
    t.integer "from_membership_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "team_id"
    t.integer "invitation_list_id"
    t.index ["invitation_list_id"], name: "index_invitations_on_invitation_list_id"
    t.index ["team_id"], name: "index_invitations_on_team_id"
  end

  create_table "mailkick_subscriptions", force: :cascade do |t|
    t.string "subscriber_type"
    t.integer "subscriber_id"
    t.string "list"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscriber_type", "subscriber_id", "list"], name: "index_mailkick_subscriptions_on_subscriber_and_list", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "user_id"
    t.integer "team_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "invitation_id"
    t.string "user_first_name"
    t.string "user_last_name"
    t.string "user_profile_photo_id"
    t.string "user_email"
    t.integer "added_by_id"
    t.integer "platform_agent_of_id"
    t.json "role_ids", default: []
    t.boolean "platform_agent", default: false
    t.index ["added_by_id"], name: "index_memberships_on_added_by_id"
    t.index ["invitation_id"], name: "index_memberships_on_invitation_id"
    t.index ["platform_agent_of_id"], name: "index_memberships_on_platform_agent_of_id"
    t.index ["team_id"], name: "index_memberships_on_team_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.string "role", null: false
    t.text "content"
    t.json "content_raw"
    t.text "thinking_text"
    t.text "thinking_signature"
    t.integer "thinking_tokens"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "cached_tokens"
    t.integer "cache_creation_tokens"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "chat_id", null: false
    t.integer "model_id"
    t.integer "tool_call_id"
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.string "model_id", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "family"
    t.datetime "model_created_at"
    t.integer "context_window"
    t.integer "max_output_tokens"
    t.date "knowledge_cutoff"
    t.json "modalities", default: {}
    t.json "capabilities", default: []
    t.json "pricing", default: {}
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_models_on_family"
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.integer "resource_owner_id", null: false
    t.integer "application_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "revoked_at", precision: nil
    t.string "scopes", default: "", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.integer "resource_owner_id"
    t.integer "application_id", null: false
    t.string "token", null: false
    t.string "refresh_token"
    t.integer "expires_in"
    t.datetime "revoked_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.string "scopes"
    t.string "previous_refresh_token", default: "", null: false
    t.string "description"
    t.datetime "last_used_at"
    t.boolean "provisioned", default: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret", null: false
    t.text "redirect_uri"
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "team_id"
    t.index ["team_id"], name: "index_oauth_applications_on_team_id"
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "oauth_stripe_accounts", force: :cascade do |t|
    t.string "uid"
    t.json "data"
    t.integer "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["uid"], name: "index_oauth_stripe_accounts_on_uid", unique: true
    t.index ["user_id"], name: "index_oauth_stripe_accounts_on_user_id"
  end

  create_table "scaffolding_absolutely_abstract_creative_concepts", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_absolutely_abstract_creative_concepts_on_team_id"
  end

  create_table "scaffolding_completely_concrete_tangible_things", force: :cascade do |t|
    t.integer "absolutely_abstract_creative_concept_id", null: false
    t.string "text_field_value"
    t.string "button_value"
    t.string "cloudinary_image_value"
    t.date "date_field_value"
    t.string "email_field_value"
    t.string "password_field_value"
    t.string "phone_field_value"
    t.string "super_select_value"
    t.text "text_area_value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sort_order"
    t.datetime "date_and_time_field_value", precision: nil
    t.json "multiple_button_values", default: []
    t.json "multiple_super_select_values", default: []
    t.string "color_picker_value"
    t.boolean "boolean_button_value"
    t.string "option_value"
    t.json "multiple_option_values", default: []
    t.boolean "boolean_checkbox_value"
    t.index ["absolutely_abstract_creative_concept_id"], name: "index_tangible_things_on_creative_concept_id"
  end

  create_table "scaffolding_completely_concrete_tangible_things_assignments", force: :cascade do |t|
    t.integer "tangible_thing_id"
    t.integer "membership_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["membership_id"], name: "index_tangible_things_assignments_on_membership_id"
    t.index ["tangible_thing_id"], name: "index_tangible_things_assignments_on_tangible_thing_id"
  end

  create_table "segments", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "name", null: false
    t.json "definition", default: {}, null: false
    t.text "natural_language_source"
    t.integer "computed_count"
    t.datetime "last_computed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "name"], name: "index_segments_on_team_id_and_name"
    t.index ["team_id"], name: "index_segments_on_team_id"
  end

  create_table "sender_addresses", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "email"
    t.string "name"
    t.boolean "verified", default: false
    t.string "ses_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_sender_addresses_on_team_id"
  end

  create_table "subscribers", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "external_id"
    t.string "email", null: false
    t.string "name"
    t.json "custom_attributes", default: {}, null: false
    t.boolean "subscribed", default: true, null: false
    t.datetime "unsubscribed_at"
    t.datetime "complained_at"
    t.datetime "bounced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "company_id"
    t.index ["company_id"], name: "index_subscribers_on_company_id"
    t.index ["team_id", "email"], name: "index_subscribers_on_team_id_and_email"
    t.index ["team_id", "external_id"], name: "index_subscribers_on_team_id_and_external_id", unique: true, where: "external_id IS NOT NULL"
    t.index ["team_id", "subscribed"], name: "index_subscribers_on_team_id_and_subscribed"
    t.index ["team_id"], name: "index_subscribers_on_team_id"
  end

  create_table "subscribers_imports", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "status", default: "pending", null: false
    t.integer "total_rows"
    t.integer "processed", default: 0, null: false
    t.integer "created_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.json "errors_log", default: [], null: false
    t.text "notes"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "created_at"], name: "index_subscribers_imports_on_team_id_and_created_at"
    t.index ["team_id"], name: "index_subscribers_imports_on_team_id"
  end

  create_table "team_ses_configurations", force: :cascade do |t|
    t.integer "team_id", null: false
    t.string "encrypted_access_key_id"
    t.string "encrypted_secret_access_key"
    t.string "region", default: "us-east-1", null: false
    t.string "sns_bounce_topic_arn"
    t.string "sns_complaint_topic_arn"
    t.string "status", default: "unconfigured", null: false
    t.integer "quota_max_send_24h"
    t.integer "quota_sent_last_24h"
    t.boolean "sandbox", default: true, null: false
    t.datetime "last_verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "configuration_set_name", default: "lewsnetter-default"
    t.string "unsubscribe_host"
    t.index ["sns_bounce_topic_arn"], name: "index_team_ses_configurations_on_sns_bounce_topic_arn", where: "sns_bounce_topic_arn IS NOT NULL"
    t.index ["sns_complaint_topic_arn"], name: "index_team_ses_configurations_on_sns_complaint_topic_arn", where: "sns_complaint_topic_arn IS NOT NULL"
    t.index ["team_id"], name: "index_team_ses_configurations_on_team_id", unique: true
  end

  create_table "teams", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "being_destroyed"
    t.string "time_zone"
    t.string "locale"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.string "tool_call_id", null: false
    t.string "name", null: false
    t.text "thought_signature"
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "message_id", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "current_team_id"
    t.string "first_name"
    t.string "last_name"
    t.string "time_zone"
    t.datetime "last_seen_at", precision: nil
    t.string "profile_photo_id"
    t.json "ability_cache"
    t.datetime "last_notification_email_sent_at", precision: nil
    t.boolean "former_user", default: false, null: false
    t.string "encrypted_otp_secret"
    t.string "encrypted_otp_secret_iv"
    t.string "encrypted_otp_secret_salt"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login"
    t.json "otp_backup_codes"
    t.string "locale"
    t.integer "platform_agent_of_id"
    t.string "otp_secret"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["platform_agent_of_id"], name: "index_users_on_platform_agent_of_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "webhooks_incoming_bullet_train_webhooks", force: :cascade do |t|
    t.json "data"
    t.datetime "processed_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "verified_at", precision: nil
  end

  create_table "webhooks_incoming_oauth_stripe_account_webhooks", force: :cascade do |t|
    t.json "data"
    t.datetime "processed_at", precision: nil
    t.datetime "verified_at", precision: nil
    t.integer "oauth_stripe_account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["oauth_stripe_account_id"], name: "index_stripe_webhooks_on_stripe_account_id"
  end

  create_table "webhooks_outgoing_deliveries", force: :cascade do |t|
    t.integer "endpoint_id"
    t.integer "event_id"
    t.text "endpoint_url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "delivered_at", precision: nil
    t.index ["endpoint_id", "event_id"], name: "index_webhooks_outgoing_deliveries_on_endpoint_id_and_event_id"
  end

  create_table "webhooks_outgoing_delivery_attempts", force: :cascade do |t|
    t.integer "delivery_id"
    t.integer "response_code"
    t.text "response_body"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "response_message"
    t.text "error_message"
    t.integer "attempt_number"
    t.index ["delivery_id"], name: "index_webhooks_outgoing_delivery_attempts_on_delivery_id"
  end

  create_table "webhooks_outgoing_endpoints", force: :cascade do |t|
    t.integer "team_id"
    t.text "url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "name"
    t.json "event_type_ids", default: []
    t.integer "scaffolding_absolutely_abstract_creative_concept_id"
    t.integer "api_version", null: false
    t.datetime "deactivation_limit_reached_at"
    t.datetime "deactivated_at"
    t.integer "consecutive_failed_deliveries", default: 0, null: false
    t.string "webhook_secret", null: false
    t.index ["scaffolding_absolutely_abstract_creative_concept_id"], name: "index_endpoints_on_abstract_creative_concept_id"
    t.index ["team_id", "deactivated_at"], name: "idx_on_team_id_deactivated_at_d8a33babf2"
    t.index ["team_id"], name: "index_webhooks_outgoing_endpoints_on_team_id"
  end

  create_table "webhooks_outgoing_events", force: :cascade do |t|
    t.integer "subject_id"
    t.string "subject_type"
    t.json "data"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "team_id"
    t.string "uuid"
    t.json "payload"
    t.string "event_type_id"
    t.integer "api_version", null: false
    t.index ["team_id"], name: "index_webhooks_outgoing_events_on_team_id"
  end

  add_foreign_key "account_onboarding_invitation_lists", "teams"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "campaigns", "email_templates"
  add_foreign_key "campaigns", "segments"
  add_foreign_key "campaigns", "sender_addresses"
  add_foreign_key "campaigns", "teams"
  add_foreign_key "chats", "models"
  add_foreign_key "chats", "teams"
  add_foreign_key "chats", "users"
  add_foreign_key "companies", "teams"
  add_foreign_key "email_templates", "teams"
  add_foreign_key "events", "subscribers"
  add_foreign_key "events", "teams"
  add_foreign_key "integrations_stripe_installations", "oauth_stripe_accounts"
  add_foreign_key "integrations_stripe_installations", "teams"
  add_foreign_key "invitations", "account_onboarding_invitation_lists", column: "invitation_list_id"
  add_foreign_key "invitations", "teams"
  add_foreign_key "memberships", "invitations"
  add_foreign_key "memberships", "memberships", column: "added_by_id"
  add_foreign_key "memberships", "oauth_applications", column: "platform_agent_of_id"
  add_foreign_key "memberships", "teams"
  add_foreign_key "memberships", "users"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_applications", "teams"
  add_foreign_key "oauth_stripe_accounts", "users"
  add_foreign_key "scaffolding_absolutely_abstract_creative_concepts", "teams"
  add_foreign_key "scaffolding_completely_concrete_tangible_things", "scaffolding_absolutely_abstract_creative_concepts", column: "absolutely_abstract_creative_concept_id"
  add_foreign_key "scaffolding_completely_concrete_tangible_things_assignments", "memberships"
  add_foreign_key "scaffolding_completely_concrete_tangible_things_assignments", "scaffolding_completely_concrete_tangible_things", column: "tangible_thing_id"
  add_foreign_key "segments", "teams"
  add_foreign_key "sender_addresses", "teams"
  add_foreign_key "subscribers", "companies"
  add_foreign_key "subscribers", "teams"
  add_foreign_key "subscribers_imports", "teams"
  add_foreign_key "team_ses_configurations", "teams"
  add_foreign_key "tool_calls", "messages"
  add_foreign_key "users", "oauth_applications", column: "platform_agent_of_id"
  add_foreign_key "webhooks_outgoing_endpoints", "scaffolding_absolutely_abstract_creative_concepts"
  add_foreign_key "webhooks_outgoing_endpoints", "teams"
  add_foreign_key "webhooks_outgoing_events", "teams"
end
