# frozen_string_literal: true

module AI
  # Generates a 3-paragraph post-send analysis (markdown) for a sent campaign.
  # In stub mode, returns a deterministic markdown summary built from the
  # campaign's own stats hash.
  class PostSendAnalyst < Base
    def initialize(campaign:)
      super()
      @campaign = campaign
    end

    # Returns a markdown String.
    def call
      return stub_markdown if stub_mode?
      return stub_markdown unless @campaign

      raw = ask_llm(system: system_prompt, user: user_prompt)
      return stub_markdown if raw.blank?
      raw.to_s
    rescue => e
      Rails.logger.warn("[AI::PostSendAnalyst] #{e.class}: #{e.message}")
      stub_markdown
    end

    private

    def system_prompt
      <<~PROMPT
        You are an email marketing analyst. Read this campaign's stats and
        copy, compare against the team's historical baseline, and produce a
        3-paragraph markdown postmortem with these sections (use ## headers):

        ## What worked
        ## What didn't
        ## What to try next

        Keep each section to 2-4 sentences. Be specific — cite the actual
        open/click/bounce/complaint rates. If data is missing or zero, say so
        plainly rather than making up numbers.
      PROMPT
    end

    def user_prompt
      <<~PROMPT
        Campaign: #{@campaign.subject.inspect}
        Sent at: #{@campaign.sent_at}
        Stats: #{stats.inspect}
        Historical baseline (team avg over last 10 campaigns): #{baseline.inspect}

        Subject: #{@campaign.subject}
        Preheader: #{@campaign.preheader}
        Body excerpt:
        #{(@campaign.body_mjml || "").to_s.gsub(/<[^>]+>/, " ").squish[0, 800]}
      PROMPT
    end

    def stats
      (@campaign.stats || {}).to_h
    end

    def baseline
      prior = @campaign.team.campaigns
        .where(status: "sent")
        .where.not(id: @campaign.id)
        .order(sent_at: :desc)
        .limit(10)
        .pluck(:stats)
      return {} if prior.empty?
      keys = prior.flat_map(&:keys).uniq
      keys.each_with_object({}) do |k, acc|
        values = prior.map { |row| row[k].to_f }.compact
        acc[k] = (values.sum / values.size).round(2) if values.any?
      end
    end

    def stub_markdown
      s = stats
      sent = s["sent"] || s[:sent] || 0
      opens = s["opens"] || s[:opens] || 0
      clicks = s["clicks"] || s[:clicks] || 0
      bounces = s["bounces"] || s[:bounces] || 0
      complaints = s["complaints"] || s[:complaints] || 0

      open_rate = percent(opens, sent)
      click_rate = percent(clicks, sent)
      bounce_rate = percent(bounces, sent)
      complaint_rate = percent(complaints, sent)

      subject = @campaign&.subject.to_s.presence || "(no subject)"
      sent_at = @campaign&.sent_at&.to_fs(:long) || "an unknown time"

      <<~MARKDOWN
        *Stub-mode analysis — set `ANTHROPIC_API_KEY` for a real LLM postmortem.*

        ## What worked

        Campaign **#{subject}** went out at #{sent_at} to #{sent} recipients.
        Open rate landed at **#{open_rate}%** and click-through at **#{click_rate}%**.
        Those numbers tell us the inbox placement was solid enough for opens to
        register, and a subset of the audience cared enough to click through.

        ## What didn't

        Bounce rate was **#{bounce_rate}%** and complaint rate **#{complaint_rate}%**.
        If either is climbing relative to your last few campaigns, suppression
        hygiene is the first place to look — old addresses, role accounts, and
        subscribers who haven't engaged in 90+ days drag deliverability down for
        everyone else on the list.

        ## What to try next

        Try a tighter segment for the next send — narrowing to recently engaged
        subscribers usually lifts open rate 2-4 points. Also consider A/B
        testing two subject lines on a 10% slice before committing to the full
        audience. Keep the cadence consistent so the inbox providers learn your
        sending pattern.
      MARKDOWN
    end

    def percent(num, denom)
      return 0.0 if denom.to_f.zero?
      ((num.to_f / denom.to_f) * 100).round(2)
    end
  end
end
