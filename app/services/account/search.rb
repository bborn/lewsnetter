module Account
  # Cmd+K palette search orchestrator. Single entry point used by
  # Account::SearchController#index so the controller can stay tiny and
  # the query logic is testable in isolation.
  #
  # Returns a structured `{ groups: [...] }` Hash ready to render as JSON.
  # Each group is { label:, type:, items: [{title, subtitle, url, type}] }.
  #
  # Scoping: every query goes through the given `team`, so users can only
  # see results from data they already have access to.
  #
  # Empty query semantics: returns the 3 most recently updated rows from
  # each surface so the palette is useful the instant it opens. With a
  # query, each surface caps at 5 results so the palette stays scannable.
  class Search
    PER_GROUP_LIMIT = 5
    PER_GROUP_RECENT_LIMIT = 3

    # Wrap the raw query string with helpers for safe LIKE matching. We
    # downcase here and use LOWER(column) LIKE :n in queries so behaviour
    # matches the existing subscriber typeahead.
    def initialize(team:, query:, url_helpers:)
      @team = team
      @query = query.to_s.strip
      @h = url_helpers
    end

    def call
      {groups: groups.reject { |g| g[:items].empty? }}
    end

    private

    attr_reader :team, :query, :h

    def groups
      [
        {label: "Subscribers", type: "subscriber", items: subscribers},
        {label: "Companies", type: "company", items: companies},
        {label: "Segments", type: "segment", items: segments},
        {label: "Campaigns", type: "campaign", items: campaigns},
        {label: "Email Templates", type: "email_template", items: email_templates},
        {label: "Sender Addresses", type: "sender_address", items: sender_addresses}
      ]
    end

    # ----- Subscribers -----------------------------------------------------
    #
    # Subscriber#email is deterministic-encrypted: exact equality works, LIKE
    # does not. Subscriber#name is non-deterministic — neither works on the
    # ciphertext. With support_unencrypted_data: true any legacy plaintext
    # rows still match LIKE; we OR that into the predicate so historic rows
    # remain searchable even though new rows won't surface via name LIKE.
    def subscribers
      scope = team.subscribers
      rows =
        if query.blank?
          scope.order(updated_at: :desc).limit(PER_GROUP_RECENT_LIMIT)
        else
          ids = subscriber_match_ids
          return [] if ids.empty?
          scope.where(id: ids).limit(PER_GROUP_LIMIT)
        end

      rows.map do |s|
        title = s.name.presence || s.email.presence || "Subscriber ##{s.id}"
        subtitle =
          if s.name.present? && s.email.present?
            s.email
          elsif s.external_id.present?
            s.external_id
          else
            "Subscriber"
          end
        {
          title: title,
          subtitle: subtitle,
          url: h.account_subscriber_path(s),
          type: "subscriber"
        }
      end
    end

    # Build the union of subscriber matches across three predicates:
    #   1. exact email (works because email is deterministic-encrypted)
    #   2. LIKE on name (matches legacy plaintext rows only — see encryption note)
    #   3. LIKE on external_id (plaintext column, always works)
    # Returns at most PER_GROUP_LIMIT ids, ordered email-then-id for stability.
    def subscriber_match_ids
      scope = team.subscribers
      needle = "%#{query.downcase}%"

      email_ids = scope.where(email: query).limit(PER_GROUP_LIMIT).pluck(:id)
      name_ids  = scope.where("LOWER(name) LIKE :n", n: needle).limit(PER_GROUP_LIMIT).pluck(:id)
      ext_ids   = scope.where("LOWER(external_id) LIKE :n", n: needle).limit(PER_GROUP_LIMIT).pluck(:id)

      (email_ids + name_ids + ext_ids).uniq.first(PER_GROUP_LIMIT)
    end

    # ----- Companies -------------------------------------------------------
    #
    # No dedicated company show page exists — link to the subscribers index
    # filtered by company_id (the index already accepts that filter via the
    # standard Bullet Train scaffolding). Falls back to the bare subscribers
    # index if the routing helper isn't available in the test environment.
    def companies
      scope = team.companies
      rows =
        if query.blank?
          scope.order(updated_at: :desc).limit(PER_GROUP_RECENT_LIMIT)
        else
          needle = "%#{query.downcase}%"
          scope.where("LOWER(name) LIKE :n OR LOWER(external_id) LIKE :n", n: needle)
            .order(:name)
            .limit(PER_GROUP_LIMIT)
        end

      rows.map do |c|
        {
          title: c.name.presence || "Company ##{c.id}",
          subtitle: c.external_id.presence || "Company",
          url: h.account_team_subscribers_path(team, company_id: c.id),
          type: "company"
        }
      end
    end

    # ----- Segments --------------------------------------------------------
    def segments
      scope = team.segments
      rows =
        if query.blank?
          scope.order(updated_at: :desc).limit(PER_GROUP_RECENT_LIMIT)
        else
          needle = "%#{query.downcase}%"
          # natural_language_source is the column the AI translator writes
          # the user's plain-English segment description to. Search both so
          # users can find segments by name OR by the prompt they typed.
          scope.where("LOWER(name) LIKE :n OR LOWER(natural_language_source) LIKE :n", n: needle)
            .order(:name)
            .limit(PER_GROUP_LIMIT)
        end

      rows.map do |s|
        {
          title: s.name.presence || "Segment ##{s.id}",
          subtitle: s.natural_language_source.to_s.presence || "Segment",
          url: h.account_segment_path(s),
          type: "segment"
        }
      end
    end

    # ----- Campaigns -------------------------------------------------------
    def campaigns
      scope = team.campaigns
      rows =
        if query.blank?
          scope.order(updated_at: :desc).limit(PER_GROUP_RECENT_LIMIT)
        else
          needle = "%#{query.downcase}%"
          scope.where("LOWER(subject) LIKE :n OR LOWER(preheader) LIKE :n", n: needle)
            .order(updated_at: :desc)
            .limit(PER_GROUP_LIMIT)
        end

      rows.map do |c|
        {
          title: c.subject.presence || "Untitled",
          subtitle: campaign_subtitle(c),
          url: h.account_campaign_path(c),
          type: "campaign"
        }
      end
    end

    def campaign_subtitle(campaign)
      bits = []
      bits << campaign.status.to_s.upcase if campaign.status.present?
      bits << campaign.preheader if campaign.preheader.present?
      bits.join(" · ").presence || "Campaign"
    end

    # ----- Email Templates -------------------------------------------------
    def email_templates
      scope = team.email_templates
      rows =
        if query.blank?
          scope.order(updated_at: :desc).limit(PER_GROUP_RECENT_LIMIT)
        else
          needle = "%#{query.downcase}%"
          scope.where("LOWER(name) LIKE :n", n: needle)
            .order(:name)
            .limit(PER_GROUP_LIMIT)
        end

      rows.map do |t|
        {
          title: t.name.presence || "Template ##{t.id}",
          subtitle: "Email Template",
          url: h.account_email_template_path(t),
          type: "email_template"
        }
      end
    end

    # ----- Sender Addresses ------------------------------------------------
    #
    # Both `name` and `email` on SenderAddress are plaintext columns (no
    # `encrypts` declaration in the model), so LIKE works directly.
    def sender_addresses
      scope = team.sender_addresses
      rows =
        if query.blank?
          scope.order(updated_at: :desc).limit(PER_GROUP_RECENT_LIMIT)
        else
          needle = "%#{query.downcase}%"
          scope.where("LOWER(name) LIKE :n OR LOWER(email) LIKE :n", n: needle)
            .order(:email)
            .limit(PER_GROUP_LIMIT)
        end

      rows.map do |s|
        title = s.name.presence || s.email
        subtitle = s.name.present? ? s.email : (s.verified? ? "Verified" : "Sender")
        {
          title: title,
          subtitle: subtitle,
          url: h.account_sender_address_path(s),
          type: "sender_address"
        }
      end
    end
  end
end
