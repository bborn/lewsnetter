require "test_helper"

# Regression test for B5 (deep QA 2026-05-13):
# The four custom Stimulus controllers must end up in the compiled JS bundle.
# Previously a missing transitive dep (easymde absent from node_modules) caused
# the glob-import build step to silently emit an empty bundle — shipping a
# JS-less app to production. We switched to explicit imports + registers in
# `app/javascript/controllers/index.js`; this test asserts the controllers
# survive the next compilation.
#
# Skipped if the bundle hasn't been compiled (e.g. fresh CI worker before
# `yarn build`). When the bundle IS present, all four identifiers MUST appear.
class JavascriptBundleTest < ActiveSupport::TestCase
  BUNDLE_PATH = Rails.root.join("app", "assets", "builds", "application.js").freeze

  CUSTOM_CONTROLLER_IDENTIFIERS = %w[
    segments-builder
    markdown-editor
    ai-drafter
    campaign-preview
  ].freeze

  test "compiled bundle exposes every custom Stimulus controller identifier" do
    skip "application.js bundle not present — run `yarn build` first" unless BUNDLE_PATH.exist?

    contents = File.read(BUNDLE_PATH)
    CUSTOM_CONTROLLER_IDENTIFIERS.each do |identifier|
      assert_includes contents, identifier,
        "Stimulus controller `#{identifier}` is missing from the compiled JS bundle. " \
        "Check `app/javascript/controllers/index.js` and `yarn build` output."
    end
  end

  test "compiled bundle contains EasyMDE for the markdown editor" do
    skip "application.js bundle not present — run `yarn build` first" unless BUNDLE_PATH.exist?

    contents = File.read(BUNDLE_PATH)
    assert_match(/EasyMDE|easymde/i, contents,
      "EasyMDE is missing from the bundle — the markdown editor will not initialize.")
  end
end
