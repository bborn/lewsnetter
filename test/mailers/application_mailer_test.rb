require "test_helper"

# Direct mailer-level coverage for the per-team unsubscribe subdomain
# behavior wired up in ApplicationMailer#set_list_unsubscribe_headers.
#
# The url-building logic itself is tested at the helper level in
# UnsubscribeUrlHelperTest — here we assert that the header an outgoing
# mail actually carries reflects the team's configured `unsubscribe_host`.
#
# ApplicationMailer's `before_action :set_list_unsubscribe_headers` reads
# either `headers[:subscriber]` or `@subscriber`. To exercise that callback
# at the mailer level we instantiate the mailer ourselves, pre-set the
# subscriber as an instance variable, and then invoke `process` so the
# `before_action` chain runs with state in place — same shape a future
# mailer would use if it assigned `@subscriber = params[:subscriber]` in
# its own `before_action` registered ahead of ApplicationMailer's.
class ApplicationMailerTest < ActionMailer::TestCase
  # Inline test-only mailer so we don't have to add anything to app/mailers/.
  class TestMailerForList < ApplicationMailer
    def hello
      mail(
        to: @subscriber.email,
        subject: "test",
        body: "hi",
        content_type: "text/plain"
      )
    end
  end

  setup do
    @team = create(:team)
    @subscriber = @team.subscribers.create!(
      email: "x@y.com",
      external_id: "mailer-#{SecureRandom.hex(4)}",
      name: "X",
      subscribed: true
    )
  end

  # Drives the mailer the same way ActionMailer::MessageDelivery does
  # internally, but with @subscriber pre-set on the instance so the
  # `before_action` chain in ApplicationMailer can read it.
  def deliver_for(subscriber)
    mailer = TestMailerForList.new
    mailer.instance_variable_set(:@subscriber, subscriber)
    mailer.process(:hello)
    mailer.message
  end

  test "List-Unsubscribe uses the team's unsubscribe_host when configured" do
    @team.build_ses_configuration(
      region: "us-east-1",
      status: "verified",
      unsubscribe_host: "email.influencekit.com"
    ).save!

    mail = deliver_for(@subscriber.reload)
    header = mail.header["List-Unsubscribe"].to_s

    assert_includes header, "https://email.influencekit.com/unsubscribe/",
      "expected branded host, got: #{header.inspect}"
    assert_includes header, "mailto:unsubscribe@email.influencekit.com",
      "expected branded mailto, got: #{header.inspect}"
    assert_equal "List-Unsubscribe=One-Click",
      mail.header["List-Unsubscribe-Post"].to_s
  end

  test "List-Unsubscribe falls back to the app default host when team has no unsubscribe_host" do
    assert_nil @team.ses_configuration

    default_host = Rails.application.config.action_mailer.default_url_options[:host]

    mail = deliver_for(@subscriber)
    header = mail.header["List-Unsubscribe"].to_s

    assert_includes header, "https://#{default_host}/unsubscribe/",
      "expected default host #{default_host.inspect}, got: #{header.inspect}"
    assert_includes header, "mailto:unsubscribe@#{default_host}",
      "expected default mailto, got: #{header.inspect}"
  end
end
