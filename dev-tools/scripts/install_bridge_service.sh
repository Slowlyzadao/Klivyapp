#!/bin/bash
# ============================================================
# Instala o serviço systemd para o WhatsApp Bridge (Baileys)
# Execute com: bash install_bridge_service.sh
# ============================================================

set -e

SERVICE_FILE="/home/leook/chatwoot-develop/lib/whatsapp/whatsapp-bridge.service"
SYSTEMD_DIR="/etc/systemd/system"

echo "🔧 Instalando serviço WhatsApp Bridge..."

# Copia o arquivo de serviço para o systemd
sudo cp "$SERVICE_FILE" "$SYSTEMD_DIR/whatsapp-bridge.service"

# Recarrega o daemon do systemd
sudo systemctl daemon-reload

# Habilita o serviço para iniciar automaticamente
sudo systemctl enable whatsapp-bridge.service

# Inicia o serviço imediatamente (para o processo já em execução, reinicia)
sudo systemctl restart whatsapp-bridge.service

echo ""
echo "✅ Serviço instalado e iniciado!"
echo ""
echo "📋 Comandos úteis:"
echo "   sudo systemctl status whatsapp-bridge   → Ver status"
echo "   sudo systemctl restart whatsapp-bridge  → Reiniciar"
echo "   sudo systemctl stop whatsapp-bridge     → Parar"
echo "   sudo journalctl -u whatsapp-bridge -f   → Ver logs em tempo real"
echo ""

# Mostra o status atual
sudo systemctl status whatsapp-bridge.service --no-pager
