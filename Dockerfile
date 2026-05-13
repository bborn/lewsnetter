# syntax=docker/dockerfile:1
# check=error=true

# Production Dockerfile for Lewsnetter v2.
#
# Single-binary deploy: Rails 8 + SQLite + Solid Queue + Solid Cable. The image
# also bundles the MJML CLI (used by `mjml-rails` to render newsletter
# templates) and the Litestream binary so the runtime container can replicate
# the three production SQLite databases to Cloudflare R2.
#
# Build via Kamal — see config/deploy.yml.

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.3
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages that the runtime image needs.
# - libsqlite3-0 / libvips / curl: Rails 8 runtime defaults
# - nodejs / npm: required by the mjml CLI which renders newsletter templates
# - ca-certificates: TLS to GHCR, R2, SES
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libvips \
      libsqlite3-0 \
      nodejs \
      npm \
      ca-certificates && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Install MJML CLI globally — `mjml-rails` shells out to this binary at
# render time. Pin to v5.x (mjml-rails 5.0+ validates against this output
# format).
RUN npm install -g mjml@5.2.1

# Install Litestream binary.
# Hetzner CX/CPX/CCX (x86) maps to amd64. If we ever move to cax* (ARM)
# servers, swap this URL to the linux-arm64 build.
ARG LITESTREAM_VERSION=0.3.13
RUN curl -fsSL -o /tmp/litestream.deb \
      "https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-v${LITESTREAM_VERSION}-linux-amd64.deb" && \
    dpkg -i /tmp/litestream.deb && \
    rm /tmp/litestream.deb

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems and native extensions
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libsqlite3-dev \
      libyaml-dev \
      pkg-config \
      node-gyp \
      python-is-python3 && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Install application gems. The Gemfile references a path-vendored gem
# at vendor/gems/lewsnetter-rails (in-repo until we extract it), so the
# gemspec + source need to exist in the build context before `bundle install`
# can resolve dependencies.
COPY Gemfile Gemfile.lock .ruby-version ./
COPY vendor/gems/lewsnetter-rails ./vendor/gems/lewsnetter-rails
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Install JS dependencies — Bullet Train ships jsbundling-rails + esbuild +
# Tailwind. Yarn is installed via corepack so we don't need a separate apt step.
COPY package.json yarn.lock ./
RUN corepack enable && yarn install --frozen-lockfile

# Copy application code
COPY . .

# Ensure bin scripts are executable BEFORE the cross-stage COPY. Some CI
# checkouts arrive with the +x bit stripped on files docker COPY treats
# preserving (the cause is environmental — gitconfig core.fileMode=false,
# umask, or runner image). chmod is idempotent if the bit is already set.
RUN chmod -R 0755 bin/

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Avo eagerly opens `log/avo.log` during app boot; assets:precompile runs the
# full Rails initializer chain so the file must exist before precompile runs.
RUN mkdir -p log && touch log/avo.log

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Some CI builds drop the +x bit on bin/* scripts (we hit Permission denied
# on /rails/bin/docker-entrypoint when first deploying via GH Actions). Run
# chmod here AND log the resulting permissions so future regressions are
# obvious in the build log.
# Files copied from the build stage land as mode 600 (root-only) when the
# CI runner's checkout used a restrictive umask (observed on ubuntu-latest
# GH Actions; local kamal deploys from a developer machine didn't hit it
# because umask 022 there yields 644). Make everything world-readable +
# directories world-traversable, then re-apply +x to bin/.
RUN find /rails -type d -exec chmod 0755 {} + && \
    find /rails -type f -exec chmod 0644 {} + && \
    chmod 0755 /rails/bin/*

# Place litestream config at the canonical path.
COPY litestream.yml /etc/litestream.yml

# Make sure runtime directories exist and are owned by the non-root user.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp /etc/litestream.yml

USER 1000:1000

# Entrypoint runs `litestream restore` against each SQLite database (no-op if
# no replicas exist yet) before exec'ing the passed command — which is either
# `bin/rails server` (web role) or `bin/rake solid_queue:start` (worker).
# For the web role the entrypoint wraps the command in `litestream replicate
# -exec` so the replicator runs alongside Puma.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server", "-p", "3000", "-b", "0.0.0.0"]
