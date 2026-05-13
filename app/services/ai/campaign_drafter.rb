# frozen_string_literal: true

module AI
  # Drafts a campaign from a brief: returns 5 subject candidates (each with a
  # short rationale), a preheader, a markdown body (the new authoring path),
  # and a suggested send time. Pulls last-10 sent campaigns from the team as
  # voice samples and optionally folds in the target segment's description +
  # tone hint.
  #
  # The drafter returns markdown — not MJML — because the markdown body is
  # composed into the email template's `{{body}}` placeholder at render time
  # by CampaignRenderer. We also surface `mjml_body` for legacy callers that
  # still want the raw MJML form (built from the same content), but new code
  # should consume `markdown_body`.
  #
  # In stub mode, returns a deterministic boilerplate draft.
  class CampaignDrafter < Base
    SubjectCandidate = Struct.new(:subject, :rationale, keyword_init: true)

    Draft = Struct.new(
      :subject_candidates, :preheader, :markdown_body, :mjml_body,
      :suggested_send_time, :errors, :stub,
      keyword_init: true
    ) do
      def success?
        errors.blank? && markdown_body.present? && subject_candidates.present?
      end

      def stub?
        !!stub
      end

      def primary_subject
        subject_candidates.first&.subject
      end
    end

    def initialize(team:, brief:, segment: nil, tone: nil)
      super()
      @team = team
      @brief = brief.to_s.strip
      @segment = segment
      @tone = tone.to_s.strip.presence
    end

    def call
      return stub_draft if stub_mode?
      return stub_draft if @brief.blank?

      raw = ask_llm(system: system_prompt, user: user_prompt)
      parsed = parse_json(raw)
      return stub_draft(errors: ["LLM did not return valid JSON"]) unless parsed

      candidates = Array(parsed["subject_candidates"]).map do |row|
        SubjectCandidate.new(
          subject: row["subject"].to_s,
          rationale: row["rationale"].to_s
        )
      end
      candidates = candidates.reject { |c| c.subject.blank? }

      markdown = parsed["markdown_body"].to_s
      if markdown.blank?
        return stub_draft(errors: ["LLM did not return a markdown_body"])
      end

      Draft.new(
        subject_candidates: candidates.presence || stub_subjects,
        preheader: parsed["preheader"].to_s,
        markdown_body: markdown,
        mjml_body: markdown_to_mjml_fallback(markdown),
        suggested_send_time: parsed["suggested_send_time"].to_s.presence || "Tuesday 10am Eastern",
        errors: [],
        stub: false
      )
    rescue => e
      Rails.logger.warn("[AI::CampaignDrafter] #{e.class}: #{e.message}")
      stub_draft(errors: ["AI draft failed: #{e.message}"])
    end

    private

    def system_prompt
      <<~PROMPT
        You are drafting an email campaign for team "#{@team.name}". The user
        will give you a brief — usually 5 bullets. Output a complete draft as
        JSON only, no surrounding prose, with this shape:

        {
          "subject_candidates": [
            {"subject": "...", "rationale": "why this subject works"},
            ... (exactly 5 candidates)
          ],
          "preheader": "the inbox preview text under the subject",
          "markdown_body": "## A heading\\n\\nParagraph text…\\n\\n- list item\\n\\n[Call to action →](https://example.com)",
          "suggested_send_time": "Tuesday 10am Eastern (or similar)"
        }

        Voice samples — the last 10 campaigns this team sent (subject + body excerpt):
        #{voice_samples_block.presence || "(no prior campaigns; default to a friendly, clear tone)"}

        #{segment_block}
        #{tone_block}

        Requirements:
        - `markdown_body` is MARKDOWN, not HTML and not MJML. The email layout
          (header, footer, unsubscribe link) is provided by a separate
          template — your body fills the content area.
        - Use ## for section headings (H2). Skip H1.
        - Keep it short: one hero paragraph, 2-3 body paragraphs, one CTA link.
        - CTAs are markdown links: `[Read more →](https://example.com)`
        - 5 distinct subject candidates exploring different angles.
        - Output JSON only. No code fences, no surrounding prose.
      PROMPT
    end

    def user_prompt
      "Brief:\n#{@brief}"
    end

    def voice_samples_block
      @team.campaigns.where(status: "sent").order(sent_at: :desc).limit(10).map { |c|
        # Prefer the markdown source if available, fall back to the MJML
        # stripped down to its text content for legacy campaigns.
        excerpt = if c.body_markdown.present?
          c.body_markdown.to_s
        else
          c.body_mjml.to_s.gsub(/<[^>]+>/, " ").squish
        end
        "- subject: #{c.subject.inspect}\n  excerpt: #{excerpt[0, 200].inspect}"
      }.join("\n")
    end

    def segment_block
      return "" unless @segment
      desc = @segment.natural_language_source.presence ||
        @segment.try(:human_description).presence ||
        @segment.name
      "Target segment: #{desc}"
    end

    def tone_block
      return "" if @tone.blank?
      "Tone: #{@tone}"
    end

    # Builds a complete MJML document around the markdown body's HTML render.
    # Only used as a fallback for legacy callers (e.g. anything still reading
    # `mjml_body` from the Draft struct). The render pipeline doesn't use this
    # — it composes the markdown body into the template's {{body}} at render
    # time via CampaignRenderer.
    def markdown_to_mjml_fallback(markdown)
      html = Commonmarker.to_html(markdown, options: {
        parse: {smart: true},
        render: {hardbreaks: false, unsafe: false},
        extension: {header_ids: nil}
      })
      <<~MJML
        <mjml>
          <mj-body>
            <mj-section>
              <mj-column>
                <mj-text>
                  #{html}
                </mj-text>
              </mj-column>
            </mj-section>
          </mj-body>
        </mjml>
      MJML
    rescue => _e
      # If commonmarker is unavailable at the call site, return a minimal MJML
      # stub. Callers that need real rendering should use the markdown_body
      # field directly.
      "<mjml><mj-body><mj-section><mj-column><mj-text>#{markdown}</mj-text></mj-column></mj-section></mj-body></mjml>"
    end

    def stub_draft(errors: [])
      Draft.new(
        subject_candidates: stub_subjects,
        preheader: "A quick note from #{@team.name}",
        markdown_body: stub_markdown_body,
        mjml_body: markdown_to_mjml_fallback(stub_markdown_body),
        suggested_send_time: "Tuesday 10am Eastern",
        errors: errors,
        stub: true
      )
    end

    def stub_subjects
      team_name = @team.name
      [
        SubjectCandidate.new(
          subject: "An update from #{team_name}",
          rationale: "Direct and personal — works when the brand has trust."
        ),
        SubjectCandidate.new(
          subject: "What's new this month",
          rationale: "Curiosity-led, low-pressure — good for monthly digests."
        ),
        SubjectCandidate.new(
          subject: "We've been working on something",
          rationale: "Teases value without giving it all away in the subject."
        ),
        SubjectCandidate.new(
          subject: "Quick read: 3 things from #{team_name}",
          rationale: "Sets expectations of length, gives reason to open."
        ),
        SubjectCandidate.new(
          subject: "Don't miss this from #{team_name}",
          rationale: "Higher urgency — use sparingly, only for real news."
        )
      ]
    end

    def stub_markdown_body
      <<~MARKDOWN
        ## Hello from #{@team.name}

        This is a stub-mode draft generated without an LLM. Replace this body
        with your actual campaign content, or set ANTHROPIC_API_KEY to get a
        real AI draft based on your brief.

        - Write in plain markdown
        - Headings, lists, **emphasis**, [links](https://example.com)
        - Keep it short and one-CTA

        [Call to action →](https://example.com)
      MARKDOWN
    end
  end
end
