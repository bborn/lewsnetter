require_relative "lib/lewsnetter-rails/version"

Gem::Specification.new do |spec|
  spec.name = "lewsnetter-rails"
  spec.version = Lewsnetter::VERSION
  spec.authors = ["Lewsnetter"]
  spec.email = ["support@lewsnetter.com"]

  spec.summary = "Rails client for Lewsnetter — push subscribers and events to your Lewsnetter team."
  spec.description = "Provides `acts_as_lewsnetter_subscriber` for ActiveRecord models, `Lewsnetter.track` for behavioral events, and `Lewsnetter.bulk_upsert` for backfill. Zero runtime deps beyond ActiveJob."
  spec.homepage = "https://lewsnetter.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/lewsnetter/lewsnetter-rails"

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "Rakefile",
    "lewsnetter-rails.gemspec"
  ]
  spec.require_paths = ["lib"]

  # Runtime deps — keep this list to ONE. Net::HTTP is stdlib.
  spec.add_dependency "activejob", ">= 6.1"

  # Dev deps.
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "activerecord", ">= 6.1"
  spec.add_development_dependency "sqlite3", ">= 1.4"
end
