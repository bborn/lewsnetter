Mjml.template_language = :erb
Mjml.raise_render_exception = Rails.env.development?

# Locate the `mjml` CLI binary. mjml-rails normally discovers this via
# `which mjml`, but under `rails runner` / `rake` PATH is often pruned and
# the global mise/npm shim isn't visible. Fall back to a list of well-known
# locations so MJML rendering works in all execution contexts.
explicit_binary = ENV["MJML_BIN"].presence

candidates = [
  explicit_binary,
  "/Users/bruno/.local/share/mise/installs/node/22.22.0/bin/mjml",
  "/Users/bruno/.local/share/mise/installs/node/22.22.0/lib/node_modules/mjml/bin/mjml",
  "/opt/homebrew/bin/mjml",
  "/usr/local/bin/mjml"
].compact

found = candidates.find { |p| File.executable?(p) }

if found
  Mjml.mjml_binary = found
else
  Rails.logger.warn("[MJML] `mjml` CLI binary not on PATH. Templates will render raw MJML strings until you `npm install -g mjml`.")
end
