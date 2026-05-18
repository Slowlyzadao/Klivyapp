#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

# Install JS dependencies
pnpm install

# Install ALL gems including dev/test (base image excludes them)
unset BUNDLE_WITHOUT
rm -f .bundle/config
bundle install -j4

echo "Ready to run Vite development server."

exec "$@"
