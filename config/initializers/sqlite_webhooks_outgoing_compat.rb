# SQLite-flavored overrides for Bullet Train scopes that are written
# Postgres-only with operators like `@>` (jsonb containment) and `?|`
# (any-key match). SQLite raises `unrecognized token: "@"` on the first and
# treats `?` as a bound-parameter placeholder for the second, so both blow up.
#
# We monkey-patch these scopes with SQLite-native equivalents that use
# `json_each` (part of SQLite's bundled json1 extension; available in every
# SQLite that Rails 8 ships against). This belongs in app config (not a gem
# fork) because the swap to SQLite is our deliberate departure from Bullet
# Train's Postgres default.

# ---- bullet_train-roles: with_roles --------------------------------------
# The gem's `included` block defines `with_roles` directly on the host class.
# ActiveSupport::Concern forbids us from chaining a second `included` block,
# so we patch via the `included` hook on Roles::Support: every time it's
# included into a model, immediately redefine `with_roles` on that model.
if defined?(Roles::Support)
  Roles::Support.singleton_class.prepend(Module.new {
    def included(base)
      super
      base.define_singleton_method(:with_roles) do |roles|
        adapter = connection.adapter_name.downcase
        if adapter.include?("sqlite")
          keys = roles.map(&:key_plus_included_by_keys).flatten.uniq.map(&:to_s)
          next none if keys.empty?
          clauses = keys.map { "EXISTS (SELECT 1 FROM json_each(#{table_name}.role_ids) WHERE json_each.value = ?)" }
          where(clauses.join(" OR "), *keys)
        elsif ["mysql", "trilogy"].any? { |a| adapter.include?(a) }
          with_roles_mysql(roles)
        else
          with_roles_postgres(roles)
        end
      end
    end
  })

  # Models that already included Roles::Support before this initializer ran
  # (none in normal boot order, but be defensive against eager-load).
  ActiveRecord::Base.descendants.each do |klass|
    next unless klass.included_modules.include?(Roles::Support)
    klass.singleton_class.prepend(Module.new {
      define_method(:with_roles) do |roles|
        adapter = connection.adapter_name.downcase
        if adapter.include?("sqlite")
          keys = roles.map(&:key_plus_included_by_keys).flatten.uniq.map(&:to_s)
          next none if keys.empty?
          clauses = keys.map { "EXISTS (SELECT 1 FROM json_each(#{table_name}.role_ids) WHERE json_each.value = ?)" }
          where(clauses.join(" OR "), *keys)
        elsif ["mysql", "trilogy"].any? { |a| adapter.include?(a) }
          with_roles_mysql(roles)
        else
          with_roles_postgres(roles)
        end
      end
    })
  end
end

# ---- Webhooks::Outgoing::Endpoint#listening_for_event_type_id ------------
# This scope is on a specific class, so we patch it after autoload.
Rails.application.config.to_prepare do
  next unless ActiveRecord::Base.connection.adapter_name.match?(/sqlite/i)

  endpoint_class = "Webhooks::Outgoing::Endpoint".safe_constantize
  if endpoint_class
    endpoint_class.singleton_class.class_eval do
      # The gem version reads:
      #   where("event_type_ids @> ? OR event_type_ids = '[]'::jsonb", "\"#{event_type_id}\"")
      # We look for the literal value inside the JSON array, OR match endpoints
      # with an empty array (the gem semantic: empty array = "listening to
      # everything").
      define_method(:listening_for_event_type_id) do |event_type_id|
        sql = "EXISTS (SELECT 1 FROM json_each(event_type_ids) WHERE json_each.value = ?) OR event_type_ids = '[]'"
        where(sql, event_type_id.to_s)
      end
    end
  end
end
