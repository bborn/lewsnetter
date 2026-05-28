# frozen_string_literal: true

module Teams
  # Seeds a brand-new team with enough data to be interesting on day one:
  # 5 demo subscribers with varied custom_attributes (so the segment
  # builder has something to play with), 1 email template, and 1 draft
  # campaign. Fired by the after_create callback on Team.
  #
  # Idempotent: re-running on a team that already has subscribers OR
  # campaigns is a no-op. Skippable globally via LEWSNETTER_SKIP_SEEDING=true
  # so the test suite + import jobs don't get polluted.
  class SampleDataSeeder
    def self.call(team)
      new(team).call
    end

    def initialize(team)
      @team = team
    end

    def call
      return if ENV["LEWSNETTER_SKIP_SEEDING"] == "true"
      return if @team.subscribers.any? || @team.campaigns.any?

      ActiveRecord::Base.transaction do
        seed_subscribers
        template = seed_email_template
        seed_campaign(template)
      end
    rescue => e
      # Seeding is best-effort decoration; never break account creation
      # if a sample row fails to insert.
      Rails.logger.warn("[SampleDataSeeder] team=#{@team.id} failed: #{e.class}: #{e.message}")
    end

    private

    SAMPLE_SUBSCRIBERS = [
      {email: "alice.demo@example.com", name: "Alice Demo", external_id: "demo-1",
       attrs: {"plan" => "growth", "tenant_type" => "brand", "tabs_enabled" => "billing,reports,influencer_hub"}},
      {email: "bob.demo@example.com", name: "Bob Demo", external_id: "demo-2",
       attrs: {"plan" => "starter", "tenant_type" => "brand", "tabs_enabled" => "billing,reports"}},
      {email: "carol.demo@example.com", name: "Carol Demo", external_id: "demo-3",
       attrs: {"plan" => "enterprise", "tenant_type" => "brand", "tabs_enabled" => "billing,reports,influencer_hub,events"}},
      {email: "dave.demo@example.com", name: "Dave Demo", external_id: "demo-4",
       attrs: {"plan" => "free", "tenant_type" => "events"}},
      {email: "eve.demo@example.com", name: "Eve Demo", external_id: "demo-5",
       attrs: {"plan" => "growth", "tenant_type" => "talent_manager"}}
    ].freeze

    def seed_subscribers
      SAMPLE_SUBSCRIBERS.each do |row|
        @team.subscribers.create!(
          email: row[:email],
          name: row[:name],
          external_id: row[:external_id],
          subscribed: true,
          custom_attributes: row[:attrs]
        )
      end
    end

    def seed_email_template
      @team.email_templates.create!(
        name: "Welcome (sample)",
        mjml_body: sample_mjml
      )
    end

    def seed_campaign(template)
      @team.campaigns.create!(
        email_template: template,
        subject: "Hello from Lewsnetter 👋",
        preheader: "A sample campaign to get you started.",
        body_mjml: sample_mjml,
        body_markdown: sample_markdown,
        status: "draft"
      )
    end

    def sample_mjml
      <<~MJML
        <mjml>
          <mj-body background-color="#fafafa">
            <mj-section>
              <mj-column>
                <mj-text font-family="-apple-system, system-ui, sans-serif" font-size="22px" font-weight="600" color="#18181b">
                  Welcome, {{ subscriber.name | default: "friend" }}.
                </mj-text>
                <mj-text font-family="-apple-system, system-ui, sans-serif" font-size="15px" color="#52525b" line-height="1.5">
                  This is a sample campaign — edit it however you like. The body uses Liquid for personalization, so anything you push to <code>subscriber.attributes</code> from your source app is available here.
                </mj-text>
                <mj-button background-color="#ea580c" font-family="-apple-system, system-ui, sans-serif" border-radius="6px">
                  Open the editor
                </mj-button>
              </mj-column>
            </mj-section>
          </mj-body>
        </mjml>
      MJML
    end

    def sample_markdown
      <<~MD
        Welcome, {{ subscriber.name | default: "friend" }}.

        This is a sample campaign — edit it however you like. The body uses Liquid for personalization, so anything you push to `subscriber.attributes` from your source app is available here.
      MD
    end
  end
end
