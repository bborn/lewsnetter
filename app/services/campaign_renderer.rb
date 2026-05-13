# Renders a Campaign's body into per-recipient HTML + text, performing
# variable substitution against the Subscriber's name / email / custom_attributes.
#
# Two authoring paths are supported:
#
#   1. Markdown body (preferred): `campaign.body_markdown` is rendered to HTML
#      with commonmarker (SAFE — no raw HTML pass-through) and substituted into
#      the email template's `{{body}}` placeholder. If the template has no
#      `{{body}}` placeholder, the rendered HTML is appended at the end of the
#      template's `<mj-body>` as a final `<mj-section>`.
#   2. Raw MJML body (legacy): `campaign.body_mjml` is used directly. This is
#      kept working so existing campaigns don't break, but is no longer the
#      foregrounded authoring path.
#
# After body resolution the pipeline is the same in both paths:
#
#   - Substitute {{first_name}} / {{last_name}} / {{email}} / {{external_id}} /
#     {{unsubscribe_url}} and any top-level key from subscriber.custom_attributes.
#   - Compile MJML → HTML via mjml-rails.
#   - Inline CSS with Premailer (so Outlook + Gmail don't strip <style> blocks).
#   - Return html + a stripped plain-text alternative + the personalized
#     subject + preheader.
#
# Unknown variables (e.g. {{foo}} where the subscriber has no `foo` attribute)
# are intentionally left in place so a user sending a test to themselves
# notices the template is broken and fixes it.
class CampaignRenderer
  Result = Struct.new(:html, :text, :subject, :preheader, keyword_init: true)

  BODY_PLACEHOLDER = "{{body}}".freeze

  def initialize(campaign:, subscriber:)
    @campaign = campaign
    @subscriber = subscriber
  end

  def call
    html = render_html
    Result.new(
      html: html,
      text: strip_to_text(html),
      subject: substitute(@campaign.subject.to_s),
      preheader: substitute(@campaign.preheader.to_s)
    )
  end

  private

  def render_html
    @render_html ||= begin
      mjml_source = substitute(resolved_mjml)
      raw_html = Mjml::Parser.new(nil, mjml_source).render
      Premailer.new(
        raw_html,
        with_html_string: true,
        warn_level: Premailer::Warnings::SAFE
      ).to_inline_css
    end
  end

  # Resolves the final MJML source to compile.
  # - Markdown path: render markdown → HTML, substitute into template's
  #   `{{body}}` placeholder (or append if missing).
  # - Legacy path: use `campaign.body_mjml`, falling back to the template body.
  def resolved_mjml
    if @campaign.body_markdown.present?
      template_mjml = @campaign.email_template&.mjml_body
      raise "Campaign #{@campaign.id} has body_markdown but no email_template to host {{body}}" if template_mjml.blank?

      # Substitute variables in the markdown source BEFORE compiling to HTML.
      # Commonmarker URL-encodes any `{` and `}` it finds in an href, so a link
      # like `[Open](https://{{subdomain}}.example.com)` would become
      # `https://%7B%7Bsubdomain%7D%7D.example.com` and the later substitute
      # pass couldn't match the encoded form. Substituting first lets URL
      # placeholders survive markdown rendering as real values.
      # Plain-text `{{var}}` in body copy still works either way (Commonmarker
      # passes braces through outside of URL contexts), and the later
      # substitute on the full MJML is a safe no-op on already-replaced vars.
      substituted_markdown = substitute(@campaign.body_markdown)
      body_mj_section = markdown_to_mj_section(substituted_markdown)
      inject_body(template_mjml, body_mj_section)
    else
      source = @campaign.body_mjml.presence || @campaign.email_template&.mjml_body
      raise "Campaign #{@campaign.id} has no body_markdown, no body_mjml and no email_template body" if source.blank?
      source
    end
  end

  # Wraps the markdown-rendered HTML in an `<mj-section><mj-column><mj-text>`
  # so it slots into a template body without breaking MJML structure.
  def markdown_to_mj_section(markdown)
    html = markdown_to_html(markdown)
    <<~MJML
      <mj-section>
        <mj-column>
          <mj-text>
            #{html}
          </mj-text>
        </mj-column>
      </mj-section>
    MJML
  end

  def markdown_to_html(markdown)
    # SAFE: no raw HTML pass-through. Users author markdown, not HTML.
    # GFM-style features: tables, strikethrough, autolinks. No unsafe HTML.
    # `header_ids: nil` disables the auto-anchor `<a class="anchor">` injection
    # — email clients don't have a URL bar to copy fragment links from, and the
    # extra `<a>` inside headings breaks Premailer's style inlining for headers.
    Commonmarker.to_html(markdown.to_s, options: {
      parse: {smart: true},
      render: {hardbreaks: false, unsafe: false},
      extension: {header_ids: nil}
    })
  end

  # Substitutes the body MJML section into the template at `{{body}}`. If the
  # template doesn't include the placeholder, appends the section just before
  # `</mj-body>` so the body still renders (and the user notices the missing
  # placeholder and can add it).
  def inject_body(template_mjml, body_mj_section)
    if template_mjml.include?(BODY_PLACEHOLDER)
      template_mjml.sub(BODY_PLACEHOLDER, body_mj_section)
    elsif template_mjml.include?("</mj-body>")
      template_mjml.sub("</mj-body>", "#{body_mj_section}\n</mj-body>")
    else
      # Template has no </mj-body> — fall back to concatenating. This is
      # almost certainly broken MJML but we'd rather render something and
      # let the user fix it than swallow the error silently.
      "#{template_mjml}\n#{body_mj_section}"
    end
  end

  def substitute(string)
    return string if string.blank?
    vars = variables
    # Match {{key}} or {{key|fallback}} with optional whitespace around the key
    # and pipe. Fallback can contain anything except '}' so it stops at the
    # closing braces. Comparisons use the symbol form of the key.
    #
    # Behavior:
    #   - {{known}} with a value → value
    #   - {{known}} with blank value → "" (existing behavior — substitute even if empty)
    #   - {{unknown}} (no fallback, key not in vars) → left in place so the
    #     user notices the broken template
    #   - {{key|fallback}} → fallback when key resolves blank (including unknown keys)
    string.gsub(/\{\{\s*(\w+)\s*(?:\|([^}]*))?\s*\}\}/) do |match|
      key = $1.to_sym
      fallback = $2
      has_fallback = !fallback.nil?
      if vars.key?(key)
        value = vars[key]
        if value.to_s.strip.empty? && has_fallback
          fallback.to_s.strip
        else
          value.to_s
        end
      elsif has_fallback
        fallback.to_s.strip
      else
        # Unknown key, no fallback — leave the token intact.
        match
      end
    end
  end

  def variables
    name = @subscriber.name.to_s.strip
    first, last = name.split(/\s+/, 2)

    base = {
      first_name: first.to_s,
      last_name: last.to_s,
      email: @subscriber.email.to_s,
      external_id: @subscriber.external_id.to_s,
      unsubscribe_url: unsubscribe_url_for(@subscriber)
    }

    custom = (@subscriber.custom_attributes || {}).each_with_object({}) do |(k, v), h|
      h[k.to_sym] = v
    end

    base.merge(custom)
  end

  # Resolves the unsubscribe URL for a subscriber. For persisted subscribers
  # this is a signed GlobalID. For the in-memory placeholder subscriber used
  # in preview mode (no persisted record, so no GlobalID) we substitute a
  # readable placeholder so the preview doesn't blow up — the author sees the
  # link shape without a real signed token.
  def unsubscribe_url_for(subscriber)
    return "#preview-unsubscribe" unless subscriber.persisted?
    UnsubscribeUrlHelper.url_for(subscriber: subscriber)
  end

  def strip_to_text(html)
    ActionView::Base.full_sanitizer.sanitize(html.to_s).gsub(/\s+/, " ").strip
  end
end
