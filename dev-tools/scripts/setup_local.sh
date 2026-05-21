#!/bin/bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 24.13.0
nvm use 24.13.0
corepack enable
npm install -g pnpm yarn
pnpm install
bundle install
