# Post-deploy data migrations for the markdown campaign body authoring rollout.
#
# These are idempotent. Re-running them with the same campaign/template state
# is a no-op. They're isolated to specific record IDs because the rollout
# targets the InfluenceKit prod fixtures (EmailTemplate #2, Campaign #3) — the
# template + campaign that were authored by the previous implementer with the
# full newsletter content baked into the template body.
#
# Usage on prod:
#   eval "$(mise activate bash)"
#   bundle exec kamal app exec --reuse --version=<sha> "bin/rails campaigns:migrate_to_markdown_body"

namespace :campaigns do
  desc "Convert EmailTemplate #2 + Campaign #3 to the markdown body authoring path"
  task migrate_to_markdown_body: :environment do
    template = EmailTemplate.find_by(id: 2)
    campaign = Campaign.find_by(id: 3)

    if template.nil?
      puts "[campaigns:migrate_to_markdown_body] EmailTemplate #2 not found — skipping template update."
    elsif template.mjml_body.to_s.include?("{{body}}")
      puts "[campaigns:migrate_to_markdown_body] EmailTemplate #2 already has {{body}} placeholder — skipping."
    else
      template.update!(mjml_body: chrome_only_template)
      puts "[campaigns:migrate_to_markdown_body] EmailTemplate #2 updated to chrome-only layout with {{body}} placeholder."
    end

    if campaign.nil?
      puts "[campaigns:migrate_to_markdown_body] Campaign #3 not found — skipping campaign backfill."
    elsif campaign.body_markdown.present?
      puts "[campaigns:migrate_to_markdown_body] Campaign #3 already has body_markdown — skipping."
    else
      campaign.update!(body_markdown: april_updates_markdown)
      puts "[campaigns:migrate_to_markdown_body] Campaign #3.body_markdown backfilled (#{campaign.body_markdown.length} chars). body_mjml left intact for diff comparison."
    end
  end

  desc "After verifying the markdown render matches, clear Campaign #3's legacy body_mjml so markdown is the sole source of truth."
  task clear_campaign_3_body_mjml: :environment do
    campaign = Campaign.find_by(id: 3)
    if campaign.nil?
      puts "[campaigns:clear_campaign_3_body_mjml] Campaign #3 not found."
    elsif campaign.body_markdown.blank?
      abort "[campaigns:clear_campaign_3_body_mjml] Refusing to clear body_mjml when body_markdown is blank."
    else
      campaign.update_columns(body_mjml: nil)
      puts "[campaigns:clear_campaign_3_body_mjml] Campaign #3.body_mjml cleared. Markdown is now the sole source."
    end
  end

  # Chrome-only template: header logo + {{body}} placeholder + footer with
  # unsubscribe + physical address (CAN-SPAM). The repeated newsletter content
  # lives in Campaign#body_markdown, not here.
  def chrome_only_template
    <<~MJML
      <mjml>
        <mj-head>
          <mj-attributes>
            <mj-all font-family="Helvetica, Arial, sans-serif" />
            <mj-text font-size="15px" line-height="1.55" color="#1f2937" />
            <mj-section padding="0 0" />
          </mj-attributes>
          <mj-style>
            h1 { font-size: 24px; line-height: 1.3; margin: 0 0 12px; }
            h2 { font-size: 20px; line-height: 1.3; margin: 24px 0 10px; color: #111827; }
            h3 { font-size: 17px; line-height: 1.35; margin: 20px 0 8px; color: #111827; }
            a { color: #2563eb; text-decoration: underline; }
            blockquote { border-left: 3px solid #e5e7eb; margin: 12px 0; padding: 4px 12px; color: #4b5563; }
            ul, ol { padding-left: 20px; margin: 8px 0; }
            li { margin: 4px 0; }
          </mj-style>
        </mj-head>
        <mj-body background-color="#f3f4f6" width="640px">
          <mj-section background-color="#ffffff" padding="24px 24px 12px">
            <mj-column>
              <mj-text align="left" font-size="20px" font-weight="700" color="#111827">
                InfluenceKit
              </mj-text>
              <mj-text align="left" color="#6b7280" font-size="13px">
                The brand-side newsletter
              </mj-text>
            </mj-column>
          </mj-section>

          <mj-section background-color="#ffffff" padding="0 24px 24px">
            <mj-column>
              <mj-text>
                Hi {{first_name}},
              </mj-text>
            </mj-column>
          </mj-section>

          {{body}}

          <mj-section background-color="#ffffff" padding="24px">
            <mj-column>
              <mj-divider border-color="#e5e7eb" border-width="1px" padding="0 0 16px" />
              <mj-text font-size="12px" color="#6b7280" line-height="1.6">
                You're receiving this because you have an InfluenceKit account. <br />
                <a href="{{unsubscribe_url}}">Unsubscribe</a> from these updates at any time.<br /><br />
                InfluenceKit · 1234 Example St · Madison, WI 53703 · USA
              </mj-text>
            </mj-column>
          </mj-section>
        </mj-body>
      </mjml>
    MJML
  end

  # The "April Updates" newsletter content as markdown. H2 per subsection.
  # CTA arrows are markdown links — the actual destination URLs are TODOs
  # that the InfluenceKit team will fill in by editing the campaign in-app.
  def april_updates_markdown
    <<~MARKDOWN
      ## April Updates from InfluenceKit

      A quick roundup of what we shipped this month — the things you asked
      for, the upgrades to the deliverable engine, and a couple of new
      reports we think you'll like.

      ## Brand Mentions

      You can now track unprompted mentions of your brand from any creator,
      not just the ones in your campaigns. We pull from the public social
      graph and surface them in a single feed so you can spot the organic
      moment before it peaks.

      [View Your Brand Mentions →](https://app.influencekit.com/TODO-brand-mentions)

      ## Deliverable Diagnostics

      Stuck deliverables now show a clear reason — expired tokens, removed
      posts, platform throttles — with a one-click fix where possible. No
      more guessing why a story didn't refresh.

      [See Diagnostics →](https://app.influencekit.com/TODO-diagnostics)

      ## Campaign Reports v2

      We rebuilt the reporting layer from the ground up. Faster loads,
      better aggregations across creators, and a new CSV export that mirrors
      exactly what you see in the UI.

      [Open a Campaign Report →](https://app.influencekit.com/TODO-reports)

      ## Coming Soon

      We're working on creator-side benchmarking — so when you negotiate
      with a creator, you'll see their performance against industry medians
      for their tier and category. Early access opens in May.

      [Get on the Waitlist →](https://app.influencekit.com/TODO-waitlist)

      Thanks for being a customer. As always, hit reply if you have
      questions or want to push back on anything.

      — The InfluenceKit team
    MARKDOWN
  end
end
