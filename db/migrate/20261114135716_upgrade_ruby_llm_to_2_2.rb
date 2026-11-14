class UpgradeRubyLlmTo22 < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:ruby_llm_tool_calls, :provider_call_id)
      if column_exists?(:ruby_llm_tool_calls, :provider_id)
        rename_column :ruby_llm_tool_calls, :provider_id, :provider_call_id
      else
        add_column :ruby_llm_tool_calls, :provider_call_id, :string
      end
    end

    add_column :ruby_llm_tool_calls, :namespace, :string unless column_exists?(:ruby_llm_tool_calls, :namespace)

    unless column_exists?(:chats, :claim_token)
      add_column :chats, :claim_token, :string
    end

    unless column_exists?(:chats, :claimed_until)
      add_column :chats, :claimed_until, :datetime
    end

    unless index_exists?(:chats, :claimed_until)
      add_index :chats, :claimed_until, where: "claim_token IS NOT NULL"
    end

    unless column_exists?(:ruby_llm_tool_calls, :claimed_until)
      add_column :ruby_llm_tool_calls, :claimed_until, :datetime
    end

    unless column_exists?(:messages, :phase)
      add_column :messages, :phase, :string
    end

    unless column_exists?(:messages, :continuation)
      add_column :messages, :continuation, :text
    end

    %i[workflow_id workflow_name workflow_step_id workflow_step_name].each do |column|
      add_column :ruby_llm_usages, column, :string unless column_exists?(:ruby_llm_usages, column)
    end
    add_index :ruby_llm_usages, :workflow_id unless index_exists?(:ruby_llm_usages, :workflow_id)

    add_column :ruby_llm_usages, :characters, :integer unless column_exists?(:ruby_llm_usages, :characters)
    unless column_exists?(:ruby_llm_usages, :audio_seconds)
      add_column :ruby_llm_usages, :audio_seconds, :decimal, precision: 16, scale: 6
    end
    add_column :ruby_llm_usages, :search_units, :integer unless column_exists?(:ruby_llm_usages, :search_units)
    %i[characters_cost audio_seconds_cost search_units_cost].each do |column|
      unless column_exists?(:ruby_llm_usages, column)
        add_column :ruby_llm_usages, column, :decimal, precision: 16, scale: 10
      end
    end

    unless table_exists?(:ruby_llm_queued_messages)
      create_table :ruby_llm_queued_messages, id: :bigint do |t|
        t.references :chat, polymorphic: true, null: false, type: :bigint, index: false
        t.references :sender, polymorphic: true, type: :bigint, index: false
        t.text :content
        t.boolean :steer, default: true, null: false
        t.timestamps

        t.index [:chat_type, :chat_id]
        t.index [:sender_type, :sender_id]
      end
    end

    unless table_exists?(:ruby_llm_chat_files)
      create_table :ruby_llm_chat_files, id: :bigint do |t|
        t.references :chat, polymorphic: true, null: false, type: :bigint, index: false
        t.references :owner, polymorphic: true, type: :bigint, index: false
        t.string :path, null: false
        t.string :content_type
        t.bigint :byte_size
        t.string :digest
        t.text :text
        t.string :read_digest
        t.timestamps

        t.index [:chat_type, :chat_id, :path]
        t.index [:owner_type, :owner_id]
      end
    end
    unless column_exists?(:ruby_llm_chat_files, :read_digest)
      add_column :ruby_llm_chat_files, :read_digest, :string
    end

    allow_code_execution_usage unless usage_accepts_code_execution?
    # Asks again: a check of the application's may still refuse the row.
    warn_about_code_execution_usage unless usage_accepts_code_execution?
  end

  def down
    drop_table :ruby_llm_chat_files, if_exists: true
    drop_table :ruby_llm_queued_messages, if_exists: true
    remove_column :messages, :continuation
    %i[search_units_cost audio_seconds_cost characters_cost search_units audio_seconds characters].each do |column|
      remove_column :ruby_llm_usages, column
    end
    remove_index :ruby_llm_usages, :workflow_id, if_exists: true
    remove_column :ruby_llm_usages, :workflow_step_name
    remove_column :ruby_llm_usages, :workflow_step_id
    remove_column :ruby_llm_usages, :workflow_name
    remove_column :ruby_llm_usages, :workflow_id
    remove_column :messages, :phase
    remove_column :ruby_llm_tool_calls, :namespace
    remove_column :ruby_llm_tool_calls, :claimed_until
    remove_index :chats, :claimed_until, if_exists: true
    remove_column :chats, :claimed_until
    remove_column :chats, :claim_token
    remove_column :ruby_llm_tool_calls, :provider_call_id
  end

  private

  # Asks the database, since each one prints a check differently: a check
  # refusing the row leaves code runs unmetered, with only a warning at run time.
  def usage_accepts_code_execution?
    connection.transaction(requires_new: true) do
      execute <<~SQL.squish
        INSERT INTO ruby_llm_usages (operation, provider, model, status, created_at, updated_at)
        VALUES ('code_execution', 'sandbox', 'upgrade check', 'succeeded', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      raise ActiveRecord::Rollback
    end
    true
  rescue ActiveRecord::StatementInvalid
    false
  end

  def allow_code_execution_usage
    lists = check_constraints(:ruby_llm_usages).select { |check| operation_list?(check.expression) }
    lists.each { |check| remove_check_constraint :ruby_llm_usages, name: check.name }
    return if lists.empty?

    add_check_constraint :ruby_llm_usages, "operation IN ('chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank', 'judgment', 'video', 'research', 'code_execution')"
  end

  # The list the install generator wrote, as each database prints it. A check
  # with other conditions is the application's, and stays.
  def operation_list?(expression)
    names = expression.scan(/'(\w+)'/).flatten
    expression.match?(/\A\(*[`"]?operation[`"]?\)*(?:::\w+)?\s*(?:in\b|=\s*any\b)/i) &&
      !expression.match?(/\b(?:and|or|not)\b|<>|!=/i) && names.size > 1 && (names - %w[chat embedding moderation image speech transcription ocr rerank judgment video research code_execution]).empty?
  end

  def warn_about_code_execution_usage
    checks = check_constraints(:ruby_llm_usages).select { |check| check.expression.match?(/\boperation\b/) }
      .map(&:name).join(", ")
    say "RubyLLM: ruby_llm_usages refuses 'code_execution' rows, so code runs will go unmetered with only a " \
        "warning in the log. Check these constraints, or any NOT NULL column you added: #{checks}. Allow the " \
        'value in a new migration: see "Code Runs Write Usage Rows" in the upgrading guide.'
  end
end
