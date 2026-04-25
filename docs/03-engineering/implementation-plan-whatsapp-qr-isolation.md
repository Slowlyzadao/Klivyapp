# 🛠️ Plano de Implementação: Isolamento do Módulo WhatsApp QR

Este documento descreve o passo-a-passo técnico para mover a funcionalidade de **WhatsApp QR Code** (atualmente integrada ao core) para um diretório isolado em `plugins/whatsapp_qr`, seguindo a arquitetura de **Modular Monolith** do KlivyApp.

---

## 1. Objetivos
- **Desacoplamento:** Garantir que o core do Chatwoot permaneça intocado para facilitar upgrades.
- **Organização:** Centralizar lógica de backend (Rails), frontend (Vue) e motor (Node.js) em um único diretório.
- **Padronização:** Seguir o modelo de Rails Engines já utilizado nos módulos de Agenda e Pacientes.

---

## 2. Levantamento de Arquivos Atuais
Antes de iniciar, identificamos as peças que precisam ser movidas:
- **Backend Rails:**
    - `app/models/channel/whatsapp.rb` (Modificações manuais)
    - `app/services/whatsapp/providers/whatsapp_qr_service.rb`
    - `app/controllers/webhooks/whatsapp_qr_controller.rb` (Se existir como arquivo separado)
- **Frontend Vue:**
    - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappQR.vue`
    - `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/WhatsappQRStatus.vue`
- **Motor (Bridge):**
    - `lib/whatsapp/` (Todo o conteúdo)
    - `dev-tools/scripts/start_bridge.sh`

---

## 3. Etapas da Implementação

### Passo 1: Criar o Plugin Base
Crie a estrutura do novo plugin:
```bash
mkdir -p plugins/whatsapp_qr/app/services/whatsapp/providers
mkdir -p plugins/whatsapp_qr/app/controllers/webhooks
mkdir -p plugins/whatsapp_qr/frontend/components
mkdir -p plugins/whatsapp_qr/engine
```
Crie o arquivo `plugins/whatsapp_qr/lib/whatsapp_qr/engine.rb` para gerenciar as injeções em runtime.

### Passo 2: Migrar o Motor Node.js (Bridge)
1. Mova o conteúdo de `lib/whatsapp/*` para `plugins/whatsapp_qr/engine/`.
2. Mova o script `dev-tools/scripts/start_bridge.sh` para `plugins/whatsapp_qr/scripts/start_bridge.sh`.
3. **Ajuste de Caminhos:** No `server.js` da Bridge, verifique se os caminhos de persistência de sessão (atualmente em `./sessions`) precisam ser relativos ou absolutos para evitar perda de dados.
4. **Update Procfile:** Atualize o `Procfile.dev`:
   ```diff
   - whatsapp: ./dev-tools/scripts/start_bridge.sh
   + whatsapp: ./plugins/whatsapp_qr/scripts/start_bridge.sh
   ```

### Passo 3: Migrar Lógica de Backend (Ruby)
1. Mova o `whatsapp_qr_service.rb` para o diretório do plugin.
2. **Injeção via `class_eval`:** No arquivo `engine.rb` do plugin, adicione o bloco para limpar o core:
   ```ruby
   config.to_prepare do
     Channel::Whatsapp.class_eval do
       # Remova fisicamente a lógica de 'whatsapp_qr' do arquivo original
       # e a injete aqui dinamicamente.
     end
   end
   ```
3. Garanta que o autoload do Rails encontre os novos caminhos do plugin.

### Passo 4: Migrar a Interface (Vue.js)
1. Mova os componentes `.vue` para `plugins/whatsapp_qr/frontend/components/`.
2. **Configuração do Vite:** No arquivo `vite.config.ts`, adicione o alias:
   ```typescript
   '@whatsapp_qr': path.resolve(__dirname, 'plugins/whatsapp_qr/frontend'),
   ```
3. **Injeção de Rotas:** Se houver rotas específicas, use o padrão de `router.addRoute` no arquivo de inicialização do frontend do plugin.

### Passo 5: Limpeza e Validação
1. **Reset do Core:** Execute `git checkout app/models/channel/whatsapp.rb` para remover as alterações manuais.
2. **Teste de Conexão:**
   - Inicie o servidor.
   - Verifique se a Bridge sobe corretamente na porta 3002.
   - Tente gerar um novo QR Code.
   - Envie e receba uma mensagem de teste.
3. **Logs:** Monitore se os logs continuam sendo gerados corretamente, agora com os novos caminhos.

---

## 4. Riscos e Mitigações
| Risco | Impacto | Mitigação |
| :--- | :--- | :--- |
| Perda de Sessões Ativas | Usuários terão que escanear o QR novamente. | Garantir que a pasta `auth_info` seja movida corretamente ou mapeada via Volume no Docker. |
| Erro de Autoload | Falha ao iniciar o Rails. | Certificar-se de que o plugin está corretamente registrado no `Gemfile` (se necessário) ou que o `lib/whatsapp_qr.rb` está correto. |
| Quebra de Webhook | Mensagens recebidas não aparecem. | Validar se o endpoint do webhook na Bridge (`CHATWOOT_BASE_URL`) continua apontando para o controlador correto. |
