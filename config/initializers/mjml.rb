Mjml.template_language = :erb
Mjml.raise_render_exception = Rails.env.development?

# Optional warning when the MJML CLI binary is missing. The mjml-rails gem
# already logs a one-liner; we surface a more actionable hint here.
unless system("which mjml > /dev/null 2>&1")
  Rails.logger.warn("[MJML] `mjml` CLI binary not on PATH. Templates will render raw MJML strings until you `npm install -g mjml`.")
end
