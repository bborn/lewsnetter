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
      # Guard so stub_markdown — which `call` falls back to when @campaign is
      # nil — doesn't recrash here and defeat its own nil-guard.
      return {} unless @campaign
      # Engagement (opened/clicked/bounced/complained) is NOT stored on the
      # campaign's `stats` column — that's send-side only (sent/failed/…). Merge
      # in the per-recipient delivery_stats so both the LLM prompt and the stub
      # summary report real open/click/bounce numbers instead of zeros.
      send_side = (@campaign.stats || {}).to_h.stringify_keys
      # Add only the engagement metrics (not sent/failed — the send-side counts
      # stay authoritative for the recipient total).
      engagement = engagement_stats.slice(
        "delivered", "opened", "clicked", "bounced", "complained", "unsubscribed", "click_total"
      )
      send_side.merge(engagement)
    end

    def engagement_stats
      @campaign.delivery_stats.stringify_keys
    rescue => e
      Rails.logger.warn("[AI::PostSendAnalyst] delivery_stats failed: #{e.class}: #{e.message}")
      {}
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
        # Some stats values are non-numeric (e.g. `errors` is an Array). Only
        # average the numeric ones — calling `.to_f` on an Array raises, and the
        # rescue in `call` silently turned that into stub-mode output.
        values = prior.map { |row| row[k] }.grep(Numeric)
        acc[k] = (values.sum.to_f / values.size).round(2) if values.any?
      end
    end

    def stub_markdown
      s = stats
      sent = s["sent"] || 0
      opens = s["opened"] || 0
      clicks = s["clicked"] || 0
      bounces = s["bounced"] || 0
      complaints = s["complained"] || 0

      open_rate = percent(opens, sent)
      click_rate = percent(clicks, sent)
      bounce_rate = percent(bounces, sent)
      complaint_rate = percent(complaints, sent)

      subject = @campaign&.subject.to_s.presence || "(no subject)"
      sent_at = @campaign&.sent_at&.to_fs(:long) || "an unknown time"

      # Only blame a missing key when the LLM genuinely isn't configured. When
      # it IS configured, this fallback means the AI call failed for some other
      # reason — don't send the author chasing an API key that's already set.
      note = if Llm::Configuration.current.usable?
        "*Automated summary — the AI postmortem couldn't be generated this time, so here are the numbers directly.*"
      else
        "*Stub-mode analysis — set `ANTHROPIC_API_KEY` for a real LLM postmortem.*"
      end

      <<~MARKDOWN
        #{note}

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
