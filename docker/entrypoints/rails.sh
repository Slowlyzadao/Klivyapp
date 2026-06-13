#!/bin/sh

set -x

# Remove a potentially pre-existing server.pid for Rails.
rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

echo "Waiting for postgres to become ready...."

# Let DATABASE_URL env take presedence over individual connection params.
$(docker/entrypoints/helpers/pg_database_url.rb)

# Check postgres using Ruby (pg_isready may not be installed in slim images)
until ruby -e "require 'socket'; TCPSocket.new('${POSTGRES_HOST:-postgres}', ${POSTGRES_PORT:-5432}).close" 2>/dev/null
do
  echo "Postgres not ready yet... waiting 2s"
  sleep 2;
done

echo "Database ready to accept connections."

# Install ALL gems including dev/test (override production config from base image)
unset BUNDLE_WITHOUT
rm -f .bundle/config
bundle install -j4

echo "Gems installed. Running bundle check..."
bundle check

# ARCH-15 (audit 2026-05-19): semeia stickers default do plugin internal_chat
# em todo boot. Idempotente — find_or_initialize_by + skip se file_size bate.
# Custo: ~2s sem mudanças. Roda ANTES do command override (rails s / sidekiq /
# foreman) pra garantir que stickers default estejam disponíveis em deploys
# novos (local com docker-compose, prod com Easypanel, test).
#
# `|| true` proposital: falha de blob storage NÃO deve derrubar o boot do
# app — sticker é nice-to-have, não bloqueante. Erro fica visível nos logs.
bundle exec rails internal_chat:seed_default_stickers || true

# Execute the main process of the container
exec "$@"
