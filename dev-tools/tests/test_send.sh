#!/bin/bash
# Testa envio via bridge
# Substitua 55XXXXXXXXXXX pelo número real do seu celular (sem @s.whatsapp.net)
NUMERO="55XXXXXXXXXXX@s.whatsapp.net"

curl -s -X POST http://localhost:3002/send \
  -H "Content-Type: application/json" \
  -d "{\"to\":\"${NUMERO}\",\"type\":\"text\",\"text\":\"Teste de envio via Chatwoot QR Bridge!\"}"
echo ""
