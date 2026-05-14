class Segment < ApplicationRecord
  # 🚅 add concerns above.

  # Forbidden tokens kept in sync with AI::SegmentTranslator::FORBIDDEN_TOKENS —
  # defense in depth at the job/scope-application layer. If the AI service
  # ever changes how predicates are sourced (UI builder, manual edit, etc.)
  # we still refuse to execute anything that looks like a statement.
  FORBIDDEN_PREDICATE_TOKENS = %w[
    DROP DELETE INSERT UPDATE TRUNCATE ALTER GRANT REVOKE CREATE
    ATTACH DETACH COPY VACUUM EXEC EXECUTE CALL
    ; -- /*
  ].freeze

  class InvalidPredicate < StandardError; end

  # 🚅 add attribute accessors above.

  belongs_to :team

  has_many :campaigns, dependent: :restrict_with_error

  validates :name, presence: true
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # Returns the SQL WHERE fragment stored in definition["predicate"], or nil
  # if the segment has no predicate (e.g. UI not yet wired, AI returned empty).
  def predicate
    definition.is_a?(Hash) ? definition["predicate"].to_s.strip.presence : nil
  end

  # Virtual setter so the segment form can post a predicate alongside the
  # other fields. We write into the `definition` JSON column rather than
  # introducing a new schema column. Blanks clear the predicate entirely.
  def predicate=(value)
    self.definition ||= {}
    new_pred = value.to_s.strip
    if new_pred.blank?
      self.definition = definition.is_a?(Hash) ? definition.except("predicate") : {}
    else
      self.definition = (definition.is_a?(Hash) ? definition : {}).merge("predicate" => new_pred)
    end
  end

  # Apply this segment's predicate to an existing ActiveRecord scope and return
  # the narrowed scope. If there's no predicate the scope is returned as-is.
  # Raises Segment::InvalidPredicate if the stored predicate contains any
  # forbidden SQL keyword — callers (notably SendCampaignJob) catch this and
  # transition the campaign to failed with a useful error message.
  def applies_to(scope)
    pred = predicate
    return scope if pred.blank?

    validation_errors = self.class.validate_predicate(pred)
    if validation_errors.any?
      raise InvalidPredicate, "Segment #{id} has invalid predicate: #{validation_errors.join(", ")}"
    end

    # Auto-join companies when the predicate references the companies table
    # (or its JSON custom_attributes). We can't reach company-level columns
    # without a JOIN, and asking the AI translator (or a hand author) to spell
    # out joins is fragile, so the segment layer handles it.
    scope = scope.joins(:company) if pred.match?(/\bcompanies\./i)
    scope.where(pred)
  end

  # Mirror of AI::SegmentTranslator#validate_predicate. Returns an array of
  # error messages; empty array means the predicate passes the allowlist.
  def self.validate_predicate(predicate)
    errors = []
    return ["Predicate is blank"] if predicate.to_s.strip.blank?

    upcased = predicate.upcase
    FORBIDDEN_PREDICATE_TOKENS.each do |tok|
      errors << "Predicate contains forbidden token: #{tok}" if upcased.include?(tok)
    end

    predicate.scan(/\b([a-zA-Z_][a-zA-Z0-9_]*)\.([a-zA-Z_][a-zA-Z0-9_]*)/) do |left, _right|
      next if left.casecmp("subscribers").zero?
      next if left.casecmp("companies").zero?
      errors << "Predicate references disallowed table: #{left}"
    end

    errors.uniq
  end
  # 🚅 add methods above.
end
