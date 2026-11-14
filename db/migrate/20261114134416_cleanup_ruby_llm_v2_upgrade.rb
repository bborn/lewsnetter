# frozen_string_literal: true

class CleanupRubyLlmV2Upgrade < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  PROGRESS_TABLE = :ruby_llm_v2_backfills

  def up
    raise "Generate cleanup with --mode copy for this database" if table_exists?(:ruby_llm_v2_upgrades)
    unless table_exists?(PROGRESS_TABLE)
      return unless legacy_columns.any?

      raise "RubyLLM 2.0 upgrade progress is missing. Run the finish migration before cleanup."
    end
    unless migration_record(PROGRESS_TABLE).where(task: "finished", completed: true).exists?
      raise "Run FinishRubyLlmV2Upgrade before removing the legacy message columns"
    end

    remove_legacy_message_columns
    drop_table PROGRESS_TABLE
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "RubyLLM 2.0 removes legacy message data"
  end

  private

  def remove_legacy_message_columns
    table = :messages
    remove_matching_indexes(table, :role)
    reference_columns = %i[model_id tool_call_id]
    reference_columns.each do |column|
      remove_column_foreign_keys(table, column)
      remove_matching_indexes(table, column)
    end

    columns = legacy_columns
    with_upgrade_safety { remove_columns table, *columns } if columns.any?
  end

  def remove_column_foreign_keys(table, column)
    connection.foreign_keys(table).each do |key|
      remove_foreign_key(table, key.to_table, column: column) if key.column == column.to_s
    end
  end

  def remove_matching_indexes(table, columns)
    connection.indexes(table).each do |index|
      remove_upgrade_index(table, index.name) if index.columns == Array(columns).map(&:to_s)
    end
  end

  def remove_upgrade_index(table, name)
    options = {name: name}
    remove_index table, **options
  end

  def with_upgrade_safety(&)
    return safety_assured(&) if respond_to?(:safety_assured, true)

    yield
  end

  def legacy_columns
    candidates = %i[
      model_id tool_call_id
      content_raw input_tokens output_tokens cached_tokens cache_creation_tokens cache_read_tokens
      cache_write_tokens thinking_tokens total_cost cost_details
    ]
    candidates.uniq.select { |column| column_exists?(:messages, column) }
  end

  def migration_record(table)
    Class.new(ActiveRecord::Base) do
      self.table_name = table.to_s
      self.inheritance_column = :_type_disabled
    end
  end
end
