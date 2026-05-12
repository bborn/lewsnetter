# Renders a Campaign's MJML body into per-recipient HTML + text, performing
# variable substitution against the Subscriber's name / email / custom_attributes.
#
# The pipeline:
#
#   1. Pull MJML source from campaign.body_mjml (or fall back to the template).
#   2. Substitute {{first_name}} / {{last_name}} / {{email}} / {{external_id}}
#      and any top-level key from subscriber.custom_attributes.
#   3. Compile MJML → HTML via mjml-rails.
#   4. Inline CSS with Premailer (so Outlook + Gmail don't strip <style> blocks).
#   5. Return html + a stripped plain-text alternative + the personalized
#      subject + preheader.
#
# Unknown variables (e.g. {{foo}} where the subscriber has no `foo` attribute)
# are intentionally left in place so a user sending a test to themselves
# notices the template is broken and fixes it.
class CampaignRenderer
  Result = Struct.new(:html, :text, :subject, :preheader, keyword_init: true)

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
      mjml_source = substitute(body_mjml)
      raw_html = Mjml::Parser.new(nil, mjml_source).render
      Premailer.new(
        raw_html,
        with_html_string: true,
        warn_level: Premailer::Warnings::SAFE
      ).to_inline_css
    end
  end

  def body_mjml
    source = @campaign.body_mjml.presence || @campaign.email_template&.mjml_body
    raise "Campaign #{@campaign.id} has no body_mjml and no email_template body" if source.blank?
    source
  end

  def substitute(string)
    return string if string.blank?
    variables.reduce(string) do |out, (key, value)|
      out.gsub("{{#{key}}}", value.to_s)
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
      unsubscribe_url: UnsubscribeUrlHelper.url_for(subscriber: @subscriber)
    }

    custom = (@subscriber.custom_attributes || {}).each_with_object({}) do |(k, v), h|
      h[k.to_sym] = v
    end

    base.merge(custom)
  end

  def strip_to_text(html)
    ActionView::Base.full_sanitizer.sanitize(html.to_s).gsub(/\s+/, " ").strip
  end
end
