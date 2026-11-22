if defined?(Stripe)
  Stripe.api_key = ENV["STRIPE_SECRET_KEY"]

  # bullet_train-billing-stripe lets Stripe::SignatureVerificationError escape,
  # so a delivery signed with another endpoint's secret (or no signature) is a
  # 500 and a Sentry alert. Answer 400 instead; nothing is stored or processed.
  Rails.application.config.to_prepare do
    Webhooks::Incoming::StripeWebhooksController.rescue_from(Stripe::SignatureVerificationError) do |error|
      Rails.logger.warn("[stripe] rejected webhook: #{error.message}")
      head :bad_request
    end
  end
end
