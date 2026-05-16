# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "lewsnetter-rails"
  spec.version       = "0.1.0"
  spec.authors       = ["Bruno Bornsztein"]
  spec.email         = ["bruno@influencekit.com"]
  spec.summary       = "Push user data + custom attributes from a Rails app into Lewsnetter."
  spec.description   = <<~DESC
    Mirrors the intercom-rails pattern: one mixin on your User model auto-syncs
    every save to Lewsnetter's bulk subscriber endpoint, plus a backfill helper
    for nightly catch-ups. The Rails app stays the source of truth; Lewsnetter
    holds a fast, segmentable mirror for campaigns.
  DESC
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "README.md", "lewsnetter-rails.gemspec"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activejob", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "faraday-retry", ">= 2.0"
end
