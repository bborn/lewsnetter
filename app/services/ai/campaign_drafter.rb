# frozen_string_literal: true

module AI
  # Drafts a campaign from a brief: returns 5 subject candidates (each with a
  # short rationale), a preheader, a complete MJML body, and a suggested send
  # time. Pulls last-10 sent campaigns from the team as voice samples and
  # optionally folds in the target segment's description + tone hint.
  #
  # In stub mode, returns a deterministic boilerplate draft.
  class CampaignDrafter < Base
    SubjectCandidate = Struct.new(:subject, :rationale, keyword_init: true)

    Draft = Struct.new(
      :subject_candidates, :preheader, :mjml_body, :suggested_send_time,
      :errors, :stub,
      keyword_init: true
    ) do
      def success?
        errors.blank? && mjml_body.present? && subject_candidates.present?
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

      mjml = parsed["mjml_body"].to_s
      unless valid_mjml?(mjml)
        return stub_draft(errors: ["LLM did not return a valid MJML document"])
      end

      Draft.new(
        subject_candidates: candidates.presence || stub_subjects,
        preheader: parsed["preheader"].to_s,
        mjml_body: mjml,
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
          "mjml_body": "<mjml><mj-body>...</mj-body></mjml>",
          "suggested_send_time": "Tuesday 10am Eastern (or similar)"
        }

        Voice samples — the last 10 campaigns this team sent (subject + body excerpt):
        #{voice_samples_block.presence || "(no prior campaigns; default to a friendly, clear tone)"}

        #{segment_block}
        #{tone_block}

        Requirements:
        - MJML must be a complete document wrapped in <mjml><mj-body>…</mj-body></mjml>.
        - Use <mj-section>, <mj-column>, <mj-text>, <mj-button> as appropriate.
        - Keep it short: one hero, one body paragraph, one CTA.
        - 5 distinct subject candidates exploring different angles.
      PROMPT
    end

    def user_prompt
      "Brief:\n#{@brief}"
    end

    def voice_samples_block
      @team.campaigns.where(status: "sent").order(sent_at: :desc).limit(10).map { |c|
        excerpt = c.body_mjml.to_s.gsub(/<[^>]+>/, " ").squish[0, 200]
        "- subject: #{c.subject.inspect}\n  excerpt: #{excerpt.inspect}"
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

    def valid_mjml?(mjml)
      return false if mjml.blank?
      mjml.include?("<mjml") && mjml.include?("<mj-body") &&
        mjml.include?("</mj-body>") && mjml.include?("</mjml>")
    end

    def stub_draft(errors: [])
      Draft.new(
        subject_candidates: stub_subjects,
        preheader: "A quick note from #{@team.name}",
        mjml_body: stub_mjml_body,
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

    def stub_mjml_body
      <<~MJML
        <mjml>
          <mj-body>
            <mj-section>
              <mj-column>
                <mj-text font-size="20px" font-weight="bold">
                  Hello from #{@team.name}
                </mj-text>
                <mj-text>
                  This is a stub-mode draft generated without an LLM. Replace
                  this body with your actual campaign content, or set
                  ANTHROPIC_API_KEY to get a real AI draft based on your brief.
                </mj-text>
                <mj-button href="https://example.com">
                  Call to action
                </mj-button>
              </mj-column>
            </mj-section>
          </mj-body>
        </mjml>
      MJML
    end
  end
end
