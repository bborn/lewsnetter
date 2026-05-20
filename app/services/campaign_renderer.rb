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

  # Optional `delivery:` arg enables open-pixel injection + click rewriting.
  # When nil (preview / test-render paths), the email is returned without
  # tracking markup so previews don't pollute stats and don't crash on the
  # in-memory placeholder subscriber. SesSender always passes a real Delivery
  # for production sends.
  def initialize(campaign:, subscriber:, delivery: nil)
    @campaign = campaign
    @subscriber = subscriber
    @delivery = delivery
  end

  def call
    html = render_html
    html = inject_tracking(html) if @delivery
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

  # ──────────────────────────────────────────────────────────────────────
  # Tracking injection (Phase 2)
  # ──────────────────────────────────────────────────────────────────────
  # Walks the final HTML, rewrites every trackable <a href> to go through
  # the click redirect controller, and appends a 1x1 open pixel just before
  # </body>. We parse with Nokogiri rather than regexing the HTML because
  # MJML's output has nested anchors inside table cells and a regex would
  # mis-handle attributes that contain '>'.
  def inject_tracking(html)
    doc = Nokogiri::HTML5(html)
    rewrite_links(doc)
    append_pixel(doc)
    # `to_html` re-serializes back to a full document; for email we want a
    # well-formed <html><body>… same as Premailer produced, so this is fine.
    doc.to_html
  rescue => e
    # Never let tracking injection break a send. Log + return the original
    # HTML so the recipient gets the email (just without analytics).
    Rails.logger.warn(
      "[CampaignRenderer] tracking injection failed for delivery=#{@delivery&.id}: " \
      "#{e.class}: #{e.message}"
    )
    html
  end

  def rewrite_links(doc)
    doc.css("a[href]").each do |a|
      href = a["href"].to_s
      next unless trackable_link?(href)
      a["href"] = click_tracking_url_for(href)
    end
  end

  def append_pixel(doc)
    body = doc.at_css("body") || doc.root
    return unless body

    img = Nokogiri::XML::Node.new("img", doc)
    img["src"] = open_tracking_url
    img["width"] = "1"
    img["height"] = "1"
    img["alt"] = ""
    img["style"] = "display:none;border:0;height:1px;width:1px"
    body.add_child(img)
  end

  # Skip:
  # - mailto: / tel: / sms: (no click to track)
  # - fragment-only links (#section) — they don't leave the email
  # - absolute unsubscribe URLs (we don't want a tracking hop on the
  #   List-Unsubscribe link; that path needs to stay exactly what we put in
  #   the List-Unsubscribe header)
  # - empty hrefs
  def trackable_link?(href)
    return false if href.blank?
    return false if href.start_with?("#")
    return false if href =~ /\A(mailto|tel|sms):/i
    return false if href.include?("/unsubscribe/")
    true
  end

  def click_tracking_url_for(original_url)
    token = @delivery.signed_click_token(url: original_url)
    Rails.application.routes.url_helpers.tracking_click_url(token, **default_url_options)
  end

  def open_tracking_url
    Rails.application.routes.url_helpers.tracking_open_url(@delivery.tracking_token, **default_url_options)
  end

  # URL options for the open-pixel + click-tracking absolute URLs.
  #
  # The host is resolved through the SAME single resolver the unsubscribe
  # link uses (UnsubscribeUrlHelper.host_for): when the team has configured
  # a branded email subdomain, the pixel + click URLs share that host with
  # the unsubscribe link; otherwise both fall back to the app-wide default
  # (BASE_URL → action_mailer.default_url_options[:host]). One host per
  # email — better branding and a mild deliverability win.
  def default_url_options
    {
      host: tracking_host,
      # Hard-default protocol so URLs include https:// in environments where
      # default_url_options doesn't carry a protocol (test, sometimes dev).
      protocol: "https"
    }
  end

  # The hostname this team's email links use. Delegates to the shared
  # resolver so unsubscribe + pixel + click never drift apart.
  def tracking_host
    UnsubscribeUrlHelper.host_for(team: @campaign.team) || "localhost"
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

  # Render via Liquid (https://shopify.github.io/liquid/). Standard syntax:
  #   {{ var }}
  #   {{ var | default: "fallback" }}
  #   {{ var | upcase }}
  #   {% if var %}…{% endif %}
  #
  # Backwards-compat shim: legacy `{{key|fallback}}` (Lewsnetter's old
  # custom syntax, no spaces, fallback as a bare word) is rewritten to
  # Liquid's `{{ key | default: "fallback" }}` BEFORE Liquid parses.
  # This means existing campaign bodies keep working without a one-shot
  # migration.
  #
  # Lewsnetter convention: unknown variables (no fallback) stay in place
  # so the user notices the broken template. Liquid's default is to
  # render unknowns as empty — we pre-fill missing vars with their own
  # `{{name}}` literal so the output round-trips.
  def substitute(string)
    return string if string.blank?

    source = rewrite_legacy_fallback_syntax(string)
    template = Liquid::Template.parse(source, error_mode: :lax)
    vars = string_keyed_variables
    fill_unknown_vars_with_literals!(vars, template)
    template.render(vars)
  rescue Liquid::SyntaxError => e
    Rails.logger.warn("[CampaignRenderer] Liquid parse failed: #{e.message} — leaving source unchanged")
    string
  end

  # Rewrite legacy `{{var|fallback}}` → `{{ var | default: "fallback" }}`.
  #
  # The pattern is intentionally strict: NO whitespace around the pipe and
  # NO whitespace in the fallback word. This distinguishes Lewsnetter's
  # original syntax (always written compact, e.g. `{{subdomain|app}}`) from
  # standard Liquid (`{{ var | upcase }}` or `{{ var | default: "x" }}`),
  # which we let Liquid parse natively.
  def rewrite_legacy_fallback_syntax(string)
    string.gsub(/\{\{\s*(\w+)\|([^}|:\s][^}|:]*?)\s*\}\}/) do
      key, fallback = $1, $2.strip
      escaped = fallback.gsub('\\', '\\\\').gsub('"', '\\"')
      %({{ #{key} | default: "#{escaped}" }})
    end
  end

  # Liquid renders unknown variables as empty by default. Lewsnetter's
  # convention is to leave them as `{{name}}` so the author notices.
  # Walk the parsed template's variable references; for any name that
  # isn't already in `vars` (and isn't a Liquid built-in like `forloop`),
  # set vars[name] = "{{name}}" so it round-trips.
  def fill_unknown_vars_with_literals!(vars, template)
    return unless template.root.respond_to?(:nodelist)
    referenced_names(template.root).each do |name|
      vars[name] = "{{#{name}}}" unless vars.key?(name)
    end
  end

  # Walks the parsed Liquid template and returns the names of variable
  # references that have NO default filter. Those are the ones we want to
  # round-trip as `{{name}}` literals so the author notices the broken
  # template. Variables with a `default:` filter are intentionally left
  # alone — Liquid's default filter handles missing/empty values.
  def referenced_names(node, names = Set.new)
    if node.is_a?(Liquid::Variable)
      has_default = Array(node.filters).any? { |f| Array(f).first.to_s == "default" }
      first = node.name
      if !has_default && first.respond_to?(:name)
        names << first.name
      end
    elsif node.respond_to?(:nodelist) && node.nodelist
      node.nodelist.each { |child| referenced_names(child, names) }
    end
    names
  end

  def string_keyed_variables
    variables.transform_keys(&:to_s)
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
