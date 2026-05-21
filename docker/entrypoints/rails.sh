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

# Execute the main process of the container
exec "$@"
