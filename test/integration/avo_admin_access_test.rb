require "test_helper"

# Locks in the contract described in config/routes/avo.rb: the Avo admin at
# /admin/avo is only reachable when the signed-in user's email is in the
# BulletTrain DEVELOPER_EMAILS allowlist (User#developer?). Self-hosters
# override DEVELOPER_EMAILS on their own boxes to grant access.
#
# This is integration-level on purpose — Avo is mounted as a Rails engine
# inside a Devise authenticate-on-mount constraint, and the controller-level
# tests in test/controllers/ don't exercise the engine routing path.
class AvoAdminAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Stash + restore so we don't leak admin scope into sibling tests, which
  # rely on @example.com factory users being plain non-admin signups.
  setup do
    @original_developer_emails = ENV["DEVELOPER_EMAILS"]
  end

  teardown do
    if @original_developer_emails.nil?
      ENV.delete("DEVELOPER_EMAILS")
    else
      ENV["DEVELOPER_EMAILS"] = @original_developer_emails
    end
  end

  test "non-admin users are bounced from /admin/avo" do
    # An allowlist that doesn't include the factory user's email.
    ENV["DEVELOPER_EMAILS"] = "bruno@influencekit.com"
    user = create(:onboarded_user)
    refute user.developer?, "factory user should not be on the DEVELOPER_EMAILS allowlist"

    sign_in user
    get "/admin/avo"

    # The Devise `authenticate` constraint in config/routes/avo.rb fails for
    # this user, so the engine isn't mounted for them and Rails falls
    # through to the default 404 route. (We accept either a redirect or a
    # not-found response — both mean "you can't see the admin.")
    assert_includes [302, 404], response.status,
      "Expected non-admin to be redirected or 404'd from /admin/avo, got #{response.status}"
  end

  test "an admin user reaches /admin/avo home and a resource page" do
    user = create(:onboarded_user)
    # Add the factory user's email to the allowlist for the duration of this
    # test. BulletTrain's `developer?` uses `email_was` so we set it after
    # the user is created.
    ENV["DEVELOPER_EMAILS"] = user.email
    assert user.reload.developer?, "user should match the DEVELOPER_EMAILS allowlist"

    sign_in user

    # The operator dashboard is wired as the home page in
    # config/initializers/avo.rb, so /admin/avo redirects to it. Follow the
    # redirect so we land on a real rendered page rather than the 302.
    get "/admin/avo"
    follow_redirect! if response.redirect?
    assert_response :success,
      "Admin should reach the Avo home dashboard, got #{response.status}"

    # And the Users resource index should also render — spot check that the
    # resources aren't missing required model lookups.
    get "/admin/avo/resources/users"
    assert_response :success,
      "Admin should reach the Users resource index, got #{response.status}"
  end

  test "an unauthenticated visitor cannot reach /admin/avo" do
    ENV["DEVELOPER_EMAILS"] = "anyone@example.com"
    get "/admin/avo"

    # Devise's `authenticate :user, ...` constraint fails before checking
    # the lambda when there's no signed-in user, so we get the same router
    # fall-through (redirect-to-sign-in or 404 depending on how Devise is
    # wired). The contract: not-success.
    assert_not response.successful?,
      "Unauthenticated visitor should not get a 200 from /admin/avo (got #{response.status})"
  end
end
