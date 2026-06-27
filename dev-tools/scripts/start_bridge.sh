#!/bin/bash
NODE_BIN=$(which node)

echo "🧹 Limpando processos zumbis do WhatsApp..."
# Usa o lsof para achar o processo usando a porta 3002 e matar, garantindo suporte pleno ao macOS
lsof -ti :3002 | xargs kill -9 2>/dev/null || true
# Mata qualquer node rodando server.js no diretório do whatsapp
pkill -f "server.js" || true
sleep 1

cd ./lib/whatsapp

# Carrega variáveis de ambiente locais
if [ -f env.localhost ]; then
    echo "📖 Carregando configurações de localhost..."
    export $(grep -v '^#' env.localhost | xargs)
fi

echo "🚀 Iniciando Bridge Oficial (server.js unificado)..."
exec $NODE_BIN server.js 2>&1 | tee bridge.log
