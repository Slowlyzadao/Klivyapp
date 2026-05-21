#!/bin/bash
source ~/.nvm/nvm.sh || true
source ~/.bashrc || true
source ~/.rvm/scripts/rvm || true

rvm use 3.4.4 || { echo "Execute install_ruby_deps.sh primeiro!"; exit 1; }

echo "Preparando banco de dados..."
bundle exec rails db:prepare

echo "Iniciando Chatwoot..."
overmind start -f ./Procfile.dev || foreman start -f ./Procfile.dev
