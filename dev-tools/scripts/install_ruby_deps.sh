#!/bin/bash
source ~/.nvm/nvm.sh || true
source ~/.bashrc || true
source ~/.rvm/scripts/rvm || true

rvm use 3.4.4
bundle install
yarn install || pnpm install
