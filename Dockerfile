# pre-build stage
FROM node:24-bookworm-slim as node
FROM ruby:3.4.4-slim-bookworm AS pre-builder

ENV RAILS_ENV=production
ENV BUNDLE_WITHOUT="development:test"
ENV BUNDLER_VERSION=2.5.16
ENV BUNDLE_PATH="/gems"
ENV BUNDLE_BIN="/gems/bin"
ENV PATH="${BUNDLE_BIN}:${PATH}"
ENV NODE_OPTIONS="--max-old-space-size=8192 --openssl-legacy-provider"

RUN apt-get update && apt-get install -y \
  build-essential \
  libpq-dev \
  git \
  curl \
  xz-utils \
  python3 \
  pkg-config \
  libvips-dev \
  cmake \
  && gem install bundler -v "$BUNDLER_VERSION"

WORKDIR /app

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && npm install -g pnpm@10.2.0 foreman

# Install Ruby Dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'development:test' && \
  bundle config set --local deployment 'true' && \
  MALLOC_ARENA_MAX=2 bundle install -j 1 -r 3

# Install Chatwoot Node Dependencies
COPY package.json pnpm-lock.yaml ./
RUN pnpm i

# Install WhatsApp Bridge Dependencies
COPY lib/whatsapp/package.json ./lib/whatsapp/
RUN cd lib/whatsapp && npm install

COPY . /app

# garante bit de executável nos scripts do bin/ (COPY pode perder +x
# em alguns backends de build como Docker Desktop + WSL2)
RUN chmod +x /app/bin/*

# generate production assets
# Dummy ACTIVE_RECORD_ENCRYPTION_* satisfy config/initializers/active_record_encryption.rb
# during build; real keys are injected by the runtime env (e.g. Easypanel).
RUN RAILS_SERVE_STATIC_FILES=true \
    SECRET_KEY_BASE=precompile_placeholder \
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=precompile_dummy_primary_key_xxxxxxxxxxxx \
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=precompile_dummy_determ_key_xxxxxxxxxxx \
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=precompile_dummy_salt_xxxxxxxxxxxxxxxxx \
    RAILS_LOG_TO_STDOUT=enabled \
    bundle exec rake assets:precompile && \
  rm -rf spec node_modules tmp/cache

RUN git rev-parse HEAD > /app/.git_sha || echo "unknown" > /app/.git_sha

# final build stage
FROM ruby:3.4.4-slim-bookworm

ENV RAILS_ENV=production
ENV BUNDLE_WITHOUT="development:test"
ENV BUNDLE_PATH="/gems"
ENV BUNDLE_BIN="/gems/bin"
ENV PATH="${BUNDLE_BIN}:${PATH}"
ENV RAILS_SERVE_STATIC_FILES=true
# Aponta para URL inválida com fragmento (#) para impedir que o hub externo
# sobrescreva o plano enterprise definido localmente.
ENV CHATWOOT_HUB_URL=https://hub.invalid/#

RUN apt-get update && apt-get install -y \
  libpq5 \
  tzdata \
  imagemagick \
  git \
  libvips42 \
  curl \
  python3 \
  ca-certificates \
  ffmpeg \
  && rm -rf /var/lib/apt/lists/* \
  && gem install bundler -v "2.5.16"

COPY --from=node /usr/local/bin/node /usr/local/bin/
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
  && ln -s /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
  && npm install -g foreman

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app

WORKDIR /app

EXPOSE 3000 3002

# Default command uses foreman to run processes defined in Procfile
CMD ["sh", "-c", "bundle exec rails db:chatwoot_prepare && bundle exec foreman start -f Procfile"]
