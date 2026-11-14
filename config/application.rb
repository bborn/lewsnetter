require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require_relative "../lib/bullet_train_oauth_scaffolder_support"

module Lewsnetter
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # See `config/locales/locales.yml` for a list of available locales.
    config.i18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.{rb,yml}")]
    config.i18n.available_locales = YAML.safe_load_file("config/locales/locales.yml", aliases: true).with_indifferent_access.dig(:locales).keys.map(&:to_sym)
    config.i18n.default_locale = config.i18n.available_locales.first
    config.i18n.fallbacks = [:en]

    BulletTrain::Api.set_configuration(self)

    # MCP server tools live under app/mcp. Using push_dir with a namespace
    # makes Zeitwerk map app/mcp/tool/base.rb → Mcp::Tool::Base.
    # The ::Mcp module must be defined before the autoloader configures.
    module ::Mcp; end
    config.autoload_paths += %W[#{config.root}/app/mcp]
    config.eager_load_paths += %W[#{config.root}/app/mcp]
    Rails.autoloaders.main.push_dir("#{config.root}/app/mcp", namespace: Mcp)
  end
end
