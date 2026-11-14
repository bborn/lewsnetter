# frozen_string_literal: true

require "generators/ruby_llm/upgrade/legacy_content_sql"

class BackfillRubyLlmV2Data < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  BATCH_SIZE = 10_000
  PROGRESS_TABLE = :ruby_llm_v2_backfills

  def up
    raise "Generate this migration with --mode copy" if table_exists?(:ruby_llm_v2_upgrades)
    verify_upgrade_in_progress
    create_progress_table
    backfill_required_defaults
    backfill_message_content
    backfill_tool_results
    backfill_usages
    verify_backfills
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "RubyLLM 2.0 changes persisted record ownership"
  end

  private

  def verify_upgrade_in_progress
    legacy_columns = %i[content_raw input_tokens output_tokens model_id tool_call_id]
    unless legacy_columns.any? { |column| column_exists?(:messages, column) }
      raise "The RubyLLM 2.0 schema has already been cleaned. Do not run the backfill again."
    end
    return unless table_exists?(PROGRESS_TABLE)
    return unless progress_records.where(task: "finished", completed: true).exists?

    raise "The RubyLLM 2.0 upgrade is already finished. Do not run the backfill again."
  end

  def backfill_required_defaults
    {
      chats: {cancelled: false},
      messages: {cache_until_here: false},
      ruby_llm_tool_calls: {message_type: "Message"}
    }.each do |table, attributes|
      column, value = attributes.first
      migration_record(table).where(column => nil).in_batches(of: BATCH_SIZE) do |batch|
        batch.update_all(column => value)
      end
    end
  end

  def backfill_message_content
    return mark_completed("message_content") unless column_exists?(:messages, :content_raw)

    each_message_range("message_content") do |range|
      content_raw = message_value(:content_raw)
      raw_content = message_value(:raw_content)
      content = message_value(:content)
      structured_content = content_raw
      rendered_content = RubyLLM::Generators::LegacyContentSQL.new(connection).render(content: content, raw: content_raw)
      execute <<~SQL
        UPDATE #{quote_table(:messages)} AS legacy_messages
           SET #{quote_column(:raw_content)} = COALESCE(#{raw_content}, #{structured_content}),
               #{quote_column(:content)} = #{rendered_content}
         WHERE #{range}
           AND #{content_raw} IS NOT NULL
      SQL
    end
  end

  def backfill_tool_results
    result_reference = :tool_call_id
    return mark_completed("tool_results") unless column_exists?(:messages, result_reference)

    each_message_range("tool_results") do |range|
      messages = quote_table(:messages)
      tool_calls = quote_table(:ruby_llm_tool_calls)
      message_id = quoted_primary_key(:messages)
      tool_call_id = quoted_primary_key(:ruby_llm_tool_calls)
      result_id = message_value(result_reference)
      result_type = connection.quote("Message")
      execute <<~SQL
        UPDATE #{tool_calls}
           SET result_id = (
                 SELECT legacy_messages.#{message_id}
                   FROM #{messages} legacy_messages
                  WHERE #{range}
                    AND #{result_id} = #{tool_calls}.#{tool_call_id}
                  ORDER BY legacy_messages.#{message_id}
                  LIMIT 1
               ),
               result_type = #{result_type}
         WHERE EXISTS (
                 SELECT 1
                   FROM #{messages} legacy_messages
                  WHERE #{range}
                    AND #{result_id} = #{tool_calls}.#{tool_call_id}
               )
      SQL
    end
  end

  def backfill_usages
    joins, provider, model = usage_identity_sql
    conditions = legacy_usage_conditions
    return mark_completed("usages") if conditions.empty?

    each_message_range("usages") do |range|
      candidate = usage_candidate_sql(conditions, joins, range)
      execute usage_insert_sql(candidate, provider, model)
    end
  end

  def each_message_range(task)
    return if completed?(task)

    primary_key = connection.primary_key(:messages)
    records = migration_record(:messages)
    last_id = progress_value(task)
    loop do
      relation = records.order(primary_key => :asc)
      relation = relation.where("#{quote_column(primary_key)} > ?", last_id) if last_id
      ids = relation.limit(BATCH_SIZE).pluck(primary_key)
      break mark_completed(task) if ids.empty?

      upper_id = ids.last
      range = message_range(primary_key, last_id, upper_id)
      records.transaction do
        with_upgrade_safety { yield range }
        record_progress(task, upper_id)
      end
      say "#{task}: migrated through #{primary_key}=#{upper_id} (#{ids.length} messages)", true
      last_id = upper_id
    end
  end

  def message_range(primary_key, lower_id, upper_id)
    upper = "#{message_value(primary_key)} <= #{connection.quote(upper_id)}"
    return upper unless lower_id

    "#{message_value(primary_key)} > #{connection.quote(lower_id)} AND #{upper}"
  end

  def verify_backfills
    verify_message_content
    verify_tool_results
    verify_usages
  end

  def verify_message_content
    return unless column_exists?(:messages, :content_raw)

    missing = migration_record(:messages)
      .where.not(content_raw: nil)
      .where("raw_content IS NULL OR content IS NULL")
      .limit(1)
      .pick(connection.primary_key(:messages))
    raise "Message #{missing} did not preserve content_raw" if missing
  end

  def verify_tool_results
    result_reference = :tool_call_id
    return unless column_exists?(:messages, result_reference)

    messages = quote_table(:messages)
    tool_calls = quote_table(:ruby_llm_tool_calls)
    missing = select_value(<<~SQL)
      SELECT legacy_messages.#{quoted_primary_key(:messages)}
        FROM #{messages} legacy_messages
        LEFT JOIN #{tool_calls} migrated_tool_calls
          ON #{message_value(result_reference)} = migrated_tool_calls.#{quoted_primary_key(:ruby_llm_tool_calls)}
         AND migrated_tool_calls.result_type = #{connection.quote("Message")}
         AND migrated_tool_calls.result_id = legacy_messages.#{quoted_primary_key(:messages)}
       WHERE #{message_value(result_reference)} IS NOT NULL
         AND migrated_tool_calls.#{quoted_primary_key(:ruby_llm_tool_calls)} IS NULL
       LIMIT 1
    SQL
    raise "Message #{missing} did not preserve its tool result association" if missing
  end

  def verify_usages
    joins, provider, model = usage_identity_sql
    conditions = legacy_usage_conditions
    return if conditions.empty?

    candidate = usage_candidate_sql(conditions, joins, "1 = 1")
    missing = select_value(<<~SQL)
      SELECT #{message_value(connection.primary_key(:messages))}
        #{candidate}
       LIMIT 1
    SQL
    return unless missing

    raise "Message #{missing} did not receive its RubyLLM usage entry (provider: #{provider}, model: #{model})"
  end

  def usage_identity_sql
    providers = []
    models = []
    joins = []
    registry = quote_table(:ruby_llm_models)
    registry_key = quoted_primary_key(:ruby_llm_models)

    if column_exists?(:messages, :model_id)
      explicit_model = column_definition(:messages, :model_id)
      if explicit_model.type == :string
        models << message_value(:model_id)
        providers << message_value(:provider) if column_exists?(:messages, :provider)
      else
        joins << "LEFT JOIN #{registry} legacy_message_models " \
                 "ON #{message_value(:model_id)} = legacy_message_models.#{registry_key}"
        providers << "legacy_message_models.#{quote_column(:provider)}"
        models << "legacy_message_models.#{quote_column(:model_id)}"
      end
    end

    if column_exists?(:chats, :ruby_llm_model_id)
      chats = quote_table(:chats)
      joins << "LEFT JOIN #{chats} legacy_chats " \
               "ON #{message_value(:chat_id)} = legacy_chats.#{quoted_primary_key(:chats)}"
      joins << "LEFT JOIN #{registry} legacy_chat_models " \
               "ON legacy_chats.#{quote_column(:ruby_llm_model_id)} = legacy_chat_models.#{registry_key}"
      providers << "legacy_chat_models.#{quote_column(:provider)}"
      models << "legacy_chat_models.#{quote_column(:model_id)}"
    end

    [joins.join("\n"), coalesce_sql(providers), coalesce_sql(models)]
  end

  def legacy_usage_conditions
    token_columns = %i[
      input_tokens output_tokens cached_tokens cache_creation_tokens cache_read_tokens cache_write_tokens
      thinking_tokens total_cost
    ]
    conditions = token_columns.filter_map do |column|
      "#{message_value(column)} IS NOT NULL" if column_exists?(:messages, column)
    end
    if column_exists?(:messages, :cost_details)
      costs = %w[input output cache_read cache_write thinking total].map do |key|
        "#{legacy_cost_detail(key)} IS NOT NULL"
      end
      conditions << "(#{costs.join(" OR ")})"
    end
    conditions << "#{message_value(:role)} = 'assistant'" if column_exists?(:messages, :role)
    conditions
  end

  def usage_candidate_sql(conditions, joins, range)
    usages = quote_table(:ruby_llm_usages)
    usage_range = range.gsub(message_value(connection.primary_key(:messages)), "existing_usages.message_id")
    <<~SQL
      FROM #{quote_table(:messages)} legacy_messages
      #{joins}
      WHERE (#{conditions.join(" OR ")})
        AND #{range}
        AND NOT EXISTS (
          SELECT 1
            FROM #{usages} existing_usages
           WHERE existing_usages.message_type = #{connection.quote("Message")}
             AND (#{usage_range})
             AND existing_usages.message_id = #{message_value(connection.primary_key(:messages))}
             AND existing_usages.operation = 'chat'
             AND existing_usages.status = 'succeeded'
        )
    SQL
  end

  def usage_insert_sql(candidate, provider, model)
    columns = %i[
      chat_type chat_id message_type message_id operation provider model status
      input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens
      input_cost output_cost cache_read_cost cache_write_cost thinking_cost total_cost
      created_at updated_at
    ].map { |column| quote_column(column) }.join(", ")
    values = [
      connection.quote("Chat"),
      message_value(:chat_id),
      connection.quote("Message"),
      message_value(connection.primary_key(:messages)),
      connection.quote("chat"),
      provider,
      model,
      connection.quote("succeeded"),
      legacy_message_value(:input_tokens),
      legacy_message_value(:output_tokens),
      preferred_message_value(:cache_read_tokens, :cached_tokens),
      preferred_message_value(:cache_write_tokens, :cache_creation_tokens),
      legacy_message_value(:thinking_tokens),
      legacy_cost_detail("input"),
      legacy_cost_detail("output"),
      legacy_cost_detail("cache_read"),
      legacy_cost_detail("cache_write"),
      legacy_cost_detail("thinking"),
      legacy_total_cost,
      legacy_message_value(:created_at, fallback: "CURRENT_TIMESTAMP"),
      legacy_message_value(:updated_at, fallback: "CURRENT_TIMESTAMP")
    ].join(", ")
    <<~SQL
      INSERT INTO #{quote_table(:ruby_llm_usages)} (#{columns})
      SELECT #{values}
        #{candidate}
    SQL
  end

  def preferred_message_value(preferred, fallback)
    return message_value(preferred) if column_exists?(:messages, preferred)

    legacy_message_value(fallback)
  end

  def legacy_message_value(column, fallback: "NULL")
    return fallback unless column_exists?(:messages, column)

    message_value(column)
  end

  def legacy_cost_detail(key)
    return "NULL" unless column_exists?(:messages, :cost_details)

    details = message_value(:cost_details)
    "json_extract(#{details}, '$.#{key}')"
  end

  def legacy_total_cost
    direct = legacy_message_value(:total_cost)
    detailed = legacy_cost_detail("total")
    return "NULL" if direct == "NULL" && detailed == "NULL"
    return detailed if direct == "NULL"
    return direct if detailed == "NULL"

    "COALESCE(#{direct}, #{detailed})"
  end

  def create_progress_table
    return if table_exists?(PROGRESS_TABLE)

    create_table PROGRESS_TABLE, id: false do |table|
      table.string :task, null: false
      table.column :last_id, reference_type_for(:messages)
      table.boolean :completed, null: false, default: false
      table.index :task, unique: true
    end
  end

  def progress_value(task)
    progress_records.where(task: task).pick(:last_id)
  end

  def completed?(task)
    progress_records.where(task: task, completed: true).exists?
  end

  def record_progress(task, last_id)
    row = progress_records.where(task: task)
    return row.update_all(last_id: last_id, completed: false) if row.exists?

    progress_records.insert_all!([{task: task, last_id: last_id, completed: false}], returning: false)
  end

  def mark_completed(task)
    row = progress_records.where(task: task)
    return row.update_all(completed: true) if row.exists?

    progress_records.insert_all!([{task: task, completed: true}], returning: false)
  end

  def coalesce_sql(values)
    values = Array(values).compact
    return "NULL" if values.empty?
    return values.first if values.one?

    "COALESCE(#{values.join(", ")})"
  end

  def message_value(column) = "legacy_messages.#{quote_column(column)}"
  def column_definition(table, column) = connection.columns(table).find { |candidate| candidate.name == column.to_s }
  def quoted_primary_key(table) = quote_column(connection.primary_key(table))
  def quote_table(table) = connection.quote_table_name(table)
  def quote_column(column) = connection.quote_column_name(column)

  def reference_type_for(table)
    column = column_definition(table, connection.primary_key(table))
    raise "Could not determine the primary key type for #{table}" unless column

    return :bigint if column.type == :integer && column.limit == 8

    column.type
  end

  def with_upgrade_safety(&)
    return safety_assured(&) if respond_to?(:safety_assured, true)

    yield
  end

  def progress_records = migration_record(PROGRESS_TABLE)

  def migration_record(table)
    Class.new(ActiveRecord::Base) do
      self.table_name = table.to_s
      self.inheritance_column = :_type_disabled
    end
  end
end
