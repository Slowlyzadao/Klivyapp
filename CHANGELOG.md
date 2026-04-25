# Changelog

Todas as mudanças relevantes no projeto serão documentadas neste arquivo.

## Estrutura de Versão: `1.B.C.D`

- **1**: Versão Major (Fixa).
- **B**: Conclusão de Projetos/Módulos completos (Ex: Sistema de Agenda, Kanban).
- **C**: Incrementado quando a contagem de bugs (D) atinge 10.
- **D**: Correções de bugs e mudanças menores.
- **Obrigatório**: Cada entrada deve listar os **Arquivos Modificados** ao final da descrição.

## [1.4.4.65] - 2026-04-24T00:00:00-03:00

### RBAC: Refinamentos na promoção a Owner — filtro de SuperAdmin e ocultação do time interno

**Problema:**
Após a entrega das versões v1.4.4.63 (botão manual) e v1.4.4.64 (auto-promoção), dois ajustes finos apareceram no uso real:
1. SaaS SuperAdmins (`User.type = 'SuperAdmin'`) apareciam na lista de usuários "promovíveis" do painel `/beclinic_admin/owners`, mesmo já tendo bypass global via `beclinic_super_admin?` — confuso e redundante.
2. O `Team` interno chamado `owner` (infraestrutura da RBAC) aparecia no sidebar do cliente ("Times → owner") e na tela Configurações → Times, poluindo a UI do cliente final.

**Solução 1 — Filtro de SuperAdmin em 4 camadas (defesa em profundidade):**
- `BeclinicAdmin::OwnersController#show` — filtra `users.type = nil` na listagem de `@account_users` (esconde SuperAdmins).
- `BeclinicAdmin::OwnersController#load_owners_for` / `#owner_user_ids` — rejeita SuperAdmins da coluna "Proprietário(s) atual(is)" do index e do cálculo de "já é proprietário".
- `BeclinicCore::AccountSetup#promote_to_owner!` — raise `ArgumentError` se tentarem promover um SuperAdmin (mesmo via POST direto ou console).
- `Account#setup_beclinic_owner` callback — skip se o primeiro usuário da conta for SuperAdmin (evita auto-promoção no onboarding inicial do SaaS).

**Solução 2 — Time `owner` invisível para o cliente:**
Sobrescrita via `class_eval` de `Api::V1::Accounts::TeamsController#index` dentro do `to_prepare` do plugin, filtrando `WHERE name != 'owner'`. Afeta sidebar, Configurações → Times e qualquer dropdown de seleção de time. Zero edição do controller original do core. `beclinic_team_for(account)` e permissões backend continuam enxergando o time normalmente.

**Arquivos Modificados:**
- `plugins/beclinic_core/app/controllers/beclinic_admin/owners_controller.rb` (filtros de SuperAdmin nas 3 actions)
- `plugins/beclinic_core/app/services/beclinic_core/account_setup.rb` (+1 linha guard)
- `plugins/beclinic_core/lib/beclinic_core/engine.rb` (skip no callback + class_eval na TeamsController)
- `spec/plugins/beclinic_core/services/account_setup_spec.rb` (+2 testes)
- `spec/plugins/beclinic_core/callbacks/account_owner_auto_promotion_spec.rb` (+1 teste)

**Testes:** 27/27 passando no rspec do plugin após os ajustes.

---

## [1.4.4.64] - 2026-04-23T16:30:00-03:00

### RBAC: Promoção automática de Owner na criação de conta (compra de plano)

**Problema:**
Mesmo com o botão manual do Super Admin disponível (v1.4.4.63), toda nova conta criada via compra de plano ainda nascia sem Proprietário definido, exigindo intervenção do time. O ideal é que o comprador do plano já saia como Proprietário automaticamente.

**Solução:**
Callback `after_create_commit :setup_beclinic_owner` registrado em `Account` via `class_eval` dentro do próprio `plugins/beclinic_core/lib/beclinic_core/engine.rb` (padrão já usado no plugin para `has_one :beclinic_profile`). Quando uma nova `Account` é criada (tipicamente via `AccountBuilder` no fluxo do `plugins/billing`), o callback:
- Busca o primeiro `AccountUser` da conta (o criador).
- Chama `BeclinicCore::AccountSetup.promote_to_owner!` — mesmo service reutilizado pelo botão manual.
- Resgata qualquer erro e apenas registra `Rails.logger.warn` — falha aqui **nunca** derruba a criação da conta.
- Não faz nada se a conta foi criada sem usuário vinculado (ex: factories em testes).

Zero edição em `app/models/account.rb` ou em qualquer arquivo do core — tudo vive dentro do plugin.

**Arquivos Modificados:**
- `plugins/beclinic_core/lib/beclinic_core/engine.rb` (callback adicionado no `Account.class_eval` existente)

**Arquivos Adicionados:**
- `spec/plugins/beclinic_core/callbacks/account_owner_auto_promotion_spec.rb`

---

## [1.4.4.63] - 2026-04-23T16:00:00-03:00

### RBAC: Promoção manual de Owner (UI: "Proprietário") em painel standalone

**Problema:**
Após a compra do plano, o cliente (dono da conta) ficava com papel `gerente`, exigindo ajuste manual de permissões toda vez que ele tentava operar recursos como "adicionar pacientes". O papel `dono` já existia no backend (`BECLINIC_ROLES`) e concede `full_permissions_hash`, mas não havia fluxo para atribuí-lo.

**Solução:**
Página standalone `/beclinic_admin/owners`, autenticada via sessão Devise de `super_admin` (mesmo login do painel super admin). Selecione uma conta e promova um de seus usuários a Proprietário. A promoção:
- Cria (idempotente) um `Team` chamado `owner` com `beclinic_role: 'dono'` na conta.
- Remove o usuário de outros times da mesma conta para garantir que `beclinic_team_for(account)` resolva para o time de Owner.
- **Nunca** altera `User#type` (a flag `SuperAdmin` permanece reservada ao dono do SaaS).

**Por que standalone e não dentro do `/super_admin`?** O painel super admin do Chatwoot usa Administrate, que auto-descobre controllers cujo path começa com `super_admin/` e tenta renderizar sidebar items para cada um. Qualquer resource desconhecido nesse path quebra toda a navegação admin. A feature usa layout próprio mínimo (sem Vite, sem Administrate) e tem zero impacto no painel super admin existente.

**Convenção de nomes:** identificadores em inglês (classes, rotas, arquivos, métodos, `Team.name`); valor de enum `beclinic_role: 'dono'` mantido (compatibilidade com `BECLINIC_ROLES` existente); rótulos de UI em português ("Proprietário").

**Arquivos Adicionados:**
- `plugins/beclinic_core/app/services/beclinic_core/account_setup.rb`
- `plugins/beclinic_core/app/controllers/beclinic_admin/owners_controller.rb`
- `plugins/beclinic_core/app/views/layouts/beclinic_admin.html.erb`
- `plugins/beclinic_core/app/views/beclinic_admin/owners/index.html.erb`
- `plugins/beclinic_core/app/views/beclinic_admin/owners/show.html.erb`
- `spec/plugins/beclinic_core/services/account_setup_spec.rb`
- `spec/plugins/beclinic_core/controllers/beclinic_admin/owners_controller_spec.rb`

**Arquivos Modificados:**
- `config/routes.rb` (+4 linhas: `namespace :beclinic_admin do resources :owners, ... end` no topo do arquivo, fora do bloco super_admin existente)

---

## [1.4.4.62] - 2026-04-23T15:44:17-03:00

### WhatsApp: Entrega de Áudio com Duração e Externalização dos Termos de Uso

**Problema:**
Áudios enviados via WhatsApp chegavam sem metadado de duração, exibindo "0:00" em alguns clientes. Adicionalmente, o texto dos Termos de Uso estava hardcoded no `checkout.html`, dificultando manutenção.

**Solução:**
- Servidor WhatsApp (`lib/whatsapp/server.js`) passou a calcular/anexar a duração antes do envio, garantindo que o player do destinatário exiba o tempo correto.
- Conteúdo dos Termos movido para `TermosUso.md` e carregado dinamicamente pelo `checkout.html`.
- Ajustes no `Dockerfile` para suportar os novos assets.

**Arquivos Modificados:**
- `lib/whatsapp/server.js`
- `TermosUso.md`
- `public/checkout.html`
- `Dockerfile`

---

## [1.4.4.61] - 2026-04-23T14:20:59-03:00

### Prontuário: Upload de Vídeos, Progresso e Persistência em Navegação + Webhooks com X-Forwarded-Proto

Duas frentes combinadas: suporte a vídeo em exames e robustez em salvamento durante navegação, além de correção em requisições HTTPS via proxy.

**1. Upload de Vídeos em Exames (`plugins/patients`):**
- Controller `exam_folders_controller` e model `exam_media` agora aceitam mimetypes de vídeo.
- Barras de progresso por upload no `Record.vue`.
- Dados da pasta de exames persistem de forma confiável mesmo quando o usuário navega/recarrega durante o upload (uso de `beforeunload` + flush pendente).

**2. Webhook / Loopback HTTPS (`lib/whatsapp/server.js`):**
- Adicionado header `X-Forwarded-Proto` em requisições fetch de webhook e loopback, corrigindo validação de protocolo em ambientes atrás de proxy reverso (EasyPanel/Traefik).

**Arquivos Modificados:**
- `plugins/patients/app/controllers/api/v1/accounts/patients/exam_folders_controller.rb`
- `plugins/patients/app/models/exam_media.rb`
- `plugins/patients/frontend/api/patients/examMedias.js`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `lib/whatsapp/server.js`
- `docs/build_deploy.md`

---

## [1.4.4.60] - 2026-04-23T13:06:18-03:00

### Anamnese: Campos Aninhados de Histórico Médico, State Patching e Ajustes no PDF + Toasts no Checkout

**Anamnese (`plugins/patients`):**
- Campos de histórico médico foram aninhados (objeto estruturado) em vez de chaves planas, simplificando novas adições e a renderização dinâmica no `AnamnesisTab.vue`.
- Introduzido _state patching_ no `Record.vue` para evitar re-renders completos ao editar blocos grandes da anamnese.
- Gerador de PDF (`anamnesis_pdf_generator.rb`) atualizado para a nova estrutura e teve o cabeçalho limpo — removidas informações de versão/data que estavam poluindo o topo do relatório.
- Specs adicionados em `spec/models/anamnesis_spec.rb` e factories atualizadas.

**Checkout (`plugins/billing`):**
- Toasts de sucesso/erro substituindo alerts nativos.
- Validação inline por campo (e não apenas no submit) no `checkout.html` e `onboarding-finish.html`.
- Ajustes em `create_customer` e no `onboarding_controller` para retornar mensagens consistentes.

**Arquivos Modificados:**
- `app/services/patients/anamnesis_pdf_generator.rb`
- `app/views/api/v1/accounts/patients/anamneses/_anamnesis.json.jbuilder`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `plugins/patients/frontend/routes/patients/tabs/AnamnesisTab.vue`
- `spec/factories/anamneses.rb`
- `spec/factories/patients.rb`
- `spec/models/anamnesis_spec.rb`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/services/asaas/create_customer.rb`
- `plugins/billing/config/routes.rb`
- `public/checkout.html`
- `public/onboarding-finish.html`

---

## [1.4.4.59] - 2026-04-22T23:07:40-03:00

### Checkout: Cupons Dinâmicos, Multi-step Validation, Turnstile e Ajuste de Preços

Evolução completa do fluxo de checkout para produção: validação por etapa, anti-bot, sistema flexível de cupons e reajuste de planos.

**1. Cupons Dinâmicos (`plugins/billing`):**
- Migrations adicionam `coupon_fields` e `credit_card_token` em `billing_subscriptions`.
- Novo `Billing::CouponRegistry` centraliza regras de descontos/trials variáveis por cupom.
- `Asaas::CreateSubscription` e `Asaas::CreatePayment` passam a aplicar trial e desconto conforme registry.

**2. Multi-step Validation & Formatação (`public/checkout.html`):**
- Validação por passo (dados pessoais → endereço → pagamento), bloqueando avanço com campos inválidos.
- Formatação aprimorada do input de cartão de crédito (máscara + bandeira detectada).

**3. Cloudflare Turnstile (`plugins/billing`, `plugins/beclinic_core`):**
- Verificação do token Turnstile no backend de onboarding.
- Domínios de contato atualizados para `klivy.app` em mailers e textos.

**4. Pricing:**
- Preço do plano Standard e valores promocionais atualizados no `Asaas::CreateSubscription` e no HTML.

**Arquivos Modificados:**
- `db/migrate/20260423000001_add_coupon_fields_to_billing_subscriptions.rb`
- `db/migrate/20260423000002_add_credit_card_token_to_billing_subscriptions.rb`
- `db/schema.rb`
- `config/schedule.yml`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/services/asaas/api_client.rb`
- `plugins/billing/app/services/asaas/create_payment.rb`
- `plugins/billing/app/services/asaas/create_subscription.rb`
- `plugins/billing/app/services/billing/coupon_registry.rb`
- `plugins/beclinic_core/app/mailers/klivy_mailer.rb`
- `plugins/beclinic_core/app/views/klivy_mailer/password_change.html.erb`
- `plugins/agenda/frontend/features/settings/composables/useSettingsNotifications.js`
- `app/controllers/swagger_controller.rb`
- `public/checkout.html`

---

## [1.4.4.58] - 2026-04-22T18:39:53-03:00

### DevOps: Build & Deploy em Produção (Docker Hub + EasyPanel)

Suporte completo para build/push de imagens de produção e deploy em EasyPanel.

**Mudanças:**
- Documentação em `docs/03-engineering/docker.md` com instruções de build/push no Docker Hub e passos de deploy em EasyPanel, incluindo troubleshooting.
- `Dockerfile` corrigido para garantir permissão de execução nos scripts de `bin/` dentro da imagem.
- Scripts em `bin/` marcados como executáveis no próprio git (arquivos versionados com bit +x).
- `docker-compose.yaml` com comandos formatados e `config/initializers/filter_parameter_logging.rb` ampliado para filtrar parâmetros sensíveis adicionais nos logs.
- `config/database.yml` ajustado para o ambiente de produção.

**Arquivos Modificados:**
- `Dockerfile`
- `docker-compose.yaml`
- `docs/03-engineering/docker.md`
- `config/database.yml`
- `config/initializers/filter_parameter_logging.rb`
- `bin/bundle`, `bin/rails`, `bin/rake`, `bin/setup`, `bin/spring`, `bin/sync_i18n_file_change`, `bin/update`, `bin/validate_push`, `bin/vite`, `bin/yarn`
- `.claude/settings.local.json`

---

## [1.4.4.57] - 2026-04-22T14:41:14-03:00

### API: Swagger/OpenAPI Completo para Plugins Core + Brand Assets

Documentação OpenAPI unificada para os plugins principais e substituição de logos inline por assets externos.

**Swagger (`plugins/*/swagger`):**
- Estrutura definitions/paths para `agenda`, `financial`, `patients`, `beclinic_core` e `billing`.
- `lib/tasks/swagger.rake` consolida os arquivos YAML em `swagger/plugins_swagger.json` e gera viewers estáticos (`plugins_scalar.html`, `core_scalar.html`).
- `docs/api-documentation-strategy.md` descreve a convenção adotada.

**Brand Assets:**
- Logos inline no `checkout.html` e `onboarding-finish.html` substituídos por referências a `public/brand-assets/logo.*` (svg + png variações), com ajustes de sizing.
- Correção de IDs duplicados em spinners de carregamento.

**Arquivos Modificados:**
- `config/routes.rb`
- `lib/tasks/swagger.rake`
- `docs/api-documentation-strategy.md`
- `plugins/agenda/swagger/**/*.yml`
- `plugins/financial/swagger/**/*.yml`
- `plugins/patients/swagger/**/*.yml`
- `plugins/beclinic_core/swagger/index.yml`
- `plugins/billing/swagger/index.yml`
- `swagger/plugins_swagger.json`, `swagger/plugins_scalar.html`, `swagger/core_scalar.html`, `swagger/plugins_index.yml`
- `public/checkout.html`
- `public/onboarding-finish.html`
- `.gitignore`

---

## [1.4.4.56] - 2026-04-22T13:20:03-03:00

### Mailer: Templates Branded Klivy (Confirmação, Convite, Alteração de Senha)

Substituição completa dos templates padrão do Devise por um mailer branded Klivy e migração de reset-password para email de confirmação.

**Mudanças (`plugins/beclinic_core`):**
- Novo `Klivy::Mailer` com layout compartilhado (`layouts/klivy_mailer.html.erb`) e templates para: `confirmation_instructions`, `reset_password_instructions`, `password_change`, `_invitation`.
- Locales dedicados em `config/locales/klivy_mailer.pt_BR.yml` + overrides de `devise.pt_BR.yml`.
- Assets de marca adicionados em `public/brand-assets/logo.*` (svg claro/escuro, png, thumbnail).

**Onboarding:**
- Fluxo de reset-password substituído por envio de email de confirmação (`confirmation_instructions`).
- Tratamento de erros adicionado ao `onboarding_controller`.
- Strings localizadas em `config/locales/pt_BR.yml`.

**Arquivos Modificados:**
- `plugins/beclinic_core/app/mailers/klivy_mailer.rb`
- `plugins/beclinic_core/app/views/klivy_mailer/*.html.erb`
- `plugins/beclinic_core/app/views/layouts/klivy_mailer.html.erb`
- `plugins/beclinic_core/config/locales/devise.pt_BR.yml`
- `plugins/beclinic_core/config/locales/klivy_mailer.pt_BR.yml`
- `plugins/beclinic_core/lib/beclinic_core/engine.rb`
- `app/views/devise/mailer/confirmation_instructions.html.erb`
- `app/views/layouts/vueapp.html.erb`
- `config/locales/pt_BR.yml`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `public/brand-assets/logo.png`, `logo.svg`, `logo_dark.svg`, `logo_thumbnail.svg`
- `public/onboarding-finish.html`

---

## [1.4.4.55] - 2026-04-21T10:48:48-03:00

### Onboarding: Fluxo de Finalização (Senha + Endereço) e Guia Coolify

**Onboarding Finish Flow (`plugins/billing`):**
- Nova página `public/onboarding-finish.html` onde o usuário define senha e informa endereço após a confirmação por email.
- Rotas dedicadas no `plugins/billing/config/routes.rb` e ações no `onboarding_controller` + `Asaas::CreateCustomer` para persistir endereço no Asaas.

**Documentação:**
- `docs/guia_instalacao_coolify.md` com passos para rodar Coolify ao lado do KlivyApp sem conflito de portas.

**Arquivos Modificados:**
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/services/asaas/create_customer.rb`
- `plugins/billing/config/routes.rb`
- `public/checkout.html`
- `public/onboarding-finish.html`
- `docs/guia_instalacao_coolify.md`

---

## [1.4.4.54] - 2026-04-20T12:46:28-03:00

### Billing: Cupom BEMVINDO com Desconto na Assinatura

Primeiro cupom do sistema, validado antes da chamada ao Asaas.

**Mudanças (`plugins/billing`):**
- `onboarding_controller` recebe o código do cupom e o valida.
- `Asaas::CreateSubscription` aplica desconto quando o cupom `BEMVINDO` é válido.
- `checkout.html` exibe campo de cupom e feedback visual do desconto aplicado.

**Arquivos Modificados:**
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/services/asaas/create_subscription.rb`
- `public/checkout.html`

---

## [1.4.4.53] - 2026-04-20T12:36:55-03:00

### Prontuário: Layout Responsivo, Sidebar Mobile e Design Tokens

Refatoração completa da rota de prontuário para uso em mobile e aplicação consistente dos tokens do design system.

**Mudanças:**
- Layout responsivo de `Record.vue` e `Index.vue` em `plugins/patients`, com sidebar mobile dedicada (`MobileSidebarLauncher.vue`) e expand/collapse no layout do dashboard (breakpoint atualizado para 1024px).
- Novo componente `BaseSelect.vue` integrado ao `NewPatientModal` para seleção de gênero (substitui `<select>` nativo).
- Tokens de cor/design-system aplicados ao modal de câmera e à sidebar do prontuário; estilos CSS consolidados em `record.css` e `patients-index.css`.

**Arquivos Modificados:**
- `plugins/patients/frontend/components/BaseSelect.vue`
- `plugins/patients/frontend/routes/patients/Record.vue`
- `plugins/patients/frontend/routes/patients/Index.vue`
- `plugins/patients/frontend/routes/patients/components/NewPatientModal.vue`
- `plugins/patients/frontend/routes/patients/record.css`
- `app/javascript/dashboard/components-next/sidebar/MobileSidebarLauncher.vue`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/constants/globals.js`

---

## [1.4.4.52] - 2026-04-19T19:12:11-03:00

### Design System: Switch Component, Border-radius Consistente e Permissões de Equipe

Alinhamento visual e estrutural de componentes ao design system.

**Mudanças:**
- `Switch` component substituindo inputs de toggle em `TeamPermissions.vue` e `RoleFormModal.vue`.
- Erro de unauthorized em `teams_controller` agora é localizado (i18n) em `agentMgmt.json` e `teamsSettings.json`.
- Migração de CSS para variáveis semânticas em `patients-index.css` e novos tokens aplicados em `AgendaEventModal.vue`, `AgendaHeader.vue`, `agenda-events.css`.
- Border-radius consistente em modais/paginação/patients index.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/teams_controller.rb`
- `app/controllers/concerns/request_exception_handler.rb`
- `app/javascript/dashboard/routes/dashboard/settings/teams/Edit/TeamPermissions.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/agentMgmt.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/teamsSettings.json`
- `plugins/beclinic_core/frontend/settings/BeClinicRoles/RoleFormModal.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaHeader.vue`
- `plugins/agenda/frontend/styles/agenda-events.css`
- `plugins/patients/frontend/routes/patients/components/NewPatientModal.vue`
- `plugins/patients/frontend/routes/patients/patients-index.css`
- `plugins/patients/frontend/routes/patients/Index.vue`

---

## [1.4.4.51] - 2026-04-19T14:14:26-03:00

### Agenda: Polish em Settings, Indicador de Fechado e Month View Border

Round de acabamento visual e feedback nos settings da agenda + ajustes no grid mensal.

**Mudanças (`plugins/agenda`):**
- Estilo do botão "Salvar" padronizado (`SettingsTabSchedules.vue`).
- Scroll suave com `scroll-into-view` ao trocar de aba nos settings.
- Feedback de sucesso visual no `SettingsTabServices.vue` e limpeza de lógica de cor em `useAgenda.js` / `AgendaEventModal.vue`.
- Indicador de status "fechado" adicionado na timeline com ajustes responsivos para mobile.
- Remoção da borda `.cell-header` em `AgendaMonthView.vue` para visual mais limpo.

**Arquivos Modificados:**
- `plugins/agenda/frontend/features/settings/components/SettingsTabSchedules.vue`
- `plugins/agenda/frontend/features/settings/components/SettingsTabServices.vue`
- `plugins/agenda/frontend/routes/settings/Index.vue`
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaMonthView.vue`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`

---

## [1.4.4.50] - 2026-04-18T23:08:07-03:00

### I18n, Onboarding Security, Default Holidays e pt-BR no Administrate

Ajustes transversais envolvendo localização, segurança e seed de feriados.

**Mudanças:**
- `switch_locale` e demais concerns de i18n revisados para processar blocos de locale corretamente em `ApplicationController`, `portals/base_controller` e `ApplicationMailer`.
- Segurança no onboarding: validação reforçada em `onboarding_controller` e `Asaas::HandleWebhook`; lógica de acesso corrigida em `Billing::AccessControl` e `Billing::Subscription`.
- Novo seed de feriados default em `AgendaSetting` com configuração automática via `agenda_settings_controller` e locale da aplicação fixado em `pt-BR`.
- Adicionado `config/locales/administrate.pt_BR.yml` para o dashboard do Administrate.

**Arquivos Modificados:**
- `app/controllers/application_controller.rb`
- `app/controllers/concerns/switch_locale.rb`
- `app/controllers/public/api/v1/portals/base_controller.rb`
- `app/mailers/application_mailer.rb`
- `config/application.rb`
- `config/locales/administrate.pt_BR.yml`
- `plugins/agenda/app/controllers/api/v1/accounts/agenda_settings_controller.rb`
- `plugins/agenda/app/models/agenda_setting.rb`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/models/billing/subscription.rb`
- `plugins/billing/app/services/asaas/handle_webhook.rb`
- `plugins/billing/lib/billing/access_control.rb`
- `public/checkout.html`

---

## [1.4.4.49] - 2026-04-17T21:51:29-03:00

### Billing: Engine com Integração Asaas (Assinaturas + Webhooks + Onboarding)

Novo engine `plugins/billing` responsável por todo o ciclo de cobrança via Asaas.

**Estrutura criada:**
- Models: `Billing::Customer`, `Billing::Subscription`, `Billing::Payment`.
- Services Asaas: `ApiClient`, `CreateCustomer`, `CreateSubscription`, `HandleWebhook`.
- Controllers: `Billing::OnboardingController` e `Billing::WebhooksController`.
- Jobs: `Billing::ProcessAsaasWebhookJob` para processamento assíncrono.
- `Billing::AccessControl` para bloquear features quando a assinatura não está ativa.
- Migration `20260416200000_create_billing_tables.rb` criando tabelas do módulo.
- `public/checkout.html` com landing inicial do onboarding.
- Documentação em `docs/01-product/modules/billing.md`.

**Arquivos Modificados:**
- `db/migrate/20260416200000_create_billing_tables.rb`
- `db/schema.rb`
- `config/routes.rb`
- `docs/01-product/modules/billing.md`
- `lib/custom_exceptions/billing.rb`
- `plugins/billing/app/controllers/billing/api/v1/billing/onboarding_controller.rb`
- `plugins/billing/app/controllers/billing/api/v1/billing/webhooks_controller.rb`
- `plugins/billing/app/jobs/billing/process_asaas_webhook_job.rb`
- `plugins/billing/app/models/billing/{customer,payment,subscription}.rb`
- `plugins/billing/app/services/asaas/{api_client,create_customer,create_subscription,handle_webhook}.rb`
- `plugins/billing/config/routes.rb`
- `plugins/billing/lib/billing.rb`
- `plugins/billing/lib/billing/{access_control,engine}.rb`
- `public/checkout.html`

---

## [1.4.4.48] - 2026-04-16T22:18:37-03:00

### Agenda: Bloqueio de Dias Fechados + Ícone de Cadeado e Dropdown Invertido

Tratamento visual e lógico de dias fechados na agenda e ajuste de popups.

**Mudanças (`plugins/agenda`):**
- `useAgenda.js` filtra blocos "closed" nas views Timeline e Month.
- Ícone de cadeado (lock) exibido em dias fechados na timeline, com lógica de bloqueio a cliques/drag.
- `AgendaEventModal.vue` ganhou modo de dropdown abrindo para cima quando não há espaço abaixo (styles em `agenda-events.css`).

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaMonthView.vue`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/styles/agenda-events.css`

---

## [1.4.4.47] - 2026-04-16T19:50:05-03:00

### Agenda: Dark Mode nos Modais e AgendaEventModal Responsivo com Teleport

Round de UX dos modais e popups da agenda.

**Mudanças (`plugins/agenda`):**
- Dark mode implementado para `AgendaDeleteModal`, `AgendaEventCard` e tipos de bloco no `AgendaEventInfoPopup`.
- `AgendaEventModal` responsivo para mobile e encapsulado em `<Teleport>` + `<transition>` para melhor overlay.
- Ajustes de layout no `AgendaHeader.vue` e estilos em `agenda-summary.css`.

**Arquivos Modificados:**
- `plugins/agenda/frontend/components/AgendaDeleteModal.vue`
- `plugins/agenda/frontend/components/AgendaEventCard.vue`
- `plugins/agenda/frontend/components/AgendaEventInfoPopup.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaHeader.vue`
- `plugins/agenda/frontend/components/AgendaMonthView.vue`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/features/agenda-summary/agenda-summary.css`

---

## [1.4.4.46] - 2026-04-16T12:22:11-03:00

### Agenda: Day-Block Banners, Treatment Colors e Cleanup de Patches Obsoletos

Banners por tipo de bloqueio de dia e paleta unificada de cores por tratamento, além de remoção dos arquivos de patch usados durante a refatoração.

**Mudanças (`plugins/agenda`):**
- `agenda-colors.js` centraliza a paleta por tratamento; `AgendaEventCard`, `AgendaMonthView` e `AgendaTimelineView` passam a lê-la via composable.
- Banners visuais nos day-blocks (Online Booking / Schedules / Services settings).
- Padronização de font-size (Tailwind `@apply text-sm`) em todos os componentes da agenda + ajustes na lógica de posicionamento de popups.
- Removidos os arquivos `patch_index_*.js` usados durante a migração e assets Vite obsoletos.
- `.gitignore` ignora arquivos `Zone.Identifier` (artefatos do WSL).

**Arquivos Modificados:**
- `plugins/agenda/frontend/utils/agenda-colors.js`
- `plugins/agenda/frontend/components/AgendaEventCard.vue`
- `plugins/agenda/frontend/components/AgendaMonthView.vue`
- `plugins/agenda/frontend/components/AgendaTimelineView.vue`
- `plugins/agenda/frontend/components/AgendaHeader.vue`
- `plugins/agenda/frontend/components/AgendaDeleteModal.vue`
- `plugins/agenda/frontend/components/AgendaEventInfoPopup.vue`
- `plugins/agenda/frontend/components/AgendaEventModal.vue`
- `plugins/agenda/frontend/components/AgendaSidebar.vue`
- `plugins/agenda/frontend/components/AgendaWlSchedulePopup.vue`
- `plugins/agenda/frontend/components/ModernSelect.vue`
- `plugins/agenda/frontend/composables/useAgenda.js`
- `plugins/agenda/frontend/composables/useAgendaPopups.js`
- `plugins/agenda/frontend/composables/useAgendaDnD.js`
- `plugins/agenda/frontend/features/settings/components/SettingsTab*.vue`
- `plugins/agenda/frontend/styles/agenda-events.css`
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`
- `plugins/agenda/frontend/routes/settings/{Index,ColorPicker}.vue`
- `plugins/agenda/frontend/routes/customAttributes/Index.vue`
- `.gitignore`

---

## [1.4.4.45] - 2026-04-16T09:56:28-03:00

### Agenda: Refatoração com Composables, Settings UI e ModernSelect

Refatoração estrutural do dashboard da agenda em composables e nova UI de configurações.

**Mudanças (`plugins/agenda`):**
- `AgendaDashboard.vue` decomposto em composables: `useAgendaCrud`, `useAgendaDnD`, `useAgendaInit`, `useAgendaPopups`.
- Utilitários extraídos: `agenda-colors.js`, `agenda-constants.js`, `agenda-date.js`.
- Nova UI de configurações via `SettingsTabNotifications`, `SettingsTabOnlineBooking`, `SettingsTabSchedules`, `SettingsTabServices` com composables dedicados.
- Componente `ModernSelect.vue` substituindo selects nativos.
- Layout responsivo e estilos de toggle switch.
- Rotas e bootstrap limpos em `plugins/agenda/lib/agenda/engine.rb`.

**Arquivos Modificados:**
- `plugins/agenda/frontend/composables/use{Agenda,AgendaCrud,AgendaDnD,AgendaInit,AgendaPopups}.js`
- `plugins/agenda/frontend/utils/{agenda-colors,agenda-constants,agenda-date}.js`
- `plugins/agenda/frontend/components/ModernSelect.vue`
- `plugins/agenda/frontend/components/Agenda*.vue` (Dashboard, DeleteModal, DragGhost, EventCard, EventInfoPopup, EventModal, Header, MonthView, Sidebar, TimelineView, WlSchedulePopup)
- `plugins/agenda/frontend/features/settings/components/SettingsTab*.vue`
- `plugins/agenda/frontend/features/settings/composables/useSettings{Notifications,OnlineBooking,Schedules,Services}.js`
- `plugins/agenda/frontend/routes/{AgendaDashboard,customAttributes/Index,settings/Index}.vue`
- `plugins/agenda/lib/agenda/engine.rb`
- `plugins/agenda/db/seeds/treatments.rb`

---

## [1.4.4.44] - 2026-04-15T18:52:16-03:00

### Arquitetura: Modularização em Plugins (Agenda, Patients, Financial, Beclinic Core)

Isolamento dos módulos do Klivy em engines Rails dedicadas, alinhado à análise arquitetural de 2026-04-12.

**Mudanças:**
- `plugins/agenda`: controllers/models de agenda (AgendaEvent, AgendaService, Slot, WaitingList) + frontend Vue + engine registrada.
- `plugins/patients`: controllers/models de prontuário (Patient, Anamnesis, ClinicalNote, ExamFolder, ExamMedia, Document, TreatmentPlan, etc.) + frontend Vue + engine.
- `plugins/financial`: controllers/models do financeiro (AccountTransaction, BankAccount, CashRegister, FinancialCategory, CommissionRule, DreCalculator, etc.) + frontend Vue + engine.
- `plugins/beclinic_core`: core Klivy com `BeclinicPermissions`, `AccountProfile`, `TeamProfile`, `UserProfile` e frontend de roles/permissões.
- Migration `20260415185500_create_beclinic_profiles.rb` extrai atributos do `Account`/`Team`/`User` para tabelas de profile separadas.
- Scripts auxiliares em `script/` para a migração automática de backend/frontend.
- Documentação reorganizada em `docs/01-product/`, `docs/02-architecture/`, `docs/03-engineering/`, incluindo `PRD.md`, `ANALISE_ARQUITETURAL.md`, `MAPA_MODULOS.md`.
- `AGENTS.md` e rake task `auto_annotate_models` atualizada.

**Arquivos Modificados:**
- `plugins/agenda/**/*`, `plugins/patients/**/*`, `plugins/financial/**/*`, `plugins/beclinic_core/**/*`
- `app/models/{account,team,user}.rb`
- `db/migrate/20260415185500_create_beclinic_profiles.rb`, `db/schema.rb`
- `docs/01-product/PRD.md`, `docs/01-product/modules/*.md`
- `docs/02-architecture/*.md`, `docs/03-engineering/*.md`
- `docs/{ANALISE_ARQUITETURAL,MAPA_MODULOS}.md`
- `docs/notes/*.md`, `docs/plans/*.md`
- `AGENTS.md`
- `script/migrate_*_backend.rb`, `script/migrate_*_frontend.rb`, `script/setup_*_engine.rb`
- `lib/tasks/auto_annotate_models.rake`

---

## [1.4.4.43] - 2026-04-14T23:00:24-03:00

### DevOps: Containerização Dev (Rails + Vite) com Polling File Watchers

Ambiente de desenvolvimento conteinerizado, com builds separados para Rails e Vite.

**Mudanças:**
- `Dockerfile` e `Dockerfile.vite` customizados com entrypoints dedicados.
- `docker-compose.yaml` orquestrando Rails + Vite + serviços auxiliares.
- Polling file watchers habilitados para Vite (necessário dentro do container em Windows/WSL).
- Documentação de setup em `docs/03-engineering/docker.md`.
- Ajustes responsivos na agenda mobile (primeiras iterações).

**Arquivos Modificados:**
- `Dockerfile`, `Dockerfile.vite`
- `docker-compose.yaml`
- `docs/03-engineering/docker.md`
- `config/vite.json`, `vite.config.ts`
- `plugins/agenda/frontend/routes/AgendaDashboard.vue`

---

## [1.4.4.42] - 2026-04-12T19:30:02-03:00

### Agenda: Layout Responsivo Mobile (Primeiras Iterações)

Início do trabalho de responsividade no dashboard da agenda para uso em tablets/celulares, antes da refatoração maior em composables.

**Mudanças:**
- Ajustes no grid/scroll em `AgendaDashboard.vue` e componentes auxiliares para viewports < 768px.

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.41] - 2026-04-12T13:07:10-03:00

### Documentação: Rebranding Klivy, PRD e Análise Arquitetural

Estabelecimento dos documentos fundacionais do Klivy como produto: PRD, análise arquitetural de isolamento de módulos e reorganização de scripts/docs.

**Mudanças:**
- `README.md` reescrito para Klivy.
- `docs/01-product/PRD.md` criado.
- `docs/ANALISE_ARQUITETURAL.md` descreve o isolamento entre Klivy e BeClinic/Chatwoot.
- Scripts de desenvolvimento reorganizados e `docs/notes/changelog_Qwen.md` adicionado (histórico do assistente Qwen).
- `.gitignore` ajustado para remover cache do pnpm.

**Arquivos Modificados:**
- `README.md`
- `docs/01-product/PRD.md`
- `docs/ANALISE_ARQUITETURAL.md`
- `docs/notes/changelog_Qwen.md`
- `.gitignore`

---

## [1.4.4.39] - 2026-04-09T17:00:00-03:00

### Agenda: Intervalo de Visualização do Calendário (15min / 30min / 60min)

Implementação de configuração de intervalo de tempo na grade do calendário, permitindo alternar entre visualizações de 15 minutos, 30 minutos ou 1 hora.

**Problema:**
A agenda era exibida apenas em janelas de 1 hora (00:00, 01:00, 02:00...), sem flexibilidade para visualizações mais granulares. Usuários que precisavam de agendamentos mais precisos (ex: consultas de 15 ou 30 minutos) não tinham essa opção.

**Solução:**
1. **Backend:**
   - Adicionada coluna `slot_interval_minutes` (integer, default: 60) na tabela `agenda_settings` via migration.
   - Atualizado modelo `AgendaSetting` com validação de inclusão (15, 30, 60).
   - Atualizado `AgendaSettingsController` para expor e aceitar `slot_interval_minutes` no payload JSON.

2. **Frontend — Settings:**
   - Novo campo "Intervalo da visualização" na aba "Agendamento online" das configurações da agenda, com opções 15min/30min/60min.
   - Valor persistido via `AgendaSettingsAPI` e carregado no `agendaSettingsData`.

3. **Frontend — Calendar Grid:**
   - `dayHours` computed property agora gera slots dinâmicos baseados no `slot_interval_minutes` (ex: 15min → "00:00", "00:15", "00:30", "00:45"...).
   - `rowHeight` computed property escala proporcionalmente: 15min→20px, 30min→40px, 60min→80px.
   - Altura das linhas do grid aplicada via inline style (`:style="{ height: ... }"`), removendo o `height: 80px` hardcoded do CSS.
   - Drag-and-drop, redimensionamento e snapping de eventos agora respeitam o intervalo configurado.
   - Linha de tempo atual (`currentTimeLineStyle`) e scroll automático (`scrollToCurrentTime`) usam o `rowHeight` dinâmico.

4. **Internacionalização:**
   - Chaves i18n adicionadas em `pt_BR` e `en` sob `AGENDA.SLOT_INTERVAL.*` para labels e opções.

**Arquivos Modificados:**
- `app/models/agenda_setting.rb`
- `app/controllers/api/v1/accounts/agenda_settings_controller.rb`
- `app/javascript/dashboard/routes/agenda/settings/Index.vue`
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`
- `app/javascript/dashboard/i18n/locale/en/settings.json`

---

## [1.4.4.40] - 2026-04-09T18:30:00-03:00

### Agenda: Correção — Botões de Alternância de Visualização (Mês/Semana/Dia) não Respondiam

**Problema:**
Ao clicar nos botões "Semana" ou "Dia" no cabeçalho da agenda, a visualização permanecia presa no Mês. O clique funcionava corretamente (`viewMode` era atualizado), mas a timeline ficava vazia pois o scroll continuava em posição 0 (topo) — sem eventos visíveis no horário atual.

**Causa raiz:**
O método `setViewMode(mode)` apenas atualizava `this.viewMode` sem chamar `scrollToCurrentTime()` para posicionar a timeline na hora atual. Ao entrar na view de Semana ou Dia, o usuário chegava no topo da grade (00:00), onde não há eventos, dando a impressão de que nada havia mudado.

**Solução:**
Adicionado `this.$nextTick(() => this.scrollToCurrentTime())` dentro do `setViewMode` sempre que o modo não for `month`, garantindo scroll automático ao horário atual ao trocar de visualização.

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.38] - 2026-04-09T11:15:00-03:00

### Financeiro: UI Ajustes Dinâmicos de KPIs e Correção 422 no DB

Ajustes baseados no workflow de design para re-arranjo da leitura de dados e correções de validação de modelo que recuavam salvamentos no módulo financeiro.

**Problemas corrigidos & UI/UX:**
1. **Erro 422 na Criação de Despesas ("A Pagar"):** A validação `payment_source: ""` ativava o array restrito do Model e as `check_constraints` lógicas do banco de dados, pois strings vazias do Javascript não contam nativamente como NULLs do Postgre.
2. **Layout das "Entradas Hoje" Engessado:** O bloco sofria do wrapper padrão em estilo bloco listrado (`.financial-block`) com título e moldura, e estava misturado na grade draggagle inferior, desalinhando-se com os mockups.

**Soluções Aplicadas:**
1. **AccountTransaction Fix:** Em `app/models/account_transaction.rb`, adicionado helper privado ativado em `before_validation` responsável por rastrear campos `payment_*` retornando com `.blank?`, transformando a string em `.nil`, deixando a entrada limpa para persistência.
2. **Reordenação e Estilização de KPIs (`Standalone`):**
   - O component `<FinancialKpiCards>` foi retirado do map de arrasto (`vuedraggable`) e de seu array padrão global `DEFAULT_BLOCKS`. Elevamos o component ao Topo Abosluto da página, aparecendo antes dos minicards de "Receita Líquida".
   - Todo `<div class="financial-standalone-kpi__header">` foi deletado.
   - Classes CSS condicionais (`.kpi-card--entradas`, `--saidas`, `--saldo`, `--inadimplencia`) injetaram cores pálidas/translúcidas aos _backgrounds_ seguindo estética abobada (High-End UX), reajustando seus opacos paramétricos também no `.dark`.

**Arquivos Modificados:**
- `app/models/account_transaction.rb`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/features/financial/components/FinancialKpiCards.vue`
- `app/javascript/dashboard/features/financial/financial.css`

---

## [1.4.4.37] - 2026-04-09T16:00:00-03:00

### Financeiro: Revisão Arquitetural — Bugs Críticos, Performance e Layout Definitivo

Auditoria completa do módulo financeiro corrigindo crashes de navegação, erros 500 em endpoints, N+1 queries, dados silenciados e layout quebrado (double scroll).

**Problemas corrigidos:**

1. **Navegação quebrada entre páginas do Financeiro** — `NewVsReturningPatients.vue` acessava `chartColors.value.tickColor` (propriedade inexistente no composable `useChart`), causando crash no render que corrompia o VDOM do Draggable e impedia unmount/navegação para qualquer outra página (Fluxo de Caixa, A Receber, etc.).
2. **DOM corruption no unmount (v-show + vuedraggable)** — `v-show` dentro do slot `#item` do vuedraggable tentava manipular `style.display` em nodes já removidos pelo SortableJS, gerando cascata de `Cannot read 'parentNode' of null`. Substituído por `v-if`.
3. **DRE Waterfall retornando 500** — `DreCalculator` fazia `GROUP BY financial_categories.dre_line` mas a coluna não existe na tabela. Corrigido para agrupar por `cost_type` (`fixo`/`variavel`).
4. **Ticket Trend retornando 500** — Controller passava `user_id:` mas o service espera `professional_id:` (`ArgumentError`).
5. **DOW offset descartava segunda-feira do heatmap** — `EXTRACT(DOW)` retorna 1 para segunda, mas o código subtraía 2 (resultando em -1, filtrado). Corrigido para `- 1`.
6. **N+1 no PatientRetentionService** — 1 query por paciente para buscar `first_event_month`. Com 500 pacientes × 12 meses = ~6.000 queries/request. Substituído por uma única query com `GROUP BY contact_id + minimum(:starts_at)`.
7. **Funil de conversão com dados inconsistentes** — `count_comparecidos` e `count_orcados` não filtravam por `event_type: 'consultation'` (diferente de `count_agendados`). `Fechados` era idêntico a `Orçados`. Corrigido: filtro consistente + `Fechados` agora cruza com `AccountTransaction` (receita efetiva).
8. **`rescue StandardError` silenciando bugs** — 7 ocorrências nos services analytics engoliam erros reais (a causa original dos 500 nunca aparecia nos logs). Removidos.
9. **CSS: Double scroll e KPI cards não full-width** — `column-count: 2` (CSS Multi-Column) não suporta `column-span` em filhos de vuedraggable. Substituído por `display: grid` + `grid-template-columns: repeat(2, 1fr)` com `.financial-block--full { grid-column: 1 / -1 }`.
10. **Sparklines vazando do card** — Container sem `overflow: hidden`, canvas sem posicionamento, eixo Y sem `grace`. Corrigido com CSS e opções Chart.js.
11. **`isBlockVisible()` não definida** — Template chamava a função mas ela não existia no `<script setup>`. Implementada com suporte a `ui_settings.financial_dashboard_hidden`.

**Arquivos Modificados:**
- `app/services/financial/agenda_analytics_service.rb`
- `app/services/financial/patient_retention_service.rb`
- `app/services/financial/conversion_analytics_service.rb`
- `app/services/financial/dre_calculator.rb`
- `app/controllers/api/v1/accounts/financial_reports_controller.rb`
- `app/javascript/dashboard/features/financial/components/NewVsReturningPatients.vue`
- `app/javascript/dashboard/features/financial/components/FinancialKpiCards.vue`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/features/financial/financial.css`

---

## [1.4.4.36] - 2026-04-09T09:16:00-03:00

### Financeiro: Refatoração Analítica e UI/UX Dashboard (`payment_source` e `AgendaEvent`)

Revisão estrutural e correção de todos os gráficos "quebrados" da arquitetura financeira, adaptando a lógica analítica ao banco de dados real (`AgendaEvent` e `account_transactions`). Melhoria substancial no layout do front-end do painel para evitar renderizações infinitas.

**Problema:**
1. A arquitetura de analytics financeira havia sido codificada espelhando modelos que não existiam no contexto (ex: modelo `Appointment` inexistente, ao invés de usar `AgendaEvent`). Isso gerou exceções 500 em 9 componentes da dashboard financeira.
2. Analytics de receita buscavam agrupar informações por transação baseada em "Origem da Receita" (Planos, Particular, etc), todavia a tabela `account_transactions` não possuia a coluna `payment_source`, causando Erros Undefined Column no backend.
3. Consultas a tabelas financeiras para KPIs de Inadimplência tentavam puxar o campo relacional `user_id`, sendo que o esquema atual utiliza o `professional_id`.
4. O Dashboard renderizava inúmeras instâncias vazias da classe `.financial-block` oriundas de grids draggables com condicionais falhas (v-if), causando scrollbars duplas na tela; os "Entradas Hoje" não preenchiam a grade panoramicamente.

**Solução:**
1. **Ruby Services Rewritten:**
   - Reescrevemos por completo o `ConversionAnalyticsService`, `AgendaAnalyticsService` e `PatientRetentionService` para ancorar no modelo existente `AgendaEvent` usando sua coluna temporal `starts_at`.
   - Adicionamos pareamentos exatos das 7 tipagens `status` do `AgendaEvent` às macros analíticas (Ex: `arrived`, `in_progress`, `completed` mapeados como 'Comparecidos/Aprovados').
2. **`payment_source` Migration Database:**
   - Criada migration para injeção de coluna `payment_source` (string) em `account_transactions` com check_constraints SQL limitando valores (`particular`, `convenio`, `plano` e `outro`) e indexação.
   - Atualizados serializadores, models (`PAYMENT_SOURCES`) e controller (`transaction_params`) para assimilar o campo. O Componente `<TransactionModal.vue>` e os JSON de tradução foram adaptados.
3. **Foreign Keys Refatoradas:**
   - Reajustado o apontamento nas consultas complexas de `ProfessionalRevenueService` e `DelinquencyCalculator`, substituindo a quebra gerada pelo `user_id` e consolidando o fluxo com `professional_id`.
4. **CSS/Vue Refactoring:**
   - Inseridas diretivas `v-show="isBlockVisible(element.id)"` no renderizador arrastável impedindo a geração indiscriminada de div's no `FinancialDashboard.vue`, matando o bug do endless scroll.
   - Injeção de `column-span: all` via bind dinâmico `:class="{ 'financial-block--full': element.id === 'kpi_cards' }"` para os KPI cards adquirirem aspecto span total.

**Arquivos Modificados/Adicionados:**
- `db/migrate/...add_payment_source_to_account_transactions.rb`
- `app/services/financial/professional_revenue_service.rb`
- `app/services/financial/delinquency_calculator.rb`
- `app/services/financial/revenue_analytics_service.rb`
- `app/services/financial/conversion_analytics_service.rb`
- `app/services/financial/agenda_analytics_service.rb`
- `app/services/financial/patient_retention_service.rb`
- `app/models/account_transaction.rb`
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`
- `app/javascript/dashboard/features/financial/components/TransactionModal.vue`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json`

---

## [1.4.4.35] - 2026-04-07T12:35:00-03:00

### UI/UX: Light Mode — PatientRecordPopup (Popup do Prontuário na Conversa)

Migração completa do `PatientRecordPopup.vue` do modo escuro legado (`#0f1117`, cores hardcoded) para o padrão **dual-theme** (light/dark) do sistema, usando variáveis CSS `rgb(var(--slate-N))` em todos os elementos.

**Problema:**
1. O popup lateral de prontuário (exibido nas conversas do Klivy) usava cores hardcoded do dark mode (`background: #0f1117`, `color: #f1f5f9`, bordas `rgba(255,255,255,0.09)`) que tornavam o componente completamente ilegível no light mode — fundo quase preto em cima de interface branca.
2. O popup estava posicionado no canto superior direito da tela (`align-items: flex-start; justify-content: flex-end`), tornando a leitura desconfortável em telas grandes.

**Solução:**
1. **Migração total para variáveis CSS dual-theme:**
   - Fundo do painel: `rgb(var(--slate-1))` (branco no light, escuro no dark)
   - Bordas: `rgb(var(--slate-4))` (visível em ambos os temas)
   - Textos primários: `rgb(var(--slate-12))`, secundários: `rgb(var(--slate-11))`, terciários: `rgb(var(--slate-9))`
   - Spinner de loading: usa `rgb(var(--slate-4))` como trilho base
   - Scrollbar customizada adaptada ao tema
   - Botão de fechar (`prp-close`): hover com `rgb(var(--slate-3))` sutil

2. **Badges de status patient corrigidos para dual-theme:**
   - `prp-pill-novo` → `#2563eb` (azul legível em ambos os temas, era `#60a5fa` dark-only)
   - `prp-pill-ativo` → `#16a34a` (verde sólido, era `#4ade80` dark-only)
   - `prp-pill-faltoso` → `#d97706` (âmbar), `prp-pill-alta` → `#9333ea` (roxo)
   - Dots de status (`prp-dot-*`) também corrigidos para cores legíveis em ambos

3. **Tags clínicas (`prp-tag--*`) com cores semânticas dual-theme:**
   - Condições: azul `rgba(37,99,235,0.12)` + `#2563eb`
   - Alergias: vermelho `rgba(220,38,38,0.12)` + `#dc2626`
   - Medicamentos: roxo `rgba(147,51,234,0.12)` + `#9333ea`
   - Contraindicações: âmbar `rgba(217,119,6,0.12)` + `#d97706`

4. **Seção financeira corrigida:**
   - `prp-fin-paid` → `#16a34a` (era `#4ade80` dark-only)
   - `prp-fin-open` → `#d97706` (era `#fbbf24` dark-only)
   - `prp-fin-overdue` → `#dc2626` (era `#f87171` dark-only)
   - `prp-fin-credit` → `#2563eb` (era `#22d3ee` dark-only)

5. **Centralização do modal:** Alterado `.prp-overlay` de `align-items: flex-start; justify-content: flex-end` (canto superior direito) para `align-items: center; justify-content: center` — popup agora aparece centrado na tela.

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/conversation/contact/PatientRecordPopup.vue` — migração completa do `<style scoped>` para dual-theme + centralização

---

## [1.4.4.34] - 2026-04-05T20:32:00-03:00

### Financeiro: UI Enhancement do A Pagar e Validação de Despesas Recorrentes

Melhorias no design da página de "A Pagar", consistência dos botões de exportação e introdução do sistema de validação explícita de erros em "Despesas Recorrentes".

**Problema:**
1. Botões de exportação de PDF inconsistentes nas listagens financeiras. Falta de padronização nas telas de listagem.
2. Tabela de "A Pagar" não trazia visibilidade rápida para itens com recorrência associada. Os cards totalizadores mostravam métricas simples demais (faltava alinhamento visual com o "Fluxo de Caixa").
3. Tentativa de salvar despesas recorrentes com campos em branco resultava em falha invisível de backend (Erro 422 - `Translation missing: pt_BR.activerecord...`). Nenhum alerta impedia a interface de parecer "congelada".

**Solução:**
1. **Padronização dos Botões de Exportação:** Uniformizado o label para "Gerar PDF" em todas as áreas (`Receivables.vue`, `Payables.vue`, `CashFlow.vue`, `DRE.vue`, `Reports.vue`). Ajustado o distanciamento/margins entre botões adjacentes.
2. **Dashboard de "A Pagar" Avançado:**
   - Adicionada coluna "Recorrência" (`is_recurring`) à listagem da grid para informar se a transação partiu de ciclo repetido, acoplado com badge (`success/neutral`).
   - Implementação de 4 Novos *Status Cards* inspirados no CashFlow: **Total A Pagar**, **Total Recorrente**, **Próximos a Vencer** e **Transações**; sendo orquestrados via `meta` keys processadas no Controller `account_transactions_controller`.
3. **Padrão de Validação Full-Stack (Frontend e Backend):**
   - Interceptação síncrona visual no `saveExp` antes da requisição API, disparando alertas via `useAlert` do Vue 3 requerendo campos essenciais.
   - Atualizados os metadados do locale `pt_BR.yml` criando descrições exatas de erros de validação do módulo `recurring_expense`.
   - Modificado backend (`RecurringExpensesController`) para devolver arrays stringificados dos erros no bad_request, sanando os silent 422 errors.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/Payables.vue`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue`
- `app/javascript/dashboard/features/financial/pages/Receivables.vue`
- `app/javascript/dashboard/features/financial/pages/DRE.vue`
- `app/javascript/dashboard/features/financial/pages/Reports.vue`
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue`
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`
- `app/controllers/api/v1/accounts/recurring_expenses_controller.rb`
- `config/locales/pt_BR.yml`

---

## [1.4.4.33] - 2026-04-05T17:49:11-03:00

### Financeiro: Aprimoramentos no PDF e Refinamentos no Filtro de Fluxo de Caixa

Implementação de visualização prévia (preview) nos relatórios PDF, correção de erros críticos no Prawn ao lidar com encodings e grids de tabelas flexíveis, e modernização da escolha de datas no Fluxo de Caixa.

**Problema:**
1. Os relatórios financeiros via PDF iniciavam downloads automáticos compulsórios, não permitindo revisar os dados antes de salvar o arquivo no PC.
2. Tentativas de baixar alguns relatórios estouravam Erro 500 vindo do backend. Motivos investigados envolveram incompatibilidade da fonte local do `prawn` com Emojis (UTF-8 `📅`) no cabeçalho e `prawn-table` crashando ao receber propriedade `column_widths: nil`.
3. Tela de Fluxo de Caixa não permitia a seleção de intervalos livres de dias para gráficos ou geração de PDF, presa a três botões rígidos (Hoje, Semana e Mês).

**Solução:**
1. **Preview inteligente na emissão:** Novo comportamento em `pdfs.js` com o uso de `window.open` instanciando Web Blobs injetáveis via Headers Auth. Agora a tela carrega o documento gerado em uma aba nova.
2. **Estabilização Prawn / Ruby:** 
   - Remoção do emoji 📅 e implementação do novo label `"Período: "` no construtor `BasePdf`, evitando falha de encoding Windows-1252 em containers.
   - Refatoração preventiva do `.draw_styled_table` que agora encapsula e instrupula hashes (`**table_options`) em arrays somente quando houver instâncias reais declaradas de column_widths, blindado de Null/Type Errors.
3. **DateRangePicker em toda a camada:** Integração fluida do `<DateRangePicker />` (já implementado nas outras abas) no `CashFlow.vue`. O componente foi ancorado diretamente no Data Fetch da tela (`params.period = 'custom'`), orquestrando relatórios Prawn e Chart dinâmicos perfeitamente a partir de datas do calendário.

**Arquivos Modificados:**

- `app/javascript/dashboard/features/financial/api/pdfs.js`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue`
- `app/services/financial/pdf/base_pdf.rb`

---

## [1.4.4.32] - 2026-04-05T16:00:00-03:00

### Financeiro: Integração do Financeiro Central com Consulta de Paciente e Refinamento de UI

Conclusão do fluxo que permite criar lançamentos no "Financeiro Central" associando um paciente via Autocomplete, e o reflexo dessa conta manual diretamente dentro do Histórico Financeiro do Prontuário do Paciente.

**Problema:**

1. As Entradas e Saídas do Financeiro não possuíam vínculos práticos para associar despesas manuais não planejadas com os pacientes no front.
2. Contas criadas de modo manual com um `patient_id` anexado ficavam salvas do lado do Financeiro Central (model `AccountTransaction`), porém o Prontuário do Paciente só listava os pagamentos de Tratamentos e Orçamentos (model `Transaction`), deixando as entradas manuais "invisíveis" aos olhos do médico no dossiê do paciente.
3. No Componente do Caixa, o layout do `<TransactionModal>` continha campos de input desconexos, labels desalinhadas, sem tratamento para buscas responsivas e sem feedback limpo.

**Solução:**

1. **Adicionado Seletor Rápido de Pacientes (`TransactionModal.vue` e `patients/index.js`):**
   - Criação de interface limpa com busca na `/api/patients` under-the-hood (acionada após digitação via debounce) e fechamento do tooltip interativo inteligente através do event watcher `onClickOutside`. O ID selecionado agora trafega via JSON pro Create do Transaction de conta.
   
2. **Refinamento Cirúrgico UI/UX (`TransactionModal` & `financial.css`):**
   - Conserto milimétrico na simetria vertical das caixas. Remoção de margens (`mb-1.5`) na root grid e nas labels flex.
   - Refatoração do feedback da captura do paciente: A view do item selecionado agora substitui lixeiras vermelhas poluídas por um emblema verde sutil com tipografia em caps no topo do input de pesquisa (`VINCULADO: [Nome do Paciente]`). 

3. **Espelhamento Analítico no Prontuário (`transactions_controller.rb` e `Record.vue`):**
   - Refatoração no Controller do Prontuário: Em vez de um complexo SyncService entre dois bancos de dados para as transações manuais, a `index` de transações do paciente constrói simultaneamente arrays puxando do modelo de `Transaction` (Orçamentos) E concatena em tempo real quaisquer entradas perdidas no model `AccountTransaction` que retenham a key do paciente sem origens atreladas.
   - No frontend, transações puras vindas do AccountTransaction possuem as tags unificadas por flag reativa e recebem um novo tratamento com Proteção nos Botões (`v-if="!tx.is_manual"`), prevenindo requisições na API de tratamentos erradas. Em vez dos atalhos de WhatsApp/Comprovantes, essas linhas exibem um belo Badge referencial: `⚡ Lançamento Manual`.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/components/TransactionModal.vue`
- `app/javascript/dashboard/api/patients/index.js`
- `app/controllers/api/v1/accounts/patients/transactions_controller.rb`
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

## [1.4.4.31] - 2026-04-05T09:35:00-03:00

### Financeiro: Integração Contas Bancárias ↔ Fluxo de Caixa (FINANCIAL_ARCHITECTURE.md — Etapa 1)

Implementação da primeira etapa da arquitetura financeira definida em `FINANCIAL_ARCHITECTURE.md`: vinculação real entre contas bancárias e transações, com reflexo imediato no Fluxo de Caixa.

**Problema:**
As contas bancárias cadastradas em Configurações > Contas Bancárias existiam de forma isolada — o `bank_account_id` nunca era preenchido ao liquidar recebíveis (era sempre `null`), portanto o `opening_balance` e o `current_balance` das contas nunca refletiam a realidade. O Fluxo de Caixa não exibia o saldo patrimonial real das contas.

**Solução — 5 arquivos alterados:**

1. **`ReceivePaymentModal.vue`** — Adicionado campo `"Conta de Destino"` (select com contas bancárias ativas). Carrega contas via API no `onMounted`. Pré-seleciona automaticamente se só houver uma conta. O `bank_account_id` é incluído no evento `confirm`.

2. **`accountTransactions.js`** — Método `receive()` agora aceita `bankAccountId` e o inclui no `FormData` enviado ao backend.

3. **`Receivables.vue`** — O handler `handleReceiveConfirm` extrai e passa `bankAccountId` para o `transactionsApi.receive()`.

4. **`account_transactions_controller.rb`** — Action `receive` agora aceita e persiste `bank_account_id` na transação ao liquidar, conectando o dinheiro à conta correta.

5. **`CashFlow.vue`** — O `fetchData()` agora carrega em paralelo o fluxo de caixa E as contas bancárias. Adicionado 4º card **"Saldo em Caixa"** calculado como:
   `saldo_final = opening_balance + entradas_do_período - saídas_do_período`
   Onde `opening_balance = initial_balance das contas + movimentações históricas`, implementando a fórmula do FINANCIAL_ARCHITECTURE.md: `Saldo Atual = Saldo Inicial + ΣEntradas - ΣSaídas`

**CSS:**
- Classes `.cf-balance-card`, `.cf-balance-label`, `.cf-balance-icon`, `.cf-balance-hint` adicionadas ao `financial.css`

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/components/ReceivePaymentModal.vue`
- `app/javascript/dashboard/features/financial/api/accountTransactions.js`
- `app/javascript/dashboard/features/financial/pages/Receivables.vue`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue`
- `app/javascript/dashboard/features/financial/financial.css`
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`

---

## [1.4.4.30] - 2026-04-04T10:54:00-03:00


### UI/UX: Redesign Completo — Aba Plano de Tratamento

Refatoração total do `TreatmentPlanTab.vue`. O componente estava usando classes `tp-plan-*`, `tp-section-*`, `tp-table-*`, etc. que **não existiam em nenhum CSS**, causando: nomes de procedimentos quase invisíveis (cor herdada do tema escuro), barra total com fundo cinza-escuro distorcido, badges de status ilegíveis e layout completamente quebrado no light mode.

**Problemas corrigidos:**
- Classes CSS indefinidas (`tp-table-head`, `tp-table-row`, `tp-cell-name`, `tp-total-row`, etc.) causavam herança de estilos escuros do Chatwoot
- Nome do procedimento ("Limpeza", "Avaliação") aparecia em cinza muito claro — ilegível
- Linha "Total Estimado" renderizava com fundo cinza-escuro e texto branco (herança dark)
- Badge "PROPOSTO" em maiúsculo e cor incorreta
- Títulos h3 com `text-slate-100` (branco) — invisível no light mode
- Ícone de seção `reg-section-icon reg-icon-blue` com fundo colorido (padrão errado)

**Solução — reescrita total com `<style scoped>`:**
- Sistema `tp-*` completo definido no próprio componente (scoped) — zero dependência de classes globais indefinidas
- Cores via `rgb(var(--slate-N))` — dual-theme automático
- **Tabela**: `tp-th` (labels uppercase 11px), `tp-td--name` (slate-12 forte), `tp-td--muted` (slate-9), `tp-td--strong` (slate-12 bold)
- **Total estimado**: fundo `slate-2`, label uppercase, valor azul `#2563eb` — limpo e legível
- **Badges de status**: `tp-status--blue` (proposto) e `tp-status--green` (aprovado) com `rgba` semitransparente
- **Cabeçalho do plano**: fundo `slate-2`, ícone verde 32px com `rgba(22,163,74,0.12)`, textos slate-12/slate-9
- **Seções internas**: label uppercase 11px slate-9, corpo com padding uniforme
- **Botões de ação**: `tp-action-btn` com borda slate-4, hover sutil; variantes `--green` e `--danger`
- **Empty state**: ícone em container slate-3, textos slate-10/slate-8
- **Print**: overrides para `@media print` preservando legibilidade

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/tabs/TreatmentPlanTab.vue` — reescrita total

---

## [1.4.4.29] - 2026-04-04T10:40:00-03:00

### UI/UX: Modal "Novo Procedimento" — Refatoração para Padrão npm-*

Auditoria completa e refatoração do modal "Novo Procedimento/Editar Procedimento" no `Record.vue`. O modal anterior usava classes Tailwind inline com ícone grande no header (`h-9 w-9 bg-slate-100`) e labels em `UPPERCASE tracking-wider`, divergindo completamente do padrão estabelecido pelo `NewPatientModal.vue`.

**Problemas corrigidos:**
- Ícone `i-lucide-plus-circle` com container `h-9 w-9 bg-slate-100` no header — removido (padrão Novo Paciente não tem ícone no header)
- Labels em `UPPERCASE tracking-wider` — corrigido para case normal com `tp-label` (12px, font-weight 600)
- Botão "Confirmar" usando `btn-modal-primary` que estava sendo sobrescrito pelo CSS do Chatwoot — migrado para `tp-btn-submit` scoped no `record.css`
- Botão "Cancelar" sem distinção visual clara — migrado para `tp-btn-cancel` com borda `--border-strong`
- Estrutura Tailwind inline toda migrada para classes `tp-*` globais

**Novo sistema `tp-*` para modais (adicionado ao `record.css`):**
- `.tp-modal-overlay` — overlay `rgba(0,0,0,0.45)` com `backdrop-filter: blur(4px)`, `z-index: 99999`
- `.tp-modal-card` — card `rgb(var(--slate-1))`, borda `slate-4`, `border-radius: 16px`
- `.tp-modal-header` — padding `22px 22px 16px`, borda inferior `--border-strong`
- `.tp-modal-title` — 16px, font-weight 600, `slate-12`
- `.tp-modal-subtitle` — 13px, `slate-9`
- `.tp-modal-close` — 28×28px, sem borda, hover `slate-3`
- `.tp-modal-body` — flex-column, gap 14px, padding `16px 22px`
- `.tp-row-2` — grid 2 colunas, gap 12px
- `.tp-label` — 12px, font-weight 600, `slate-11`
- `.tp-input` — `slate-2` bg, `--border-strong` borda, `blue-9` focus, zero box-shadow
- `.tp-btn-cancel` — transparente com borda `--border-strong`, hover `slate-3`
- `.tp-btn-submit` — azul sólido `#3b82f6`, hover `#2563eb`, zero box-shadow

**Atualização das classes globais `btn-modal-*`:**
- `btn-modal-primary`: removido `box-shadow` (proibido pelo StyleMD)
- `btn-modal-cancel`: migrado para `--border-strong` para consistência

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — modal Novo Procedimento reescrito com `tp-*`
- `app/javascript/dashboard/routes/dashboard/patients/record.css` — sistema `tp-*` de modal + fix `btn-modal-*`

---

## [1.4.4.28] - 2026-04-04T10:40:00-03:00

### UI/UX: Light Mode — Prontuário Clínico (Série Completa)

Migração completa do módulo de Prontuário (Record.vue) do modo escuro legado para o padrão de **Light Mode** do sistema, com criação do guia de design `STYLEMD.md`.

#### Histórico de Evoluções Clínicas (`.evo-note-*`)

- Convertidas todas as cores hexadecimais hardcoded (modo escuro) das classes `.evo-note-*` para variáveis semânticas (`rgb(var(--slate-N))`).
- **Tipografia corrigida:**
  - Labels (Queixa, Avaliação, Conduta…) → `font-weight: 700; color: #0f172a` (preto-escuro, negrito proeminente)
  - Valores das respostas → `font-weight: 500; color: #475569` (cinza médio-escuro, legível)
- **Campo "Intercorrência":** Removida a classe `evo-note-field--alert` do HTML e toda a CSS que injetava fundo vermelho/amarelo. O campo agora é visualmente idêntico a todos os outros campos.
- **Bordas e separadores** dos campos migrados para `rgb(var(--slate-3/4))`.

#### Modal "Novo Procedimento" (`.delete-modal-card`)

- Fundo do modal corrigido de gradiente escuro (`#1e293b → #0f172a`) para **branco sólido** (`bg-white border-slate-200 shadow-xl`).
- Ícone do header: tamanho reduzido de `h-10 w-10 size-5` para `h-9 w-9 size-4`; fundo alterado para `bg-slate-100 text-slate-600` (neutro claro); ícone estilo **outline** (não preenchido).
- Labels do formulário: cor alterada de `text-slate-400` para `text-slate-600`.
- Títulos e subtítulo: `text-slate-900` e `text-slate-500`.

#### Sistema de Botões de Modal — Criado `StyleMD`

- **`btn-modal-primary`** (CSS em `record.css`): Botão azul sólido `#2563eb`, texto branco, hover `#1d4ed8`, estado disabled com `opacity: 0.45`. Imune a overrides do Chatwoot via `!important`.
- **`btn-modal-cancel`** (CSS em `record.css`): Fundo transparente, **borda cinza** (`rgb(var(--slate-5))`), hover com fundo `slate-2`. Nunca mais botão cancelar invisível.
- Seletor global `button.bg-blue-600` adicionado ao `record.css` para forçar o azul mesmo quando CSS do Chatwoot sobrepõe Tailwind.
- Modal "Novo Procedimento" migrado para as classes `btn-modal-primary` e `btn-modal-cancel`.

#### Criação do `STYLEMD.md`

Guia de design oficial do BeClinic criado com:
- Tabela de variáveis semânticas de cor
- Estrutura HTML canônica de modais
- Regras visuais (ícones outline, fundo branco, etc.)
- Referência de botões (`btn-modal-primary` / `btn-modal-cancel`)
- Anti-padrões documentados (o que **não** fazer)
- Tipografia padrão do Histórico de Evoluções

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`
- `app/javascript/dashboard/routes/dashboard/patients/tabs/EvolutionTab.vue`
- `app/javascript/dashboard/routes/dashboard/patients/record.css`

**Arquivos Criados:**
- `STYLEMD.md` — Guia de estilo oficial do BeClinic

---

## [1.4.4.27] - 2026-04-03T21:05:00-03:00


### Funcionalidade: Busca Local na Lista de Conversas
**Modificações:**
- Implementada barra lateral expansível de busca (search input) em formato retrátil ("lupa") no cabeçalho das mensagens (`ChatListHeader.vue`).
- Estado local otimizado para filtragem de conversas por nome de contato de remetente (client-side) (`ChatList.vue`), incluindo evento do global bus para limpeza de campo baseada no estado entre abas.

### UI/UX: Correção de Estilos no Prontuário e Componentes
**Modificações:**
- Criação e padronização da classe utilitária semântica e multi-tema (dark/light) `.geral-header-btn` para o projeto conforme o `STYLE.md`.
- Correção massiva do problema visual do "Ghost Button" (botão transparente fundido com backgrouds claros), substituindo todas as ocorrências de `.btn-secondary flex items-center...` em headers e actions no escopo do Prontuário Clínico.
- Botões corrigidos/melhorados: `Agendar Consulta`, `Editar Ficha`, `Nova Anamnese`, `Salvar Rascunho` (Evolução e Anamnese), `Filtrar` e `Fotos Antes/Depois` (Procedimentos), `Ver na Agenda`, `Nova Pasta` (Exames), botões de ordenação da `Timeline`, e `Exportar PDF` (Auditoria).

**Arquivos Modificados:**
- `app/javascript/dashboard/components/ChatList.vue`
- `app/javascript/dashboard/components/ChatListHeader.vue`
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`
- `app/javascript/dashboard/routes/dashboard/patients/patients-index.css`
- `app/javascript/dashboard/routes/dashboard/patients/record.css`

## [1.4.4.26] - 2026-04-01T19:15:00-03:00
### Demo: Dados de Demonstração para Apresentação Comercial

**Seed de dados demo incluído na imagem:**
- 18 pacientes com dados brasileiros realistas (CPF, RG, endereço, convênio)
- 18 anamneses completas e individualizadas por especialidade
- 12 alertas críticos (alergia, gestante, marca-passo, oncológico, etc.)
- 6 notas clínicas assinadas e em rascunho
- 6 planos de tratamento com itens e sessões controladas
- 86 eventos na agenda (3 meses histórico + 6 semanas futuras)
- 117+ transações financeiras retroativas (Jan–Mar) com categorias reais
- Abril/2026: R$ 625.410 em entradas, R$ 408.009 em saídas, margem ~35%

**Arquivos Modificados:**
- `db/seeds/patients_demo_seed.rb`
- `db/seeds/patients_demo_seed_2.rb`
- `db/seeds/agenda_events_seed.rb`
- `db/seeds/financeiro_demo_seed_2.rb`
- `db/seeds/abril_financeiro_seed.rb`

---

## [1.4.4.25] - 2026-03-27T15:36:00-03:00

### Pacientes: Paginação + Historico Caixa + i18n AMOUNT

**Paginação na listagem de pacientes:**
- Implementado controle de paginação client-side na aba Pacientes (view lista e grade)
- Seletor de itens por página: 15 (padrão), 20, 50, 100
- Barra de paginação no rodapé da tabela exibindo "Exibindo X–Y de N pacientes"
- Navegação inteligente com ellipsis para listas com muitas páginas
- Reset automático para página 1 ao mudar filtro ou busca
- Scroll corrigido: `pt-list-wrap` e `pt-grid` com `flex-shrink: 0` garantem que o `pt-page` gere overflow e o `overflow-y: auto` funcione corretamente

**Histórico do Caixa (sessão anterior):**
- Histórico agrupado por data em accordion colapsável
- Cada dia exibe totais de suprimentos, sangrias e saldo calculado
- Carregamento sob demanda das movimentações ao expandir each dia
- Filtro de mês para o histórico

**i18n:**
- Adicionada chave `FINANCIAL.CASH_REGISTER.AMOUNT` em `pt_BR` ("Valor") e `en` ("Amount")

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Index.vue` — paginação, `pagedPatients`, `pageNumbers`, `goToPage`, `setPerPage`
- `app/javascript/dashboard/routes/dashboard/patients/patients-index.css` — `.pt-pagination*`, `flex-shrink: 0` nos wrappers
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — chave `AMOUNT`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chave `AMOUNT`

## [1.4.4.24] - 2026-03-27T13:10:00-03:00

### Financeiro: Correção na Exclusão de Categorias e Contas Bancárias

**Problema:** O botão de exclusão nas listas de "Categorias Financeiras" e "Contas Bancárias" dentro das Configurações do Financeiro falhava silenciosamente, ao passo que a exclusão em "Despesas Recorrentes" e "Regras de Comissão" funcionava perfeitamente. Como a API de Categorias e Contas encapsulava a lista em um objeto raiz (ex: `{ categories: [...] }`), a interface (Vue) injetava o objeto bruto na variável de estado reativo e o laço `v-for` acabava iterando sobre os valores das propriedades iteráveis do objeto, criando um problema estrutural no HTML (linhas renderizadas sem *id* de instâncias reais). Como consequência, as chamadas de API `.delete(cat.id)` e o `.filter` de listas falhavam.

**Solução:**
- Inserido *unwrapping* condicional seguro (`data?.categories || data || []` e `data?.bank_accounts || data || []`) no nível da action `loadCategories` e `loadBankAccounts` na página `FinancialSettings.vue`. Isso desempacota e normaliza os dados diretamente para instâncias reais de Array. Agora a visualização, paginação e eventos `@click` manipulando exclusões com `splice` ou `filter` funcionam nativamente sem falhas e atualizam a interface em tempo real.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — Correção no assinalamento reativo de carga de dados nas funções primárias.

## [1.4.4.23] - 2026-03-27T12:50:00-03:00

### Financeiro: UI Premium para Configurações e Caixa Diário

**Problema:** A aba de Configurações (regras de comissão, contas bancárias, despesas recorrentes e categorias) e a interface do Caixa Diário (`CashRegister.vue`) ainda utilizavam componentes isolados no estilo legado. Tabelas espremidas em cards, botões de ação e status com cores vazadas (`--color-woot-500` ausente) e menu de abas em "pills" flutuantes que não acompanhavam o design edge-to-edge das outras telas.

**Solução:**
- **Centralização Real de Modais (Teleport):** Envolto de todos os 4 modais de edição e criação de regras em `<Teleport to="body">`, garantindo que o overlay (`fixed inset-0`) respeite 100% da viewport e fique livre de eventuais blocos de `overflow: hidden` ou `transform` dos containers pais. Modais não cobrem mais apenas metade da página!
- **Sistema de Abas Horizontal (Underline):** Reescrita total das abas de navegação de Configurações (`.sets-tabs`) e eliminação total do contêiner obsoleto (`fin-card`), implementando padrão idêntico a `Agenda -> Configurações`.
- **Tabelas Canto-a-Canto:** Conversão da lista de histórico do *CashRegister* para `rep-table` com status pills padronizados. Nas Configurações, as seções agora mesclam harmoniosamente com o fundo da tela.
- **Header e Ações Consistentes:** Categoria e título das seções agora se alinham perfeitamente horizontalmente (`display: flex; align-items: flex-end`) com o botão de criação ("+ Regra", "+ Conta", etc). Correção de cores forçando hex `#3b82f6` para sanar o erro de variância no botão primário.
- **Empty States de Impacto:** Refatoração de estados vazios (`.cr-empty-state`, `.sets-empty`) usando ícones em blocos *soft-blue* arredondados e bordas `dashed`, imitando on-boarding minimalista.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/CashRegister.vue` — Layout refeito do histórico e header
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — Strip de cards extras e melhor formatação
- `app/javascript/dashboard/features/financial/financial.css` — Extenso re-work de classes `.cr-*` e `.sets-*`

## [1.4.4.22] - 2026-03-27T10:49:00-03:00

### Financeiro: UI Premium, Filtros Modernizados e Calendários Customizados (Pickers)

**Problema:** Alta fragmentação visual estourando nos módulos financeiros (DRE, A Pagar, A Receber, Fluxo). Filtros baseados em `<select>` e date inputs padrão do browser, que quebravam a imersão do Design System e impossibilitavam uma experiência premium "canto-a-canto" garantida. Problemas severos de alinhamento em gráficos em resoluções atípicas.

**Solução:**
- **Gráfico de Fluxo SVG "Canto a Canto":** Reescrita do gráfico interativo removendo bordas mortas, permitindo que a linha verde/vermelha flua de quina a quina absoluta do container-pai. Resolvido bug de corte superior em picos e overlapping com cabeçalhos.
- **Barra de Filtros Pagar/Receber:** Substituição completa de barras com selects para layouts icon-driven de busca e menus "Status" customizados via dropdown (ref-click-outside).
- **Picker 100% Customizado no DRE:**
  - Criação do **`MonthPicker.vue`** para seleção rápida e fluida de Meses do Ano através de botões estilizados.
  - Criação do **`DatePicker.vue`** base para navegação de dias, emulando calendário de maneira clean e em dark-mode.
  - Substituição definitiva das chamadas obsoletas `type="month"` e `type="date"`.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/components/MonthPicker.vue` — Novo componente criado do zero.
- `app/javascript/dashboard/features/financial/components/DatePicker.vue` — Novo componente criado do zero.
- `app/javascript/dashboard/features/financial/pages/DRE.vue` — Integração de picks e abas pill.
- `app/javascript/dashboard/features/financial/pages/Payables.vue` — Redesign do filtro com Status Menu.
- `app/javascript/dashboard/features/financial/pages/Receivables.vue` — Mirror dos filtros A Pagar.
- `app/javascript/dashboard/features/financial/financial.css` — +200 linhas de CSS system-compliant para comportar Dropdowns de Pickers e correção do Fluxo de Caixa.
- `app/javascript/dashboard/i18n/locale/*/financial.json` — Translation Keys para placeholders (`DATE_PLACEHOLDER`).

## [1.4.4.21] - 2026-03-27T10:45:00-03:00

### Financeiro — Relatórios: Refinamento Premium e Calendários Customizados

**Problema:** O módulo de "Relatórios" do financeiro estava exibindo abas centralizadas de forma indesejada devido a contêineres pai grid global, e utilizando as cores erradas para "Ativo" (ficando com texto invisível no modo claro). Além disso, os inputs de data ainda eram os nativos HTML `type="month"` e `type="date"`.

**Solução:**
- **Alinhamento:** `<div class="rep-tabs">` envolto com um contêiner `w-full flex justify-start` para garantir que o menu da aba fique sempre à esquerda, obedecendo as margens máximas de 1280px de forma fluida.
- **Cor Primária Azul:** Correção dos seletores de abas `.rep-tab--active` e `.rep-period-tab--active` que voltaram a usar estritamente o azul canônico BeClinic (`bg-woot-600` e `#3b82f6`) garantindo máximo contraste com fonte branca `#ffffff` ao invés de usar os antigos tons de slate.
- **Pickers Customizados:** Remoção total dos inputs nativos HTML de todas as quatro abas de relatório (Comissões, Despesas, Faturamento, Ticket). Em seu lugar foram estendidos e implementados de maneira unificada os novos componentes `<MonthPicker>` (seleção ágil mes/ano) e `<DatePicker>` (popovers customizados para datas específicas) reutilizando a sólida base construída no DRE.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/Reports.vue` — Inserção de refatoração para Month/DatePicker, e wrap do menu à esquerda.
- `app/javascript/dashboard/features/financial/financial.css` — `.rep-tab--active` agora usa cores hex code solidificadas para as brands blue.

## [1.4.4.20] - 2026-03-27T07:22:00-03:00

### Financeiro — Dashboard: Gráfico de Fluxo de Caixa reformulado para linha dupla

**Problema:** O `CashFlowChart.vue` exibia barras duplas (entradas verde / saídas vermelho), sem uma leitura comparativa imediata. O usuário precisava comparar alturas de barras adjacentes para entender o saldo do dia.

**Causa:** Design inicial baseado em `Bar` do Chart.js, sem área preeenchida, sem tooltip enriquecido e sem indicador de status do período.

**Solução — Redesign completo com gráfico de duas linhas:**
- Migrado de `Bar` para `Line` do Chart.js com `Filler` plugin
- **Linha verde** (Entradas) com área preenchida em gradiente verde sutil
- **Linha vermelha** (Saídas) com área preenchida em gradiente vermelho sutil
- Quando a linha verde está acima da vermelha = período positivo; quando a vermelha ultrapassa = saldo negativo do dia
- **Status Pill** contextual no cabeçalho do gráfico: "Saldo positivo no período" (verde) / "Saldo negativo no período" (vermelho)
- **Crosshair plugin** customizado: linha vertical tracejada ao fazer hover, facilitando leitura precisa dos pontos
- **Tooltip premium** com `mode: index`: exibe entradas (▲) e saídas (▼) de forma simultânea + saldo do dia após separador
- **Legenda redesenhada**: dot circular + traço de linha colorido para cada série + dica de leitura à direita ("Verde acima = mais entradas do que saídas")
- Grid Y minimalista com linhas horizontais ultra-suaves (`#f1f5f9` / `#1e293b`)
- Animação `easeInOutQuart` com 600ms de duração
- Canvas com altura de 280px (aumento de 20px vs. versão anterior)
- Suporte dual-theme completo (light/dark via `isDark` reactivo do `useChart`)
- Alerta de saldo negativo acumulado mantido e com cores corrigidas para padrão `STYLE.md`

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/components/CashFlowChart.vue` — redesign completo
- `app/javascript/dashboard/features/financial/financial.css` — classes `ccf-*` totalmente reescritas
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +3 chaves (`BALANCE_POSITIVE`, `BALANCE_NEGATIVE`, `LEGEND_HINT`)

## [1.4.4.19] - 2026-03-25T14:40:00-03:00

### Financeiro — Análise Avançada (Onda 4)

Implementação completa de três gráficos analíticos avançados para o Módulo Financeiro, provendo insights detalhados sobre funil de vendas, heatmap de ocupação da agenda e retenção de pacientes. Estes componentes seguem regras estritas de não usar bibliotecas de gráficos complexas quando viável por CSS.

**Gráficos implementados:**

- **Funil de Conversão (`ConversionFunnel.vue`)** — Gráfico com barras dinâmicas ilustrando a taxa de conversão entre etapas (Leads → Fechados). Inclui alerta destacando a etapa com maior perda (gargalo).
- **Heatmap de Ocupação da Agenda (`AgendaHeatmap.vue`)** — Matriz (Dias x Horários) exibindo densidade térmica baseada na taxa de ocupação. Construído sem libs (*completamente CSS Grid*). Alerta indicando horário de pico.
- **Novos Pacientes vs Recorrentes (`NewVsReturningPatients.vue`)** — Gráfico misto demonstrando pacientes novos (Barras Claras), retornados (Barras Escuras), o % de retenção (Linha Roxa) e meta de retenção (Tracejado). Sistema de alerta ativado caso retenção fique < 50% em 2 meses consecutivos (risco de *churn*).

**Backend & API:**
- Implementação de três Micro-Services otimizados (`agenda_analytics_service.rb`, `conversion_analytics_service.rb`, `patient_retention_service.rb`) para cálculo de percentuais e extração de insights.
- Criação dos três novos endpoints isolados no `FinancialReportsController`.
- Conformidade completa com regras do RuboCop para complexidade e tamanho de métodos.

**Design System & i18n:**
- Todas as definições visuais customizadas movidas para o manifesto unificado `financial.css`, mantendo a reusabilidade modular e suporte Light/Dark nativo.
- Adicionadas keys literais para os gráficos no manifesto `en/financial.json`.
- Atualização e documentação no `graficos_plano_de_acao.md`.

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/components/ConversionFunnel.vue`
- `app/javascript/dashboard/features/financial/components/AgendaHeatmap.vue`
- `app/javascript/dashboard/features/financial/components/NewVsReturningPatients.vue`
- `app/services/financial/agenda_analytics_service.rb`
- `app/services/financial/conversion_analytics_service.rb`
- `app/services/financial/patient_retention_service.rb`

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb`
- `config/routes.rb`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/features/financial/financial.css`
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `graficos_plano_de_acao.md`
- `app/javascript/dashboard/features/financial/components/RevenueGoalGauge.vue` (pequenos fixes incidentais)

## [1.4.4.18] - 2026-03-25T12:35:57-03:00

### Financeiro — Gráficos do Dashboard + Refinamentos Visuais

Implementação de 2 gráficos CSS-only no Dashboard Financeiro e refinamentos visuais nos botões de ação, modal de transação e summary cards.

**Gráficos implementados:**

- **`DailyCashFlowChart.vue`** — Gráfico de barras duplas verticais (verde = entradas, vermelho = saídas) mostrando o fluxo de caixa dos últimos 8 dias. CSS-only, sem dependência de Chart.js. Inclui legenda com dot colorido, labels de data (dd/mm), tooltip com valor formatado em BRL. Classes `dcf-*` com suporte dual-theme.

- **`MonthlySalesChart.vue`** — Gráfico de barras verticais azuis mostrando a evolução de vendas dos últimos 6 meses. Valores abreviados acima das barras (ex: R$ 12,5k), labels de mês/ano abaixo. Cor primária `rgb(var(--blue-9))`. Classes `msc-*` com suporte dual-theme.

- Ambos integrados como blocos arrastáveis no grid do Dashboard (`daily_cash_flow`, `monthly_sales`), com skeleton loading e empty state.

**Refinamentos visuais:**

- **Modal de Transação (`TransactionModal.vue`):** Botões de tipo (Entrada/Saída) refatorados — estado inativo agora é cinza neutro (`#f9fafb`), estado ativo aplica cor semântica (verde para entrada, vermelho para saída). Corrige o bug onde ambos os botões ficavam verdes.

- **Botões de ação (CashFlow, Receivables, Payables):** Cores suaves aplicadas — `.btn-new-entry-cf` verde pastel, `.btn-new-expense-cf` vermelho pastel, `.btn-new-entry-rec` verde pastel, `.btn-new-expense-pay` vermelho pastel. Hover states removidos/simplificados.

- **Summary cards:** `.financial-summary-card` redesenhado com fundo verde claro (#f1fdf0), `.financial-summary-card--income` azul (#e5effd), `.financial-summary-card--expense` vermelho (#fdf0f0).

- **Teleport no modal:** `TransactionModal.vue` envolto em `<Teleport to="body">` para resolver overlay que não cobria 100% da tela.

**CSS adicionado:** ~145 linhas no `financial.css` (classes `dcf-*` e `msc-*`).

**i18n:** +13 chaves novas no `FINANCIAL.DASHBOARD.*` em pt-BR.

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/components/DailyCashFlowChart.vue`
- `app/javascript/dashboard/features/financial/components/MonthlySalesChart.vue`

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue` — imports + 2 novos blocos
- `app/javascript/dashboard/features/financial/financial.css` — +145 linhas de CSS de gráficos + botões
- `app/javascript/dashboard/features/financial/components/TransactionModal.vue` — Teleport + fix de indentação
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue` — classes de botões
- `app/javascript/dashboard/features/financial/pages/Receivables.vue` — classes de botões
- `app/javascript/dashboard/features/financial/pages/Payables.vue` — classes de botões
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +13 chaves DASHBOARD

---

## [1.4.4.17] - 2026-03-24T14:35:15-03:00


### Financeiro Central — Auditoria Visual Completa + Correção de CSS Crítico

Auditoria 100% do módulo financeiro: identificação e correção da causa raiz de todos os problemas visuais (páginas sem estilo, layout espremido, espaçamento inconsistente) e correções de i18n/inline styles.

**Problema:** Todas as sub-páginas (CashFlow, Receivables, Payables, Reports, Settings) estavam visualmente "quebradas" — sem espaçamento, sem cards, sem estilos de tabela, conteúdo espremido num canto da tela. O Dashboard e DRE/CashRegister tinham strings hardcoded em português e inline styles proibidos pelo STYLE.md.

**Causa Raiz (descoberta nesta auditoria):**
1. **5 de 8 páginas NÃO importavam `financial.css`** — CashFlow, Receivables, Payables, Reports e FinancialSettings nunca carregavam o stylesheet, então renderizavam sem NENHUM estilo
2. **~50 classes CSS referenciadas nos templates nunca foram definidas** — classes como `financial-page__header`, `financial-grid`, `financial-summary-card`, `financial-table`, `financial-filters`, `financial-badge`, `financial-btn`, `fin-card`, etc. eram usadas mas não existiam no CSS

**Solução:**

- **CSS imports** — Adicionado `import '../financial.css'` em 5 páginas: CashFlow.vue, Receivables.vue, Payables.vue, Reports.vue, FinancialSettings.vue.

- **+600 linhas de CSS** — Definidas todas as classes ausentes no `financial.css`:
  - Layout de sub-páginas: `.financial-page__header/title/subtitle`
  - Grid responsivo: `.financial-grid` / `--2` / `--3` / `--4` (com breakpoints mobile)
  - KPI summary cards: `.financial-summary-card` / `--income` / `--expense` + label/value
  - Data tables: `.financial-table` com th/td, hover, col variants (`--number`, `--income`, `--expense`, `--positive`, `--negative`, `--description`)
  - Barra de filtros: `.financial-filters` + `__search` / `__select` / `__overdue` / `__btn`
  - Badges: `.financial-badge` + `--success` / `--warning` / `--danger` / `--neutral`
  - Paginação: `.financial-pagination` + `__info` / `__btn`
  - Botões genéricos: `.financial-btn` + `--primary` / `--ghost`
  - Gráfico de barras (CashFlow): `.financial-bar-chart`, `.financial-bar--income/expense`, `.financial-chart-legend`
  - Empty states: `.financial-empty-state` + `__icon` / `__text`
  - Skeletons: `--card` / `--chart` / `--table`
  - Settings: `.fin-page`, `.fin-card`, `.fin-loading`, `.fin-text-muted`, `.fin-text-secondary`
  - Tudo com suporte completo a Dark Mode (`body.dark`)

- **CSS import path fix (sessão anterior)** — Corrigido `../../financial.css` → `../financial.css` em DRE.vue e CashRegister.vue (resolvia erro de build Vite).

- **i18n (sessão anterior)** — 15+ strings PT hardcoded em FinancialDashboard.vue substituídas por `$t()`. Chaves DASHBOARD e CANCEL/CONFIRM adicionadas em en/pt_BR `financial.json`.

- **Inline styles (sessão anterior)** — Removidos todos os `style=""` de FinancialDashboard.vue, substituídos por classes CSS utilitárias.

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/Receivables.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/Payables.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/Reports.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — +import CSS
- `app/javascript/dashboard/features/financial/pages/DRE.vue` — fix import path
- `app/javascript/dashboard/features/financial/pages/CashRegister.vue` — fix import path + i18n keys
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue` — i18n + remove inline styles
- `app/javascript/dashboard/features/financial/financial.css` — +600 linhas de classes CSS
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +chaves DASHBOARD/CANCEL/CONFIRM
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem

---

## [1.4.4.16] - 2026-03-24T14:05:17-03:00

### Financeiro Central — Onda 4C: Faturamento por Convênio + Ticket Médio + Exportação CSV

Implementa dois novos relatórios analíticos e adiciona exportação CSV a todos os relatórios financeiros, completando a Onda 4 do módulo financeiro.

**Problema:** A página Reports.vue tinha apenas 2 abas (Comissões e Despesas). Faltavam análise de faturamento por convênio/origem de pagamento e análise de ticket médio por profissional/mês — funcionalidades críticas para gestão de clínicas com múltiplos convênios.

**Solução:**

- **`FinancialReportsController#insurance`** — Agrupa entradas recebidas por `metadata['insurance']` ou `financial_category.name` (fallback: "Particular"). Retorna ranking com label, count e amount por origem. Suporte a `?format=csv` para download direto.

- **`FinancialReportsController#average_ticket`** — Calcula ticket médio agrupado por profissional ou por mês. Inclui overall (total geral). Query com `AVG(amount)` + COUNT nativo no Postgres.

- **`FinancialReportsController#commissions`** — Adicionado suporte a `?format=csv` (download de planilha de comissões com cabeçalho, linhas e total).

- **Rotas** — `get :insurance` e `get :average_ticket` adicionadas ao namespace `financial/reports`.

- **`reports.js`** — Adicionados `insurance()`, `averageTicket()` e `downloadReportCSV()` (utilitário separado para não violar regra de classe ESLint).

- **`Reports.vue`** — Reescrito com 4 abas:
  1. **Comissões** — existente, com botão CSV
  2. **Despesas por Categoria** — existente, sem alteração de lógica
  3. **Faturamento por Convênio** — novo: ranking horizontal por origem + tabela com ticket médio por convênio + KPI cards + botão CSV
  4. **Ticket Médio** — novo: toggle "por profissional / por mês", bar chart com acento verde, tabela e KPIs de total+ticket geral

- **CSS** — +50 linhas: `.rep-export-btn`, `.rep-filter-actions`, `.rep-date-input--year`, `.rep-ins-*`, `.rep-tick-*`, `.fin-flex-center`, `.fin-gap-sm`.

- **i18n** — +35 chaves novas no `FINANCIAL.REPORTS.*` em EN e pt_BR.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — +2 actions, CSV builders, helpers SQL
- `config/routes.rb` — `get :insurance` e `get :average_ticket`
- `app/javascript/dashboard/features/financial/api/reports.js` — 2 new methods + downloadReportCSV
- `app/javascript/dashboard/features/financial/pages/Reports.vue` — reescrito com 4 abas
- `app/javascript/dashboard/features/financial/financial.css` — +50 linhas de CSS
- `app/javascript/dashboard/i18n/locale/en/financial.json` — +35 chaves
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem

---

## [1.4.4.15] - 2026-03-24 13:56:50-03:00

### Financeiro Central — Onda 4B: Configurações (Regras de Comissão + Despesas Recorrentes)

Implementação completa da página `FinancialSettings.vue` — substitui o placeholder de `/financeiro/configuracoes` por uma interface funcional de gerenciamento de regras de comissão e despesas recorrentes.

**Problema:** Até agora, o `CommissionCalculator` calculava comissões mas as regras tinham que ser criadas manualmente via console Rail/seed. Sem UI, impossível para a clínica configurar regras por profissional. Idem para despesas recorrentes.

**Solução:**

- **`CommissionRulesController`** — CRUD completo (index/create/update/destroy). Multi-tenant via `Current.account.commission_rules`. Serializa `professional_name` e `category_name` para uso direto no frontend. Protegido por `CommissionRulePolicy` (admin only para write).

- **`RecurringExpensesController`** — CRUD completo (index/show/create/update/destroy). Destroy é soft (`active: false`). Inclui `bank_account_name` e `category_name` na serialização.

- **Rotas** — `resources :commission_rules` e `resources :recurring_expenses` adicionadas ao `namespace :financial`.

- **`FinancialSettings.vue`** — 2 abas: "Regras de Comissão" e "Despesas Recorrentes". Cada aba tem:
  - Tabela com badges coloridos (tipo de comissão / frequência / status ativo)
  - Modal de criação/edição com formulário completo
  - Select de profissional (carrega agents existentes)
  - Select de categoria e conta bancária (carregados de APIs existentes)
  - Toggles de ativo e auto_confirm

- **API clients** — `commissionRules.js` e `recurringExpenses.js` (padrão `ApiClient`).

- **CSS** — +420 linhas no `financial.css` com prefixo `sets-*`. Inclui: tabs, tabela, modal animado, form grid 2-col, badges, botões de ação, empty state. Suporte dark mode completo. Zero inline styles.

- **i18n** — +67 chaves `FINANCIAL.SETTINGS.*` em EN e pt_BR.

**Arquivos Criados:**
- `app/controllers/api/v1/accounts/commission_rules_controller.rb`
- `app/controllers/api/v1/accounts/recurring_expenses_controller.rb`
- `app/javascript/dashboard/features/financial/api/commissionRules.js`
- `app/javascript/dashboard/features/financial/api/recurringExpenses.js`

**Arquivos Modificados:**
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue` — substituiu placeholder
- `config/routes.rb` — 2 novos resources no namespace financial
- `app/javascript/dashboard/features/financial/financial.css` — +420 linhas `sets-*`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — `FINANCIAL.SETTINGS.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

---

## [1.4.4.14] - 2026-03-24 13:33:00-03:00


### Financeiro Central — Onda 4A: Comissões por Profissional

Implementação completa do **Relatório de Comissões** com cálculo automático por profissional, período e tipo de regra, substituindo o placeholder da página Relatórios por uma interface funcional com duas abas.

**Problema:** A página `/financeiro/relatorios` era um placeholder sem dados reais. Não existia nem o cálculo de comissões no backend nem a interface de seleção de profissional + período. Impossível gerar relatório de repasse para profissionais.

**Solução:**

- **`Financial::CommissionCalculator` service** — Recebe account, professional e period. Para cada `AccountTransaction` do profissional no período (recebidas), busca a `CommissionRule` mais específica via `CommissionRule.most_specific_for` (prioridade: procedimento > categoria > geral). Aplica a fórmula correta conforme o tipo:
  - `percentage_production` → `original_amount * rule.value / 100`
  - `percentage_received` → `amount * rule.value / 100`
  - `fixed_value` → `rule.value` por transação
  - Retorna professional, period, total_commission, transaction_count, transactions[]

- **`commissions` action no `FinancialReportsController`** — `GET /api/v1/accounts/:id/financial/reports/commissions`. Params: `professional_id` (obrigatório), `period` (month/quarter/year/custom), `date`, `start_date`, `end_date`. Busca o profissional no escopo da account (segurança multi-tenant). Delega ao `CommissionCalculator`.

- **`resolve_commission_period` helper** — Suporta os mesmos 4 modos de período do DRE (month/quarter/year/custom).

- **`Reports.vue` completo** — Substitui o placeholder com duas abas:
  - **Aba Comissões:** Select de profissional (carrega `/agents`), seletor de período (mês/trimestre/ano/personalizado), input de data/range, botão Calcular. Exibe 3 KPI cards (profissional, Nº de transações, total de comissão roxo) + tabela detalhada por transação (descrição, categoria, data recebimento, valor, badge de tipo de regra, comissão calculada) + linha de total.
  - **Aba Despesas por Categoria:** Reaproveita o endpoint DRE existente. Gráfico de barras CSS-only com nome, valor e percentual por categoria + tabela com categoria, tipo (fixo/variável), valor e % sobre total.

- **CSS** — ~340 novas linhas com prefixos `rep-*` (shell da página), `comm-*` (comissões) e `exp-cat-*` (despesas por categoria). Zero inline styles, zero Tailwind ad-hoc.

**Decisões técnicas:**
- `CommissionCalculator` lê `transaction.metadata['procedure_name']` para busca por procedimento específico — forward-compatible com quando o campo for populado pela integração com procedimentos
- A aba de Despesas por Categoria reutiliza o endpoint `/dre` (já testado) em vez de criar um novo endpoint redundante — mantém o princípio de menor código
- Para o input de Ano no seletor de período, usa `input[type=number]` em vez de `input[type=month]` (compatibilidade com todos os browsers)

**Arquivos Criados:**
- `app/services/financial/commission_calculator.rb`
- `app/javascript/dashboard/features/financial/pages/Reports.vue` (substituiu placeholder)

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — action `commissions` + helper `resolve_commission_period`
- `config/routes.rb` — `get :commissions` na collection de reports
- `app/javascript/dashboard/features/financial/api/reports.js` — método `commissions(params)`
- `app/javascript/dashboard/features/financial/financial.css` — +340 linhas `rep-*`, `comm-*`, `exp-cat-*`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chaves `FINANCIAL.REPORTS.*` e `FINANCIAL.COMMISSIONS.*`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

---

## [1.4.4.13] - 2026-03-24 13:15:00-03:00

### Financeiro Central — Onda 3A: DRE (Demonstração do Resultado do Exercício)

Implementação completa do DRE por **regime de competência** (`competence_date`), com comparativo automático de período anterior e tabela hierárquica expansível.

**Problema:** A página DRE era um placeholder. Não existia endpoint de cálculo de resultado econômico, apenas fluxo de caixa (regime de caixa). Impossível gerar demonstrativo contábil para a clínica.

**Solução:**

- **Backend** — 4 métodos novos em `FinancialReportsController`:
  - `dre` — action pública: resolve período, calcula DRE atual e anterior, retorna JSON estruturado
  - `resolve_dre_period` — suporta 4 modos: `month`, `quarter`, `year`, `custom`
  - `prior_period` — calcula período anterior com duração idêntica (shift temporal simples)
  - `build_dre` — agrega `account_transactions` por `competence_date` + LEFT JOIN com `financial_categories`; calcula as 9 linhas: receita bruta → deduções → receita líquida → custos variáveis → margem bruta → despesas fixas → EBITDA → outras despesas → lucro líquido
  - `dre_rows` — GROUP BY categoria com `SUM(amount)`, distinguindo `cost_type: fixo / variavel`

- **DRE.vue** — Página funcional substituindo placeholder:
  - Seletor de 4 períodos (mês/trimestre/ano/personalizado) com `input[type=month]` e range de datas
  - Tabela com 9 seções econômicas: linhas de resultado destacadas visualmente
  - Subcategorias expansíveis via chevron (receita bruta, custos var., desp. fixas, outras)
  - Coluna de variação % vs período anterior com badge colorido (↑ verde / ↓ vermelho)
  - Botão de exportação desabilitado (placeholder para onda futura)
  - Loading state com spinner + empty state

- **CSS** — ~350 novas classes DRE em `financial.css`: `.dre-table`, `.dre-row--result`, `.dre-row--net-profit`, `.dre-badge--up/down`, `.dre-period-tabs`, etc.

**Decisões técnicas:**
- Usa `competence_date` (não `received_at`/`paid_at`) — regime de competência correto para DRE
- LEFT JOIN com `financial_categories` para incluir transações sem categoria como "Sem categoria"
- Categorias `income` com `category_type = 'deducao'` são subtraídas da receita bruta
- Despesas sem `cost_type` caem em "Outras Despesas" (taxas bancárias, cartão, etc.)

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/pages/DRE.vue` (substituiu placeholder)

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb` — action `dre` + 4 helpers privados
- `config/routes.rb` — `get :dre` na collection de reports
- `app/javascript/dashboard/features/financial/api/reports.js` — método `dre(params)`
- `app/javascript/dashboard/features/financial/financial.css` — +350 linhas DRE + `.financial-title/subtitle/loading`
- `app/javascript/dashboard/i18n/locale/en/financial.json` — chaves `FINANCIAL.DRE.*` (14 chaves)
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json` — idem em português

---

## [1.4.4.8] - 2026-03-24 12:36:00-03:00

### Financeiro Central — Onda 1A: Migrations + Models (Fundação)

Criação da fundação de dados do **Módulo Financeiro Central** do BeClinic. Este bloco estabelece as 5 tabelas que sustentam todos os KPIs, DRE, fluxo de caixa e relatórios futuros.

**Problema:** O sistema não tinha uma estrutura centralizada para financeiro da clínica — apenas o financeiro do paciente (`transactions`). Impossível gerar DRE, fluxo de caixa geral, ou registrar despesas operacionais.

**Solução:** Criação de 5 tabelas independentes que compõem o núcleo do módulo central:

- **`financial_categories`**: Árvore de categorias de receita/despesa (pai→filhos), com `cost_type` para distinguir fixo/variável no DRE
- **`bank_accounts`**: Contas bancárias da clínica com saldo inicial; saldo atual calculado dinamicamente pelas transações vinculadas
- **`account_transactions`**: Tabela "mãe" do financeiro central. Aceita entradas e saídas com ou sem paciente vinculado. 5 campos de data distintos (competência, vencimento, recebimento, pagamento, criação) para suportar tanto regime de caixa quanto regime de competência. Soft delete para rastreabilidade contábil. Índice `UNIQUE` em `source_transaction_id` garante idempotência absoluta na integração com o financeiro do paciente
- **`commission_rules`**: Regras de comissão por profissional com 3 tipos: `percentage_production`, `percentage_received`, `fixed_value`. Suporta prioridade: procedimento > categoria > geral, com vigência por data
- **`recurring_expenses`**: Template de despesas recorrentes (aluguel, salários) para geração automática via job. Suporta `competence_rule: same_month | previous_month` para correta alocação contábil

**Decisões técnicas:**
- Índice composto `[:account_id, :entry_type, :status]` recebeu nome explícito curto (`idx_acct_txns_account_type_status`) para respeitar limite de 63 chars do PostgreSQL
- Validado via `rails runner`: todos os 5 models carregam sem erro

**Arquivos Criados:**
- `db/migrate/20260324120001_create_financial_categories.rb`
- `db/migrate/20260324120002_create_bank_accounts.rb`
- `db/migrate/20260324120003_create_account_transactions.rb`
- `db/migrate/20260324120004_create_commission_rules.rb`
- `db/migrate/20260324120005_create_recurring_expenses.rb`
- `app/models/financial_category.rb`
- `app/models/bank_account.rb`
- `app/models/account_transaction.rb`
- `app/models/commission_rule.rb`
- `app/models/recurring_expense.rb`

---

## [1.4.4.10] - 2026-03-24 12:55:00-03:00

### Financeiro Central — Onda 1B: Frontend (Rotas + Sidebar + Dashboard)

Implementação completa da camada frontend da **Onda 1 do Módulo Financeiro Central**. O módulo agora está acessível na sidebar com dashboard funcional consumindo API real.

**Problema:** Sem frontend, o backend da Onda 1A era invisível para o usuário. A sidebar não tinha entrada "Financeiro" e as rotas Vue não existiam.

**Solução:** Estrutura modular completa em `features/financial/`:

- **8 rotas lazy-loaded** em `features/financial/routes.js` — dashboard, fluxo de caixa, a receber, a pagar, DRE, relatórios, caixa, configurações
- **CSS modular** `financial.css` — 240 linhas, zero inline/scoped, dual-theme light/dark
- **5 API clients** com `/* global axios */` — dashboard, transactions, categories, bankAccounts, reports
- **2 composables** — `useFormatCurrency` (Intl.NumberFormat BRL) + `useFinancialFilters` (period: today/week/month/custom)
- **`FinancialDashboard.vue`** — Dashboard principal com 4 KPIs (receita, saídas, novas entradas, lucro), blocos A Receber/A Pagar/Inadimplência/Contas, skeleton loading, seletor de período
- **7 páginas placeholder** para Onda 2/3 com visual "em breve"
- **i18n** `financial.json` adicionado em `en` e `pt_BR` e registrado nos respectivos `index.js`
- **Sidebar** — entrada "Financeiro" com ícone `i-lucide-wallet` e 8 subitens, posicionada entre Patients e Contacts

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/routes.js`
- `app/javascript/dashboard/features/financial/financial.css`
- `app/javascript/dashboard/features/financial/api/dashboard.js`
- `app/javascript/dashboard/features/financial/api/accountTransactions.js`
- `app/javascript/dashboard/features/financial/api/categories.js`
- `app/javascript/dashboard/features/financial/api/bankAccounts.js`
- `app/javascript/dashboard/features/financial/api/reports.js`
- `app/javascript/dashboard/features/financial/composables/useFormatCurrency.js`
- `app/javascript/dashboard/features/financial/composables/useFinancialFilters.js`
- `app/javascript/dashboard/features/financial/pages/FinancialDashboard.vue`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue`
- `app/javascript/dashboard/features/financial/pages/Receivables.vue`
- `app/javascript/dashboard/features/financial/pages/Payables.vue`
- `app/javascript/dashboard/features/financial/pages/DRE.vue`
- `app/javascript/dashboard/features/financial/pages/Reports.vue`
- `app/javascript/dashboard/features/financial/pages/CashRegister.vue`
- `app/javascript/dashboard/features/financial/pages/FinancialSettings.vue`
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json`

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/i18n/locale/en/index.js`
- `app/javascript/dashboard/i18n/locale/pt_BR/index.js`

---

## [1.4.4.12] - 2026-03-24 13:05:00-03:00

### Financeiro Central — Onda 2B: A Receber + A Pagar

Implementação das páginas **Receivables** e **Payables** com listagem real, filtros e detecção automática de inadimplência.

**Problema:** As páginas eram placeholders sem dados reais. O backend não suportava filtros por vencimento ou busca textual.

**Solução:**

- **Receivables.vue** — A Receber (entry_type: entrada): KPIs de total/quantidade, filtros por status/vencido/busca, tabela com badge de status e auto-detecção de inadimplência (due_date < hoje + não recebido = badge vermelho), paginação
- **Payables.vue** — A Pagar (entry_type: saida): mesma estrutura
- **Backend expandido** com filtros `?due_start`, `?due_end`, `?overdue=true`, `?q=texto` e `meta.total_amount` no retorno

**Arquivos Criados:**
- `app/javascript/dashboard/features/financial/pages/Receivables.vue`
- `app/javascript/dashboard/features/financial/pages/Payables.vue`

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`
- `app/javascript/dashboard/features/financial/api/accountTransactions.js`
- `app/javascript/dashboard/i18n/locale/en/financial.json`
- `app/javascript/dashboard/i18n/locale/pt_BR/financial.json`

---

## [1.4.4.11] - 2026-03-24 13:00:00-03:00

### Financeiro Central — Onda 2A: Fluxo de Caixa + Bugfix Sidebar i18n

**Bug Corrigido — Sidebar mostrando labels crus (SIDEBAR.INBOX, SIDEBAR.CONVERSATIONS etc.):**
- Root cause: `financial.json` tinha chave top-level `SIDEBAR` que sobrescrevia o objeto inteiro do `settings.json` via spread (`...financial`)
- Fix: removido bloco `SIDEBAR` de `financial.json`; chaves `FINANCIAL_*` adicionadas dentro do `SIDEBAR` do `settings.json` (EN + pt_BR)

**Fluxo de Caixa:**
- `FinancialReportsController` com `GET /financial/reports/cash_flow` (breakdown diário + saldo inicial) e `GET /financial/reports/monthly_summary`
- `CashFlow.vue`: seletor de período, 3 KPIs, gráfico de barras CSS-only, tabela diária com skeleton loading

**Arquivos Criados:**
- `app/controllers/api/v1/accounts/financial_reports_controller.rb`
- `app/javascript/dashboard/features/financial/pages/CashFlow.vue` (substituiu placeholder)

**Arquivos Modificados:**
- `config/routes.rb`
- `app/javascript/dashboard/features/financial/api/reports.js`
- `app/javascript/dashboard/features/financial/composables/useFinancialFilters.js`
- `app/javascript/dashboard/i18n/locale/en/settings.json` e `pt_BR/settings.json`
- `app/javascript/dashboard/i18n/locale/en/financial.json` e `pt_BR/financial.json`

## [1.4.4.9] - 2026-03-24 12:45:00-03:00

### Financeiro Central — Onda 1A: Controllers + Policies + Rotas

Implementação da camada de API do **Módulo Financeiro Central**. Os 4 controllers expõem os endpoints financeiros protegidos por Pundit e acessíveis via namespace `/financial`.

**Problema:** Os models da Onda 1A não tinham controllers nem políticas de acesso. Impossível consumir os dados pelo frontend.

**Solução:**

- **`FinancialDashboardController`** — `GET /financial/dashboard` retorna 4 KPIs regime caixa (income, expense, new_income, net_profit), blocos receivables/payables/delinquency, lista de contas bancárias com saldo atual, mini cash flow e monthly sales
- **`AccountTransactionsController`** — CRUD completo com filtros por data/tipo/status, paginação, soft delete (preserva rastreabilidade contábil)
- **`FinancialCategoriesController`** — CRUD com proteção de categorias padrão contra deleção
- **`BankAccountsController`** — CRUD, destroy apenas desativa (soft delete)
- **6 Policies Pundit** — `FinancialDashboardPolicy`, `AccountTransactionPolicy`, `FinancialCategoryPolicy`, `BankAccountPolicy`, `CommissionRulePolicy`, `RecurringExpensePolicy`; escrita restrita a `administrator`
- **`Account` model** — `has_many` das 5 novas tabelas financeiras

**Arquivos Criados:**
- `app/controllers/api/v1/accounts/financial_dashboard_controller.rb`
- `app/controllers/api/v1/accounts/account_transactions_controller.rb`
- `app/controllers/api/v1/accounts/financial_categories_controller.rb`
- `app/controllers/api/v1/accounts/bank_accounts_controller.rb`
- `app/policies/financial_dashboard_policy.rb`
- `app/policies/account_transaction_policy.rb`
- `app/policies/financial_category_policy.rb`
- `app/policies/bank_account_policy.rb`
- `app/policies/commission_rule_policy.rb`
- `app/policies/recurring_expense_policy.rb`

**Arquivos Modificados:**
- `config/routes.rb` — namespace `:financial` com dashboard, transactions, categories, bank_accounts
- `app/models/account.rb` — `has_many` das 5 tabelas financeiras

---


## [1.4.4.7] - 2026-03-24 10:28:00-03:00

### Chat: Modal de Lista de Espera — Botão de Remoção

Adicionado botão **"Remover da lista"** no rodapé do modal `WaitingListModal` (acessível pelo botão "Lista de espera" no painel de contato da conversa).

**Comportamento:**
- O botão **só aparece quando o contato já está na lista de espera** (`isEditing = true`)
- Estilo vermelho/danger. É um botão icon-only (usando apenas o ícone de lixeira `i-ph-trash`), sem modal de confirmação (ação direta)
- Layout do footer ajustado: botão de remoção à esquerda, "Cancelar" e ação principal à direita
- Estado de loading (`isRemoving`) durante a requisição, com spinner no lugar do ícone
- Após remoção bem-sucedida: alerta com mensagem personalizada + fecha o modal automaticamente

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/conversation/contact/WaitingListModal.vue` — função `handleRemove`, estado `isRemoving`, botão danger, CSS `.wl-btn--danger` e `.wl-footer-right`
- `app/javascript/dashboard/i18n/locale/en/contact.json` — chaves `REMOVE`, `REMOVING`, `REMOVE_MESSAGE`

---

## [1.4.4.6] - 2026-03-24 10:19:00-03:00

### Agenda: Lista de Espera — Remoção Automática ao Agendar

Quando um paciente da lista de espera é agendado através do popup de células verdes no calendário, sua entrada é **automaticamente removida** da lista de espera após o agendamento ser salvo com sucesso.

**Fluxo:**
1. Usuário clica na célula verde (slot disponível compatível com a preferência da lista de espera)
2. Popup mostra os pacientes na lista de espera para aquele horário
3. Usuário seleciona um paciente (ex: "Gabriel"), o modal de novo evento abre pré-preenchido
4. Usuário finaliza o agendamento e clica em "Agendar"
5. Após salvar com sucesso, o sistema **chama automaticamente `waitingListStore.remove(wlScheduleEntry.id)`**, removendo a entrada do banco e do store reativo

A remoção só ocorre em novos agendamentos (não em edições de eventos existentes) e apenas quando o contexto da lista de espera está presente (`wlScheduleEntry`).

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue` — chamada `waitingListStore.remove` após `agendaEvents/create`

---

## [1.4.4.5] - 2026-03-22 18:30:00-03:00

### Agenda: Correção de 500/404 em Endpoints + i18n

Auditoria e correção de erros de console que impediam o funcionamento correto da agenda.

#### Bug Fixes — API (500 / 404)

- **500 em `/api/v1/accounts/:id/agenda_setting`:** `Pundit::NotDefinedError` — faltava `AgendaSettingPolicy`
- **500 em `/api/v1/accounts/:id/agenda_custom_attributes`:** `Pundit::NotDefinedError` — faltava `AgendaCustomAttributePolicy`
- **404 em `/api/v1/accounts/:id/agenda_online_config`:** Dois problemas combinados:
  1. Faltava `AgendaOnlineConfigPolicy` (Pundit)
  2. `resource :agenda_online_config` no routes.rb buscava `AgendaOnlineConfigsController` (plural), mas o controller era `AgendaOnlineConfigController` (singular). Corrigido com `controller: 'agenda_online_config'`

Todas as 3 policies seguem o padrão existente: leitura para `account_user`, escrita para `administrator`.

#### Bug Fixes — i18n (traduções faltando em pt_BR)

- **`CONVERSATION_WORKFLOW`**: bloco completo (INDEX.HEADER, REQUIRED_ATTRIBUTES com MODAL, PAYWALL, ENTERPRISE_PAYWALL) adicionado em `pt_BR/settings.json`
- **`PAGINATION_FOOTER.SHOW` e `.PER_PAGE`**: chaves adicionadas em `pt_BR/contact.json`

**Arquivos Criados:**
- `app/policies/agenda_setting_policy.rb`
- `app/policies/agenda_custom_attribute_policy.rb`
- `app/policies/agenda_online_config_policy.rb`

**Arquivos Modificados:**
- `config/routes.rb` — `controller: 'agenda_online_config'` adicionado
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json` — bloco CONVERSATION_WORKFLOW
- `app/javascript/dashboard/i18n/locale/pt_BR/contact.json` — SHOW, PER_PAGE

---

## [1.4.4.4] - 2026-03-22 16:43:00-03:00

### Agenda: Barra de Resumo (mini-dashboard contextual)

Adicionado botão **"Resumo"** no cabeçalho da agenda (substituindo "Filtrar Agentes") que abre/fecha uma barra de métricas contextual abaixo do header. A barra exibe 6 KPIs para o período atualmente visível (dia/semana/mês):

- **Agendados** — total de eventos no período
- **Confirmados** — eventos com status `confirmed`
- **Pendentes** — eventos com status `scheduled` (aguardando confirmação)
- **Atendidos** — soma de `completed + in_progress + arrived`
- **Ocupação** — taxa percentual de slots preenchidos vs. capacidade total
- **No-show** — taxa percentual de faltas

O range de datas (since/until) é calculado automaticamente a partir da view ativa:

- **Mês:** do primeiro ao último dia do mês exibido
- **Semana:** do domingo ao sábado da semana exibida
- **Dia:** a data exata do dia selecionado

Ao navegar para outra semana/mês/dia, as métricas são re-calculadas automaticamente via watcher reativo. O botão "Resumo" muda de aparência (azul ativo) quando a barra está visível.

**Arquitetura modular:** novo módulo em pasta própria, sem poluir o `AgendaDashboard.vue`.

**Arquivos Criados/Modificados:**

- `app/javascript/dashboard/features/agenda-summary/AgendaSummaryBar.vue` *(novo)*
- `app/javascript/dashboard/features/agenda-summary/agenda-summary.css` *(novo)*
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.3] - 2026-03-22 16:39:00-03:00

### Agenda: Botões de ação na célula verde — tamanho e posição

Aumentado o tamanho dos botões de ação inline nas células verdes (lista de espera) de 22px para 28px, com ícone de 11px → 15px. Posição ajustada de centralizado para **canto inferior direito** (`bottom: 4px; right: 4px`).

**Arquivos Modificados:**

- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.2] - 2026-03-22 16:35:00-03:00

### Agenda: Lista de Espera — cadastro automático de novo paciente

Quando o contato selecionado da lista de espera **não possui cadastro como paciente**, o sistema agora:

1. Limpa o campo "Paciente" no modal de novo evento (não pre-seleciona o contato incorretamente)
2. Abre automaticamente o painel lateral **"Novo Paciente"** com nome e telefone pré-preenchidos do contato
3. O `contact_id` é passado no `quickPatient` para vincular o novo paciente ao contato existente após o cadastro

Quando o contato **possui** paciente cadastrado, o comportamento anterior é mantido: paciente auto-selecionado via `PatientsAPI.byContact`.

**Arquivos Modificados:**

- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.4.4.1] - 2026-03-22 15:14:00-03:00

### Lista de Espera: Card minimalista, Seção na Agenda e Store reativo

Refatorado o card de contato no modal de lista de espera para design ultra-minimalista (uma linha com inicial + nome + telefone + badge). Implementado o módulo `features/waiting-list/` com arquitetura modular separada:

- `store.js` — store reativo com persistência em localStorage
- `WaitingListSidebarSection.vue` — seção colapsável na sidebar da Agenda
- `WaitingListSidebarItem.vue` — item individual com tooltip de detalhes
- `WaitingListSlotBadge.vue` — badge verde-pastel para slots livres compatíveis

O modal agora salva diretamente no store ao submeter, fazendo a entrada aparecer instantaneamente na sidebar da Agenda.

**Arquivos Modificados:**

- `app/javascript/dashboard/routes/dashboard/conversation/contact/WaitingListModal.vue`
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`
- `app/javascript/dashboard/features/waiting-list/store.js` (novo)
- `app/javascript/dashboard/features/waiting-list/WaitingListSidebarSection.vue` (novo)
- `app/javascript/dashboard/features/waiting-list/WaitingListSidebarItem.vue` (novo)
- `app/javascript/dashboard/features/waiting-list/WaitingListSlotBadge.vue` (novo)
- `app/javascript/dashboard/i18n/locale/en/contact.json`
- `docs/STYLE.md`

---

## [1.4.4.0] - 2026-03-22 15:02:00-03:00

### Chat: Botão e Modal de Lista de Espera no Painel de Contato

Adicionado botão **"Lista de Espera"** (ícone `i-ph-clock-countdown`) na barra de ações do painel lateral de contato, ao lado dos botões existentes (Nova Mensagem, Prontuário, Editar, Mesclar, Excluir).

**Fluxo:**
- Botão com tooltip "Lista de espera" segue o mesmo padrão visual (`NextButton` com `slate faded sm`)
- Ao clicar, abre o modal `WaitingListModal.vue` (componente separado, seguindo arquitetura de modularização)
- Modal exibe o contato da conversa já vinculado automaticamente (read-only, com badge verde "Contato vinculado automaticamente")
- Campos do modal:
  - **Período de preferência** (obrigatório): 3 botões seletores — Manhã 🌅 (08–12h), Tarde ☀️ (12–18h), Noite 🌙 (18–21h)
  - **Horário específico** (opcional): input `type="time"` com ícone de relógio
  - **Observações** (opcional): textarea livre
- Validação frontend com `useAlert` se período não selecionado
- Feedback de sucesso com nome do contato após submeter
- Dual-theme completo: todo CSS usa variáveis `rgb(var(--slate-N))` — funciona em dark e light mode
- Animações de entrada/saída (fade no backdrop, slide+scale no modal)

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/conversation/contact/WaitingListModal.vue` *(criado)*
- `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue` — importa e renderiza `WaitingListModal`, adiciona botão e state `showWaitingListModal`
- `app/javascript/dashboard/i18n/locale/en/contact.json` — chaves `WAITING_LIST.*` adicionadas

---

## [1.4.3.9] - 2026-03-21 19:36:00-03:00

### API Docs: Página de Documentação Interativa da API Klivy

Criação do site de documentação interativo da API da plataforma Klivy, servido estaticamente em `/api-docs.html`.

**Funcionalidades:**

- **Config Bar** no topo com campos Domínio, Account ID e API Access Token, persistidos no `localStorage`
- **Injeção dinâmica de credenciais** em todos os exemplos cURL da página
- **Barra de progresso** de preenchimento das credenciais (2px no topo)
- **Sidebar navegável** com contagem de endpoints por módulo e estado ativo por scroll
- **63 endpoints documentados** em 12 módulos: Autenticação, Agenda (Eventos, Serviços, Notificações, Config Online, Relatórios), Pacientes (CRUD, Evoluções, Planos, Agendamentos, Financeiro, Outros)
- **Grid de estatísticas** no hero (63 endpoints, 12 módulos, 100% com cURL, v1)
- **Tabs** por endpoint: Body/Params, cURL, Resposta
- **Botão Copiar** nos blocos de código com feedback visual
- **Botão Back-to-Top** flutuante
- **Atalho ⌘K** para focar no campo Domínio
- **Footer** com padrão de URL da API
- **Animações** de entrada nos endpoint cards

**Arquivos Modificados:**
- `public/api-docs.html` *(criado)*

---

## [1.4.3.8] - 2026-03-21 18:42:00-03:00


### Prontuário: Light Mode Modais + STYLE.md Guia Dual-Theme

#### Correções de Light Mode — Modais do Prontuário

Continuação da auditoria de tema claro no prontuário. Foco nos modais com fundo preto no light mode.

**Estratégia aplicada:**

- **`body:not(.dark)` overrides** no `record.css`: sobrescrevem classes Tailwind dark hardcoded (`bg-slate-900`, `bg-slate-800`, `border-slate-700`) sem editar o monolítico `Record.vue`.
- **Classes `record-modal-*`**: substituem `style=""` inline proibidos pelo ESLint. Usam variáveis `rgb(var(--slate-N))` para adaptar ao tema automaticamente.

**Modais/elementos corrigidos:**

- Criar/Renomear/Excluir Pasta: `bg-slate-900` → `.record-modal-box`; inputs e labels com `.record-modal-input`, `.record-modal-label`, `.record-modal-muted`
- Lock/Unlock e Excluir Arquivo: `body:not(.dark) .bg-slate-900` override no CSS
- Input modal Lock: `body:not(.dark) input.bg-slate-800` override
- Botão empty state de documentos: `style="color: #60a5fa"` → `class="text-blue-400"`

#### STYLE.md — Guia Completo de Dual-Theme

Adicionadas ao `docs/STYLE.md`:

- **Arquitetura CSS por Módulo**: CSS separado por feature é obrigatório
- **Guia de 5 Passos**: mecanismo `body.dark`, prefixos, estratégia `body:not(.dark)`, proibição `style=""`, grep de problemas
- **Sistema `record-modal-*`**: tabela de classes e exemplos before/after
- **Checklist de Auditoria**: 7 categorias para validar light mode
- **Lições Aprendidas**: tabela dos problemas reais e soluções

**Arquivos Modificados:**

- `app/javascript/dashboard/routes/dashboard/patients/record.css` — overrides `body:not(.dark)` + classes `record-modal-*`
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — `style=""` removidos; Tailwind dark → `record-modal-*`
- `docs/STYLE.md` — guia completo de implementação dual-theme adicionado

---

## [1.4.3.7] - 2026-03-21 21:45:00-03:00

### Pacientes: Light Mode Completo — Prontuário e Todas as Abas

Aplicação do sistema dual-theme (light/dark) para **toda** a área de pacientes: lista principal, arquivados, e as 13 abas do prontuário.

**Estratégia:** criado `record.css` com overrides de variáveis CSS `rgb(var(--slate-N))` que substituem os valores dark hardcoded do `<style scoped>` do `Record.vue` (17k linhas), sem precisar editar o arquivo monolítico. O CSS importado no `<script setup>` cria regras globais não-scoped com `!important` para garantir precedência.

**Abas cobertas:**
- Geral (Visão Geral) — cards, KPIs, empty states
- Cadastro (RegistrationTab) — seções colapsáveis, inputs, toggles, dropdown de contatos
- Anamnese — cards, assinatura
- Evolução — textarea, cards de notas, alertas
- Plano de Tratamento — cards, itens de tratamento
- Procedimentos — cards, tabela de sessões
- Exames e Imagens — cards de arquivos, pastas, breadcrumb, upload zone
- Documentos — cards, ações
- Consentimentos — KPIs, cards, botões de ação semânticos
- Financeiro — KPIs, tabelas de transações e orçamentos
- Agenda e Histórico — cards de consultas
- Timeline — cards de eventos, badges coloridos, ícones semânticos (16 variantes)
- Auditoria — filtros, tabela, expandido de diff

**Cores corretas para ambos os temas:**

| Status | Background | Texto |
| --- | --- | --- |
| Novo | `rgba(59,130,246,0.12)` | `#2563eb` |
| Ativo | `rgba(22,163,74,0.12)` | `#16a34a` |
| Faltoso | `rgba(217,119,6,0.10)` | `#d97706` |
| Alta | `rgba(124,58,237,0.10)` | `#7c3aed` |
| Inativo | `rgba(100,116,139,0.10)` | `#475569` |
| Arquivado | Banner âmbar com variáveis CSS |

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/record.css` — **NOVO** arquivo CSS dual-theme do prontuário
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — importa `record.css`
- `app/javascript/dashboard/routes/dashboard/patients/tabs/RegistrationTab.vue` — box-shadow dark removido

---

## [1.4.3.6] - 2026-03-21 21:30:00-03:00


### Pacientes: Correção de Bug 422 + Light Mode + Modularização CSS

#### Bug Fix: Criação de Paciente com 422 (Unprocessable Content)

- **Causa raiz**: O controlador criava um Contato fantasma no banco antes de validar o Paciente. Quando o nome tinha apenas 1 caractere (ex: `"s"`), o model `Patient` rejeitava com `length: { minimum: 2 }` — mas o contato já havia sido persistido, criando registros órfãos.
- **Correção backend** (`patients_controller.rb`): A autorização Pundit e a validação do model agora ocorrem **antes** da criação do contato. Se o paciente for inválido, retorna 422 imediatamente sem efeitos colaterais no banco.
- **Correção frontend** (`NewPatientModal.vue`): Validação do nome completo com mínimo de 2 caracteres antes de fazer a requisição — alinhada à validação do backend.

#### Light Mode: Página de Pacientes (Index)

- Todos os estilos da área de pacientes migrados de cores hardcoded dark (`#0a0c10`, `rgba(0,0,0,0.2)`, `rgba(255,255,255,0.X)`) para variáveis CSS `rgb(var(--slate-N))`.
- Status badges corrigidos para cores legíveis em ambos os temas (ex: `#4ade80` → `#16a34a` para "Ativo").
- Controles de busca, filtros, cards de grid e tabela de lista agora funcionam corretamente em light e dark mode.

#### Modularização CSS (seguindo KI de Arquitetura)

- CSS da `Index.vue` extraído para arquivo dedicado `patients-index.css` — elimina o arquivo monstruoso anterior de +640 linhas de estilos inline.
- O arquivo é importado estaticamente no `<script setup>` seguindo o padrão de modularização definido no Knowledge Item.

**Arquivos Modificados:**
- `app/controllers/api/v1/accounts/patients_controller.rb` — validação antes da criação do contato
- `app/javascript/dashboard/routes/dashboard/patients/components/NewPatientModal.vue` — validação de nome mínimo 2 chars
- `app/javascript/dashboard/routes/dashboard/patients/Index.vue` — CSS migrado para arquivo externo
- `app/javascript/dashboard/routes/dashboard/patients/patients-index.css` — **NOVO** arquivo CSS dual-theme modularizado

---

## [1.4.3.5] - 2026-03-21 15:17:00-03:00


### Enterprise Unlock, Deduplicação de Grupos e Paginação de Contatos

#### Enterprise: Plano desbloqueado por padrão

- `config/installation_config.yml`: `INSTALLATION_PRICING_PLAN` agora nasce como `enterprise`, `INSTALLATION_PRICING_PLAN_QUANTITY` = `10000`
- `Dockerfile`: env `CHATWOOT_HUB_URL=https://hub.invalid/#` impede que o job `CheckNewVersionsJob` sobrescreva o plano ao sincronizar com o hub externo — `@instance_info` fica `nil` e o job retorna antes de tocar nos configs de plano
- Resultado: toda imagem Docker nova já inicia em modo Enterprise completo, sem precisar de SQL manual

#### Grupos WhatsApp: Race condition na criação de conversas corrigida

- **Causa**: `find_or_create_conversation` buscava por `@contact_inbox.conversations.where(group_id).last`; quando 2 mensagens chegavam do mesmo grupo simultaneamente, ambas não encontravam a conversa existente e cada uma criava uma nova
- **Correção**: A busca passou a usar `Conversation.where(inbox_id:, contact_id:, group_id:)` (escopo mais amplo), com `rescue ActiveRecord::RecordNotUnique` para proteção contra race conditions

#### Paginação de Contatos: Seletor 15 / 50 / 100 por página

- **Backend** (`contacts_controller.rb`): aceita param `page_size` (validado em `[15, 50, 100]`, padrão 15)
- **API** (`contacts.js`): todos os endpoints paginados agora forwaram `page_size`
- **Store** (`actions.js`): `get`, `active`, `search`, `filter` aceitam `pageSize`
- **UI** (`ContactsListLayout.vue`): dropdown "Show [X] per page" no rodapé da lista de contatos
- **Persistência**: seleção salva em `uiSettings.contacts_page_size`

**Arquivos Modificados:**

- `Dockerfile` — `CHATWOOT_HUB_URL`
- `config/installation_config.yml` — plano enterprise + 10000 seats
- `app/services/whatsapp/incoming_message_qr_service.rb` — race condition na criação de conversas de grupo
- `app/controllers/api/v1/accounts/contacts_controller.rb` — suporte a `page_size`
- `app/javascript/dashboard/api/contacts.js` — `page_size` nos endpoints
- `app/javascript/dashboard/store/modules/contacts/actions.js` — `pageSize` nas actions
- `app/javascript/dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue` — state + handler
- `app/javascript/dashboard/components-next/Contacts/ContactsListLayout.vue` — dropdown seletor
- `app/javascript/dashboard/i18n/locale/en/contact.json` — chaves `SHOW` e `PER_PAGE`

## [1.4.3.4] - 2026-03-21 13:29:00-03:00


### WhatsApp QR: API Create Message — Correção de Roteamento de Templates e Falha Silenciosa

#### Problema

Mensagens criadas via API padrão do Chatwoot (`POST /api/v1/accounts/:id/conversations/:id/messages`) em canais WhatsApp QR ficavam com status `sent` (ícone de relógio) permanentemente e nunca eram entregues ao destinatário.

#### Causa Raiz

Quando o payload da API continha `template_params`, o `SendOnWhatsappService#perform_reply` roteava a mensagem para `send_template_message` — mesmo para canais WhatsApp QR. O `WhatsappQrService#send_template` retornava `nil` (pois a bridge Baileys não suporta templates da API oficial). Resultado: a mensagem ficava eternamente como `sent` sem nunca ser entregue nem marcada como falha.

Adicionalmente, o `WhatsappQrService#post_to_bridge` capturava TODAS as exceções silenciosamente e retornava `nil`, sem atualizar o status da mensagem para `failed`.

#### Solução

1. **Roteamento corrigido para WhatsApp QR**: O `SendOnWhatsappService#perform_reply` agora detecta se o provider é `whatsapp_qr` e **sempre** roteia para `send_session_message`, ignorando `template_params`. Templates são exclusivos dos provedores Cloud API e 360Dialog.

2. **Tratamento de falhas com `mark_failed`**: Toda falha de comunicação com a bridge agora marca a mensagem como `status: :failed` com `external_error` descritivo. O UI mostra um ícone de erro vermelho e o usuário pode clicar em "Retry".

3. **Erros granulares**: Diferenciação entre `ECONNREFUSED` (bridge indisponível), `Timeout` (rede lenta) e erros HTTP (503, 500, etc.), cada um com mensagem de erro específica.

4. **Padronização de env vars**: Todos os arquivos aceitam **ambas** as env vars (`WHATSAPP_QR_BRIDGE_URL` → `WHATSAPP_BRIDGE_URL` → fallback `http://localhost:3002`).

5. **Fix de encoding UTF-8**: Respostas da bridge com caracteres acentuados (ex: "não está conectado") não causam mais `incompatible character encodings`.

#### Teste Realizado (Local)

- API com payload contendo `template_params` → agora roteia para `send_session_message` ✅
- Mensagem criada via API → Sidekiq processou → bridge entregou em 48ms → `status: delivered` ✅
- Bridge indisponível → mensagem marcada como `failed` com `external_error` descritivo ✅

**Arquivos Modificados:**

- `app/services/whatsapp/send_on_whatsapp_service.rb` — roteamento corrigido: WhatsApp QR **sempre** usa `send_session_message`
- `app/services/whatsapp/providers/whatsapp_qr_service.rb` — `mark_failed`, erros granulares, fix encoding, env var padronizada
- `app/jobs/delete_object_job.rb` — env var padronizada
- `app/models/channel/whatsapp.rb` — env var padronizada
- `app/controllers/api/v1/accounts/whatsapp/bridges_controller.rb` — env var padronizada
- `app/services/whatsapp/incoming_message_qr_service.rb` — anti-duplicação de contatos (LID → JID)

---

## [1.4.3.3] - 2026-03-19 23:25:00-03:00

### Agenda: Refatoração do Modal de Informações, Prontuário, Busca Telefônica Mágica e Cancelamento Motivacional

#### Melhorias Visuais e de Usabilidade
- **Aperfeiçoamento do Popup do Evento:** O popup de detalhes rápidos de um evento foi radicalmente melhorado. Agora ele exibe a **foto atual/histórica** do paciente, bem como o **Tratamento/Procedimento** atrelado ao evento e mapeia corretamente a **Observação** (dinâmica) vinda da criação.
- **Navegação Imersiva:** O botão de "Prontuário" no popup de evento deixou de abrir um insatisfatório e incompleto sub-popup fluante lateral. Agora ele executa um redirecionamento limpo e imediato à Rota Raiz do Prontuário do BeClinic, mantendo a tela imersiva na história daquele paciente.

#### Reestruturação de Fluxos e Correções Críticas (Bug Fixes)
- **Criação Rápida Livre de Duplicações:** Foi mitigado com rigor um erro onde a criação rápida na agenda resultava em pacientes fantasma no banco de dados (que mostravam erro 'Paciente não encontrado' no front-end).
  - O autocomplete de telefone passou a consumir o **ContactAPI**, e não o Patients API que impedia filtragem fluída via Wildcard Like.
  - Ao clicar numa sugestão de telefone existente, o sistema usa o `contact_id` para realizar checagem inteligente via `PatientsAPI.byContact`. Acertando na mosca o registro real, prevenindo orquestração confusa. O event binding funciona suavemente desde a criação!
- **Proteção do Histórico (Exclusão Motivada):** Os botões de atalho pela visão mensal/semanal de eventos não apagam de forma perniciosa os eventos com um prompt silencioso. Exigem a modal de **Confirmação e Justificativa**. "Cancelado pelo paciente", "Tráfego/Erro", etc. Tudo catalogável daqui para frente.

#### Remoções e Limpeza de Código
- Retirados os campos de "Como conheceu" e etc. O sistema passará focar em Observação de agenda de fábrica.
- Grande limpeza em `AgendaDashboard.vue`: O layout complexo e os estados que suportavam o antigo `patientRecordPopup` foram varridos, destravando leveza no componente.

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

## [1.4.3.2] - 2026-03-19 20:25:00-03:00

### Agenda: Redesign Avançado dos Cards de Evento & Status

- **Sistema de 4 Tiers (Responsividade Inteligente)**: Cards agora se adaptam a 4 alturas pré-definidas ('micro' ≤15m, 'compact' ≤30m, 'medium' ≤50m, 'normal') otimizando exibição de informações com base na duração.
- **Cor do Tratamento no Card**: A borda esquerda do card agora reflete fielmente a cor configurada para o tratamento do paciente (ex: Avaliação, Limpeza), facilitando leitura visual da agenda.
- **Bolinha de Status Inline**: O indicador de status do evento (Agendado, Confirmado, Chegou, Em atendimento, Cancelado, etc) agora se posiciona elegantemente ao lado direito do nome do paciente em todos os tamanhos de card.
- **Tooltip de Informação Rápida**: Adicionado tooltip nativo (`title`) em todo o card de evento, permitindo que ao passar o mouse, o usuário veja instantaneamente o "Nome do Paciente - Status do Evento", agilizando a leitura quando nomes estão truncados (longos).
- **Correção Geral de UI**: Reordenamento da lupa (Search) para sempre aparecer à esquerda da estrela e estar sempre visível (removido hover oculto em tiers de curto tempo).

**Arquivos Modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

## [1.4.3.1] - 2026-03-19 17:45:00-03:00

### WhatsApp Bridge: Sistema de Cleanup Definitivo — Sessões Nunca Mais Viram Fantasmas

Implementação de um sistema completo de 3 camadas para garantir que sessões WhatsApp excluídas sejam **permanentemente eliminadas** do disco, memória e bridge.

---

#### 🔴 Camada 1: Endpoint `DELETE /sessions/:inboxId` (Bridge)

Novo endpoint que **destrói completamente** uma sessão WhatsApp:
1. Desconecta o WebSocket
2. Remove todos os event listeners
3. Cancela todos os timers (reconnect, stableConnection)
4. Remove a sessão do Map em memória
5. **Apaga a pasta inteira** do disco (`auth_info/`, `config.json`, tudo)

```bash
# Exemplo de uso:
curl -X DELETE http://localhost:3002/sessions/28
# → { "success": true, "message": "Sessão 28 destruída permanentemente" }
```

**Arquivo modificado:**
- `lib/whatsapp/server.js` — Novo `app.delete('/sessions/:inboxId', ...)`

---

#### 🔴 Camada 2: Hook Rails `DeleteObjectJob` → Bridge (Auto-cleanup)

Quando um inbox WhatsApp é **excluído pela UI** (botão "Excluir" nas Caixas de Entrada), o `DeleteObjectJob` agora chama automaticamente `DELETE /sessions/:inboxId` no bridge **ANTES** de destruir o registro no banco.

- Usa `Net::HTTP` com timeout de 5s
- Silencia falhas: se o bridge estiver fora do ar, a exclusão do inbox **prossegue normalmente**
- Log de auditoria: `[WHATSAPP_CLEANUP] 🗑️ Destruindo sessão X no bridge...`

**Arquivo modificado:**
- `app/jobs/delete_object_job.rb` — Novo `cleanup_whatsapp_bridge_session` no private

---

#### 🟢 Camada 3: Validação no Boot (`rehydrateSessions`)

Ao iniciar, o bridge agora **verifica credenciais** de cada sessão antes de iniciar:
- Se `auth_info/` não existe ou tem <2 arquivos → sessão fantasma
- Sessões fantasmas são **automaticamente deletadas do disco** e logadas
- Resultado: impossível re-iniciar sessões mortas

**Arquivo modificado:**
- `lib/whatsapp/server.js` — `rehydrateSessions()` com validação e auto-limpeza

---

## [1.4.3.0] - 2026-03-19 17:40:00-03:00

### WhatsApp Bridge: Performance Crítica + Resolução de Contatos `fromMe` + Limpeza de Sessões Fantasmas

Correção de múltiplos problemas críticos de performance e funcionalidade no motor WhatsApp (Baileys bridge).

---

#### 🔴 Fix Crítico: Sessões Fantasmas Matando Performance

**Problema**: O bridge re-hidratava **15 sessões** ao iniciar (13-28), sendo que **14 delas eram fantasmas** — inboxes criadas por cliques duplicados no botão "Finalizar" que nunca chegaram a conectar. Cada uma abria um WebSocket ao WhatsApp Web, gerava QR codes infinitamente e causava erros 408 (timeout) em cascata, saturando CPU, RAM e Redis.

**Solução**:
- Removidas 14 sessões fantasmas do disco (~52.000 arquivos de auth mortos na sessão 13 sozinha)
- `rehydrateSessions()` agora **valida credenciais antes de iniciar**: verifica se `auth_info/` existe e tem ≥2 arquivos de credencial
- Sessões inválidas são **automaticamente removidas do disco** e logadas
- Resultado: bridge inicia com **1 sessão** (a real) e conecta em <2s

**Arquivos modificados:**
- `lib/whatsapp/server.js` — `rehydrateSessions()` com validação de credenciais e auto-limpeza

---

#### 🔴 Fix Crítico: Performance de Envio de Mensagens (5 Gargalos)

**Problema**: Enviar mensagens (especialmente áudio) demorava 5-15 segundos ou falhava silenciosamente.

**Gargalos corrigidos:**

| # | Gargalo | Antes | Depois | Economia |
|---|---------|-------|--------|----------|
| 1 | Import dinâmico de `node-fetch` | `import()` ESM a cada chamada (~200-500ms) | `require()` uma vez no topo | ~400ms/msg |
| 2 | Processamento sequencial | `for...of await` (msgs em fila) | `Promise.allSettled` (paralelo) | 2-10x |
| 3 | Conversão de áudio desnecessária | Todo áudio passava por ffmpeg | Detecta OGG/Opus e pula | 2-5s |
| 4 | ffmpeg sem timeout | Travava indefinidamente | Timeout de 15s + fallback | ∞→15s max |
| 5 | Rails com timeout de 30s | Worker Sidekiq preso | 15s texto, 25s áudio | 5-15s |

**Arquivos modificados:**
- `lib/whatsapp/server.js` — Import estático, processamento paralelo, conversão inteligente, timeouts
- `app/services/whatsapp/providers/whatsapp_qr_service.rb` — Timeouts dinâmicos, logs com timing em ms

---

#### 🟢 Feature: Mensagens `fromMe` Criam Contato do Destinatário

**Problema**: Ao enviar mensagem pelo celular para alguém que não estava na plataforma, a conversa aparecia como "Eu" (usando o próprio número como contato) em vez de criar o contato do destinatário.

**Solução**: O `IncomingMessageQrService` agora diferencia 3 cenários:

| Cenário | Contato criado | Tipo da mensagem |
|---------|----------------|------------------|
| Grupo | Contato do grupo | incoming/outgoing |
| Privado `fromMe` | **Destinatário** (remoteJid) | outgoing |
| Privado recebido | Remetente (sender_jid) | incoming |

**Bonus — Nome do destinatário**: O bridge mantém um `contactNameCache` por sessão alimentado por:
1. `contacts.upsert` / `contacts.update` (sincronização do WhatsApp)
2. `pushName` de cada mensagem recebida

Se o cache tiver o nome, é enviado como `recipient_name` para o Rails.

**Arquivos modificados:**
- `app/services/whatsapp/incoming_message_qr_service.rb` — Nova branch `elsif is_from_me` na resolução de contato
- `lib/whatsapp/server.js` — `contactNameCache` por sessão, `recipient_name` no payload

---

#### 🟢 Feature: Atualização Automática do Nome do Contato

**Problema**: Contatos criados via `fromMe` ficavam com o número de telefone como nome, mesmo depois que a pessoa respondia.

**Solução**: Quando uma mensagem `incoming` chega de um contato cujo nome atual é genérico (começa com `+` ou é igual ao phone_raw), o nome é automaticamente atualizado com o `pushName` do WhatsApp.

- Aceita **qualquer** caractere como nome válido (til `~`, emojis, acentos, etc.)
- Log de auditoria: `[WHATSAPP_QR] 👤 Nome do contato atualizado: +5511... → Maila`

**Arquivo modificado:**
- `app/services/whatsapp/incoming_message_qr_service.rb`

---

#### 🟢 Fix: Mensagens `fromMe` em Grupos Não Carregavam (Spinner)

**Problema**: Mensagens enviadas pelo celular em grupos apareciam como "Nova Mensagem" com spinner infinito, precisando de F5 para carregar.

**Causa**: O `msg_sender` era `nil` para todas as mensagens `fromMe`. O ActionCable precisa de um sender válido para serializar corretamente a mensagem para o frontend.

**Solução**: Para `fromMe` em **grupos**, o sender é o primeiro agente da inbox (`inbox.inbox_members.first&.user`). Para `fromMe` privado, continua `nil` (representa o agente/conta).

**Arquivo modificado:**
- `app/services/whatsapp/incoming_message_qr_service.rb`

---

## [1.4.2.2] - 2026-03-19 16:00:00-03:00

### Nova Regra Global de Arquitetura: Modularização Obrigatória

Foi adicionada uma nova diretriz rígida no Knowledge Items (KI) voltada à modularização de código, para evitar a criação de arquivos monstruosos (como `AgendaDashboard.vue`).

**Regras Estabelecidas:**
- Toda nova seção, área ou módulo grande de negócio criado (ex: "Área de Pacientes", "Área de Agenda") deverá possuir uma **estrutura de arquivos e pastas dedicada e isolada**.
- Essa separação afeta não só a estrutura principal, como também desde as lógicas das **funcionalidades**, parte **visual/UI** e **Estilos (CSS)**. Nada deverá ser agrupado.
- Nenhum código de um módulo ou subcomponente complexo deve ficar junto com outro arquivo não-relacionado.
- Exemplo prático: Modais complexos ou painéis laterais que ocupem centenas de linhas deverão ser isolados em componentes separados na mesma pasta raiz de sua página parente, e não mais injetados diretamente na View global.

---

## [DEPLOY] Docker Push — benuv/chatwoot:v1.4.2.1 — 2026-03-16 18:45:00-03:00

### Build e Push da Imagem Docker para Produção

- **Imagem publicada**: `benuv/chatwoot:latest` e `benuv/chatwoot:v1.4.2.1`
- **Registry**: Docker Hub — `docker.io/benuv/chatwoot`
- **Plataforma**: `linux/amd64` (para o servidor EasyPanel)
- **Estratégia de build**: Cache preservado — apenas layers com mudanças foram reconstruídas
- **O que mudou**: RBAC security hardening — 15+ actions de controllers sem `authorize` corrigidas, bug crítico no navigation guard do Vue Router (`getRole` → `getBeclinicRole`), sidebar oculta "Unattended" por permissão
- **Próximo passo**: Realizar **Redeploy** no EasyPanel para que o serviço faça pull de `benuv/chatwoot:latest`

---

## [DEPLOY] Docker Push — benuv/chatwoot:v1.3.2.0 — 2026-03-15 23:15:00-03:00


### Build e Push da Imagem Docker para Produção

- **Imagem publicada**: `benuv/chatwoot:latest` e `benuv/chatwoot:v1.3.2.0`
- **Registry**: Docker Hub — `docker.io/benuv/chatwoot`
- **Plataforma**: `linux/amd64` (para o servidor EasyPanel)
- **Estratégia de build**: Cache preservado — apenas layers com mudanças foram reconstruídas
- **Próximo passo**: Realizar **Redeploy** no EasyPanel para que o serviço faça pull de `benuv/chatwoot:latest`

---

## [1.4.2.0] - 2026-03-16 17:35:00-03:00

### RBAC — Fase 8: Hardening & QA de Segurança Backend

Garante que a autorização é aplicada no servidor — o frontend nunca é a única linha de defesa.

#### Arquivos modificados:

- `app/policies/application_policy.rb` — Adicionados helpers `beclinic_can?(module, action)` e `beclinic_scope(module)` disponíveis em todas as subclasses via `private`. Delegam ao concern `BeclinicPermissible` no `User`.

- `app/policies/patient_policy.rb` — **Refatorado completamente**: usa `beclinic_can?` para cada ação. `PatientPolicy::Scope` implementa `scope=own` filtrando por `responsible_professional_id` quando o perfil do usuário tem escopo restrito.

- `app/policies/clinical_note_policy.rb` — Refatorado: usa permissões granulares (`view_clinical_notes`, `create_clinical_notes`, `sign_clinical_notes`, `delete_clinical_notes`).

- `app/policies/agenda_event_policy.rb` — Refatorado: usa `beclinic_can?` + `AgendaEventPolicy::Scope` implementa `scope=own` filtrando por `user_id` (dentista/especialista responsável).

- `app/policies/transaction_policy.rb` — Refatorado: usa permissões granulares do módulo `:financial`.

- `app/policies/financial_estimate_policy.rb` — Refatorado: usa permissões granulares do módulo `:financial`.

- `app/policies/consent_record_policy.rb` — Refatorado: usa `view_consents` e `manage_consents`.

- `app/policies/document_policy.rb` — Refatorado: usa `view_documents` e `manage_documents`.

- `app/policies/exam_media_policy.rb` — Refatorado: usa `view_exams` e `manage_exams`.

- `app/policies/treatment_plan_policy.rb` — Refatorado: usa `view_treatment_plans` e `manage_treatment_plans`, mantendo guard de `status_proposto?`.

- `app/policies/anamnesis_policy.rb` — Refatorado: usa permissões de clinical notes, mantendo guard de `status_finalized?`.

#### Novo arquivo criado:

- `lib/tasks/beclinic_rbac.rake` — Rake tasks de retrocompatibilidade:
  - `beclinic:rbac:ensure_default_profiles` — Cria os 4 perfis preset (recepcionista, especialista, gerente, sdr) para contas que ainda não os têm
  - `beclinic:rbac:assign_missing_users` — Atribui usuários sem perfil ao time 'especialista' como fallback
  - `beclinic:rbac:status` — Imprime visão geral de cobertura RBAC por conta

#### Segurança garantida após Fase 8:
- `super_admin` bypass funcional via `beclinic_super_admin?` (mapeia para `super_admin?`)
- Teams com `beclinic_role=dono` têm acesso total automaticamente
- Usuários sem nenhum time recebem `{}` de permissões (negado por padrão)
- `scope=own` aplicado no banco de dados via `policy_scope` — não pode ser contornado via frontend

---

## [1.4.1.0] - 2026-03-16 20:25:00-03:00

### RBAC — Fase 7: Tela de Gestão de Perfis em Settings

Interface completa para Donos e Gerentes gerenciarem os perfis RBAC da clínica diretamente em **Settings → Perfis & Permissões** (`/settings/roles`).

#### Novos arquivos criados:

- `app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles/beclinicRoles.routes.js` — Rota `/settings/roles/list` registrada como `beclinic_roles_list`
- `app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles/Index.vue` — Tela principal com dois painéis:
  - **Grid de Perfis**: cards com nome, badge Padrão/Customizado, badge de nível (Dono/Gerente/Especialista), mini-indicadores de módulos com permissão, contagem de membros e avatars empilhados, ações de editar/deletar
  - **Tabela de Agentes**: lista todos os agentes com perfil atual e botão "Atribuir Perfil"
- `app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles/RoleFormModal.vue` — Modal de criação/edição com dois modos:
  - **Perfis Padrão**: grade visual com os 4 presets (Recepcionista, Especialista, Gerente, SDR) — ao selecionar, preenche automaticamente todas as permissões
  - **Customizado**: campo de nome, seleção de nível base e checkboxes granulares organizados por módulo (Pacientes, Agenda, Financeiro, Chat, Settings)
- `app/javascript/dashboard/routes/dashboard/settings/BeClinicRoles/AssignRoleModal.vue` — Modal de atribuição com lista de radio buttons mostrando todos os perfis disponíveis (nome, nível, indicadores de módulos), perfil atual destacado, opção "Sem perfil" para remover
- `app/javascript/dashboard/api/beclinicRoles.js` — API client para CRUD de Times/Perfis + `addMember`/`removeMember` via `team_members` endpoint

#### Arquivos modificados:

- `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js` — Rota `beclinicRoles.routes` adicionada

#### Integração com backend existente:

Utiliza a API nativa de Teams (`/api/v1/accounts/:id/teams`) que já foi estendida na Fase 1 com:
- `beclinic_role` (string: dono/gerente/especialista) — já nos strong params e serializer
- `permissions` (JSONB) — já nos strong params e serializer
- `is_preset` (boolean) — já nos strong params e serializer

---

## [1.4.0.0] - 2026-03-16 17:21:00-03:00

### RBAC — Role-Based Access Control: Fases 1 a 6 Implementadas

Esta versão entrega as **6 primeiras fases** do sistema completo de controle de acesso baseado em papéis (RBAC) do BeClinic. O sistema é **híbrido**: a plataforma entrega perfis pré-configurados como ponto de partida, mas cada clínica pode editar, excluir ou criar perfis totalmente customizados.

> **Referência completa:** Ver `RBAC_Plan.md` na raiz do projeto para o plano detalhado com todas as permissões, hierarquia de roles e decisões de arquitetura.
> **Status atual:** Fases 1 a 6 ✅ concluídas. Fases 7 (Gestão de Perfis em Settings) e 8 (Hardening & QA) pendentes para o próximo sprint.

---

#### ✅ FASE 1 — Fundação Backend (Rails)

**Novos arquivos criados:**

- `db/migrate/XXXXXX_create_beclinic_roles.rb` — Migration que cria a tabela `beclinic_roles` (campos: `id`, `account_id`, `name`, `description`, `is_preset`, `base_role` enum, `permissions` JSONB, timestamps)
- `db/migrate/XXXXXX_add_beclinic_role_id_to_account_users.rb` — Adiciona `beclinic_role_id` em `account_users` (FK para `beclinic_roles`)
- `app/models/beclinic_role.rb` — Model `BeClinicRole` com validações, defaults e serialização do JSONB de permissões
- `app/models/concerns/beclinic_permissible.rb` — Concern incluído no `User` com helpers `can?(:module, :action)` e `permission_scope(:module)`
- `app/controllers/api/v1/accounts/beclinic_roles_controller.rb` — CRUD completo de perfis + endpoint `PUT /assign` de perfil ao usuário
- `app/policies/transaction_policy.rb` — Pundit policy para transações financeiras
- `app/policies/financial_estimate_policy.rb` — Pundit policy para orçamentos
- `db/seeds/beclinic_roles.rb` — Seed com os 4 perfis padrão (Recepcionista, Especialista, Gerente, SDR) criados automaticamente por conta

**Arquivos modificados:**
- `app/policies/patient_policy.rb` — Expandido com suporte a `scope`, `view`, `create`, `edit`, `delete`, `view_clinical_notes`, etc.
- `config/routes.rb` — Rota para `beclinic_roles` com nested resources em `accounts`

---

#### ✅ FASE 2 — Fundação Frontend (Vue.js)

**Novos arquivos criados:**

- `app/javascript/dashboard/store/modules/beclinicPermissions.js` — Vuex module que carrega as permissões do usuário logado via `GET /api/v1/accounts/:id/beclinic_roles/my_permissions`. Carregado no boot da aplicação.
- `app/javascript/dashboard/composables/usePermissions.js` — Composable central do RBAC: `can('financial', 'view_transactions')` retorna `true | false`; `scope('agenda')` retorna `'all' | 'own'`
- `app/javascript/dashboard/components/PermissionGate.vue` — Wrapper que recebe `module` e `action` e usa slot `#locked` para UI de cadeado quando sem permissão
- `app/javascript/dashboard/components/LockedTab.vue` — Visual de aba bloqueada com ícone de cadeado e tooltip
- `app/javascript/dashboard/components/Page403.vue` — Página de acesso negado para rotas protegidas
- `app/javascript/dashboard/directives/vCan.js` — Diretiva `v-can` que atua como `v-if` automático baseado em permissões: `<button v-can="['financial', 'delete_transaction']">Estornar</button>`

**Arquivos modificados:**
- `app/javascript/dashboard/app.js` — Registra `v-can` globalmente e despacha `beclinicPermissions/fetch` no boot
- `app/javascript/dashboard/store/index.js` — Registra o módulo `beclinicPermissions` na store Vuex

---

#### ✅ FASE 3 — Prontuário do Paciente

**Arquivo modificado:** `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

Gates de permissão aplicados no `allTabs` (computed que controla abas visíveis):

| Aba | Permissão exigida |
|---|---|
| Evoluções Clínicas | `patients.view_clinical_notes` |
| Plano de Tratamento | `patients.view_treatment_plans` |
| Consentimentos | `patients.view_consents` |
| Documentos | `patients.view_documents` |
| Exames e Imagens | `patients.view_exams` |
| Financeiro | `financial.view_transactions` |
| Auditoria | `patients.view_audit` |

Botões com `v-can`: Deletar Paciente (`patients.delete`), Assinar Evolução (`patients.sign_clinical_notes`), Deletar Evolução (`patients.delete_clinical_notes`), Aprovar Plano (`patients.manage_treatment_plans`), Gerar Documento (`patients.manage_documents`), Upload de Exame (`patients.manage_exams`). Campos de cadastro em read-only para perfis sem `patients.edit`. Filtro de escopo: `scope=own` passa `responsible_professional_id` para o backend.

---

#### ✅ FASE 4 — Configurações de Times (Settings → Teams)

> Decisão de produto: ao invés de criar uma tela separada de "Agenda", o RBAC é configurável diretamente dentro da aba **Configurações → Times**, aproveitando o wizard de edição de times existente.

**Novo arquivo criado:**

- `app/javascript/dashboard/routes/dashboard/settings/teams/edit/TeamPermissions.vue` — Etapa "Permissões" no wizard de edição de times com dois modos:
  - **Perfis Predefinidos:** grade visual com os 4 perfis (Recepcionista, Especialista, Gerente, SDR), cada um com badge, descrição e lista de permissões principais
  - **Customizado:** toggles granulares organizados por módulo (Pacientes, Agenda, Financeiro, Chat, Settings)
  - Ao salvar, faz `PUT /api/v1/accounts/:id/teams/:teamId/permissions`

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/settings/teams/edit/Index.vue` — Wizard agora tem 4 passos: Detalhes → Agentes → **Permissões** → Finalizar
- `app/javascript/dashboard/routes/dashboard/settings/teams/teams.routes.js` — Rota `/settings/teams/:teamId/edit/permissions` adicionada
- `app/javascript/dashboard/i18n/locale/en/teamsSettings.json` — Novas chaves de tradução para a etapa de Permissões

---

#### ✅ FASE 5 — Módulo Financeiro

**Arquivo modificado:** `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

Aba "Financeiro" no `allTabs` agora exige `financial.view_transactions`. Botões com `v-can`:

| Botão | Permissão |
|---|---|
| Novo Orçamento | `financial.create_estimate` |
| Receber Pagamento (header) | `financial.create_transaction` |
| Receber (linha da tabela) | `financial.create_transaction` |
| Estornar transação | `financial.delete_transaction` |
| Aprovar Orçamento | `financial.approve_estimate` |
| Cancelar Orçamento | `financial.edit_estimate` |

---

#### ✅ FASE 6 — Chat / Conversas (WhatsApp)

**Arquivos modificados:**

- `app/javascript/dashboard/components-next/message/Message.vue` — `contextMenuEnabledOptions.delete` agora exige `can('chat', 'delete_message')`. Recepcionistas e Especialistas não veem o item "Deletar" no menu de contexto das mensagens.
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` — Grupo "Campanhas" (Live chat, SMS, WhatsApp) oculto para quem não tem `chat.send_broadcast`. Item "Todas as Conversas" oculto para quem não tem `chat.view_all`.

---

#### Mapa de Permissões por Perfil

| Módulo / Ação | Recepcionista | Especialista | SDR | Gerente | Dono |
|---|---|---|---|---|---|
| Pacientes — ver tudo | ✅ | só os seus | ✅ | ✅ | ✅ |
| Pacientes — criar | ✅ | ✅ | ✅ | ✅ | ✅ |
| Pacientes — deletar | ❌ | ❌ | ❌ | ✅ | ✅ |
| Evoluções clínicas | ❌ | ✅ | ❌ | ✅ | ✅ |
| Financeiro — transações | ver+criar | ver+criar | ❌ | tudo | tudo |
| Financeiro — orçamentos | ver | tudo | criar+editar | tudo | tudo |
| Chat — ver tudo | ✅ | ❌ | ✅ | ✅ | ✅ |
| Chat — campanhas | ❌ | ❌ | ✅ | ✅ | ✅ |
| Chat — deletar mensagem | ❌ | ❌ | ❌ | ✅ | ✅ |
| Settings | ❌ | ❌ | ❌ | parcial | tudo |

---

#### Próximos passos (iniciar em nova sessão de chat)

- **FASE 7:** Tela `/settings/roles` — listagem de perfis da clínica, criação, edição e assign de perfil ao usuário (ler `RBAC_Plan.md` seção 7 para todos os detalhes)
- **FASE 8:** Hardening & QA — testes de endpoints sem UI, validação de `scope=own` no backend, edge cases sem perfil atribuído

---

## [1.3.2.0] - 2026-03-15 23:15:00-03:00


### Agenda: Remoção do Placeholder "Selecione o Especialista"

- Removida a opção nula/placeholder `Selecione o especialista` do dropdown de especialista responsável no modal de criação de eventos — o select agora exibe apenas os especialistas reais cadastrados.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

### Prontuário: Busca de Contato por Telefone na Aba Cadastro

A aba **Cadastro** do prontuário do paciente ganhou o mesmo autocomplete de contato que já existia no modal "Novo Paciente". Ao digitar no campo **Telefone Principal**, os contatos do Chatwoot com números similares são sugeridos em um dropdown.

- **Busca debounced** (400ms) disparada a partir de 2 dígitos digitados.
- **Remoção automática do prefixo `+55`**: o `handlePhoneInput` salva o número como `+55XXXXXXXXX`, mas a busca extrai apenas os dígitos locais para que a API encontre correspondências corretamente.
- **Dropdown premium**: avatar colorido determinístico (ou foto real), nome e número do contato.
- **Seleção**: ao clicar num contato, `contact_id` é vinculado ao paciente e o e-mail é auto-preenchido se estiver vazio.
- **Correção da arquitetura**: A aba de Cadastro é inline no `Record.vue` (o `RegistrationTab.vue` existia mas nunca foi importado) — lógica implementada diretamente no componente correto.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

### Agenda: Visibilidade por Role e Pré-seleção de Especialista

- **Role-based visibility**: Administradores veem a agenda de todos; agentes comuns veem apenas seus próprios eventos.
- **Pré-seleção**: O campo "Especialista Responsável" nos modais de criação de evento é automaticamente preenchido com o usuário logado.
- **Renomeação**: "Agente" → "Especialista" em toda a UI da agenda.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`

---


## [1.3.1.1] - 2026-03-14 11:36:00-03:00

### Prontuário: Redesign Premium da Aba Procedimentos e Sessões

#### Aba Procedimentos — Refatoração Visual Completa (STYLE.md)

- **Header padronizado**: substituído `registration-header` por `reg-header` com botões `btn-secondary` (`i-lucide-sliders-horizontal` + "Filtrar") e `btn-primary` ("+ Registrar Sessão")
- **Painel de filtro**: novo `.proc-filter-panel` com posicionamento absoluto, sombra premium, botão X de fechar e campos com `form-label`; usa `reg-field-grid-2` em vez de `form-row-2`
- **Formulário "Registrar Novo Procedimento"**: convertido de `form-section card border-l-4 border-emerald-500` para `reg-section` com `reg-section-icon reg-icon-cyan` (ícone `i-lucide-syringe`), `reg-section-title`, `reg-section-subtitle` e body em `reg-section-body`
  - Grade de campos migrada de `form-row-3`/`form-row-2` para `reg-field-grid-3`/`reg-field-grid-2`
  - Labels com `form-label` e asterisco `reg-required` para campo obrigatório
  - Ações do formulário em `.proc-form-actions` (border-top, flex end) com ícones `w-4 h-4` explícitos
  - Input de data como `.proc-date-input` (sem `w-auto` inline)
- **Histórico de Sessões**: convertido de `card p-0` + tabela genérica para `reg-section` com `reg-section-icon reg-icon-purple` e tabela dedicada `proc-table` com:
  - Cabeçalho `proc-table-head` uppercase, tracking-wide, slate-600
  - Linhas `proc-table-row` com hover sutil e `proc-table-cell` com `vertical-align: top`
  - Células ricas: `proc-cell-primary` + `proc-cell-secondary` para dados hierárquicos
  - Coluna de resultado com `proc-result-ok` (verde), `proc-result-warn` (âmbar), `proc-result-info` (azul)
  - Botão de exclusão `proc-action-btn` (vermelho ao hover)
  - Empty state elegante: `proc-empty-state` + `proc-empty-icon` + `proc-empty-text` + `proc-empty-hint`
- **Contagem de sessões**: badge `proc-count-badge` no header do histórico
- **Adicionados no CSS**: bloco completo `/* PROCEDIMENTOS – estilos exclusivos */` com ~210 linhas definindo todas as classes `proc-*`

#### Arquivo Modificado
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

## [1.3.1.0] - 2026-03-13 18:26:00-03:00

### Prontuário: Timeline Visual + Auditoria e Segurança — Cobertura Completa

#### Timeline de Eventos — Redesign Visual Completo

- **Linha conectora corrigida**: linha contínua centralizada atrás dos ícones (antes saía do lado do círculo como micro-stub)
- **Ícones com fundos sólidos e coloridos por tipo de evento** usando inline styles (hex hardcoded) para imunidade total ao JIT/purge do Tailwind:
  - Cadastro → Índigo · Anamnese → Azul · Agendamento → Laranja · Reagendamento → Amarelo · Consulta Realizada → Esmeralda · Falta → Vermelho · Cancelamento → Rosa · Evolução Clínica → Ciano · Sessão → Teal · Exame/Imagem → Violeta · Documento → Céu · Consentimento → Roxo · Pagamento → Verde · Orçamento → Âmbar · Status Alterado → Slate · Alta → Lima · Recall → Amarelo
- **Paleta refinada (STYLE.md)**: tons ultra-escuros com leve tint da cor no fundo, borda de 1px sutil (não 2px), ícone em pastel médio — flat & minimalista sem saturação excessiva
- **Badges** (tipo de evento): mesma cor sólida do ícone, fundo levemente diferenciado

#### Auditoria e Segurança — Cobertura Completa de Módulos

**Backend — 5 controllers agora auditados (antes nenhum log era gerado):**

- `DocumentsController` → logs em `generate`, `attach`, `destroy`, `status`
- `ConsentRecordsController` → logs em `create`, `sign`, `revoke`
- `TransactionsController` → logs em `create`, `pay`, `destroy`
- `FinancialEstimatesController` → logs em `create`, `update`, `approve`, `destroy`
- `ExamMediasController` → logs em `create`, `update`, `destroy`

**Frontend — Bugs corrigidos:**

- **Bug crítico**: serializer chamava `log.changes` (método ActiveRecord de dirty tracking) em vez de `log.changed_fields` (coluna real do banco após rename migration) → logs de diff de campos eram sempre vazios
- **Filtro de ações corrigido**: `AUDIT_ACTION_OPTIONS` usava `send_whatsapp` e `login_access` que não existem no enum do model — substituídos pelos 10 enums reais: `view, create, update, delete, sign, export, finalize, approve, pay, print`
- **Emojis removidos** do dropdown de filtros (👁✅✏️🗑✍️📄💬🔑) → labels limpas seguindo STYLE.md
- **`formatAuditAction`** expandido com `finalize`, `approve`, `pay`, `print` e ícones Lucide corretos; removidos `send_whatsapp`, `login_access`, `permission_change` (inexistentes no enum)
- **`generateDetailedAuditText`** expandido com todos os resource types: `ConsentRecord`, `Transaction`, `FinancialEstimate`, `SessionLog`, `Recall`, `CriticalAlert`
- **Header STYLE.md**: `h3` sem ícone decorativo, botões usando `btn-primary`/`btn-secondary`

#### STYLE.md — Regra de `box-shadow` Documentada

- **Bug corrigido**: `.btn-primary` tinha `box-shadow: 0 2px 10px rgba(59, 130, 246, 0.2)` — efeito de glow proibido pelo princípio Flat & Minimalista
- Removido `box-shadow` do `.btn-primary` → `box-shadow: none`
- Adicionado `box-shadow: none` explícito em `.btn-secondary` também
- Adicionado `align-self: stretch` em `.btn-secondary` para garantir mesma altura que o botão primário adjacente em contexto flex (corrige desalinhamento do botão X de limpar filtros)
- **STYLE.md atualizado**: seção de Botões agora documenta explicitamente `box-shadow: none` em `.btn-primary` e `.btn-secondary`, e o uso de `align-self: stretch` para botões inline

**Arquivos modificados:**

- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — timeline visual (cores sólidas hex por tipo de evento, linha conectora, badges); aba Auditoria (filtros corrigidos, formatAuditAction expandido, generateDetailedAuditText expandido, botões STYLE.md, paginação); CSS (.btn-primary sem box-shadow, .btn-secondary com align-self: stretch)
- `app/controllers/api/v1/accounts/patients/audit_logs_controller.rb` — `log.changes` → `log.changed_fields`
- `app/controllers/api/v1/accounts/patients/documents_controller.rb` — PatientAuditLog.log! em generate, attach, destroy, status
- `app/controllers/api/v1/accounts/patients/consent_records_controller.rb` — PatientAuditLog.log! em create, sign, revoke
- `app/controllers/api/v1/accounts/patients/transactions_controller.rb` — PatientAuditLog.log! em create, pay, destroy
- `app/controllers/api/v1/accounts/patients/financial_estimates_controller.rb` — PatientAuditLog.log! em create, update, approve, destroy
- `app/controllers/api/v1/accounts/patients/exam_medias_controller.rb` — PatientAuditLog.log! em create, update, destroy
- `docs/STYLE.md` — box-shadow proibido em botões + align-self: stretch documentado

---

## [1.3.0.2] - 2026-03-12 17:55:00-03:00

### Pacientes: Status Coloridos na Lista + Jornada de Consultas Refinada

#### Lista de Pacientes — Status com Cores por Tipo

- Adicionados estilos de cor para todos os statuses na coluna "STATUS" da lista de pacientes (`Index.vue`), alinhados com as cores do prontuário:
  - **Novo** → azul · **Ativo** → verde · **Inativo** → cinza (antes vermelho) · **Faltoso** → âmbar · **Alta** → roxo · **Arquivado** → slate

#### Jornada de Consultas — Restaurada e Refinada

- Layout restaurado ao estilo empilhado: label ("Última Consulta" / "Próxima Consulta") + data + hora em linhas separadas.
- **Título do evento removido** — o campo `title` ("a", "s") não é exibido mais, pois não agrega valor visual.
- **Ícone centralizado verticalmente** — `align-items: center` no `.visit-box` mantém o ícone alinhado ao centro do bloco de informações.

**Arquivos modificados:**

- `app/javascript/dashboard/routes/dashboard/patients/Index.vue`
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

## [1.3.0.1] - 2026-03-12 17:02:00-03:00

### Prontuário: Aba "Visão Geral" — Painel Clínico Completo e Refinamentos

Entrega da aba **Geral** do prontuário com painel clínico, correção das tags clínicas, redesenho visual do status do paciente e da jornada de consultas.

#### Tags Clínicas — Dados Reais da Anamnese

- **Bug corrigido**: Tags exibiam `[object Object]` porque alergias e medicamentos são arrays de objetos `{ name }`, não strings planas.
- Helper `getString(v)` introduzido no computed `computedClinicalTags` para extrair `.name` de objetos ou usar o valor diretamente se for string.
- Resultado: tags agora mostram `Alergia: Penicilina`, `Med: Losartana 50mg`, etc.

#### Dados da Conta — Dropdown de Status do Paciente

- Removido o badge "Adimplente" (que já aparece no banner superior) do card "Dados da Conta".
- Adicionado dropdown **"Status do Paciente"** (Novo / Ativo / Inativo / Faltoso / Alta / Arquivado) diretamente no card, usando o mesmo `handleStatusChange`.

#### Bug Crítico: Status do Paciente Não Era Salvo

- **Causa raiz**: `PatientsAPI.updateStatus` enviava `{ status }` mas o controller Rails esperava `params[:patient_status]`.
- **Correção**: payload alterado para `{ patient_status: status }` — status agora persiste corretamente no banco.

#### Header: Dropdown de Status → Badge Colorido Estático

- O `<select>` de status foi removido do cabeçalho do prontuário.
- Substituído por `<span class="patient-status-badge">` com cor por status:
  - Novo = azul · Ativo = verde · Inativo = cinza · Faltoso = âmbar · Alta = roxo · Arquivado = slate
- Width do badge corrigida para `fit-content` (antes esticava 100% do container).

#### Jornada de Consultas — Layout Compacto

- Redesenhado: de 3 linhas separadas (label / data / hora / título) para layout horizontal minimalista.
- **Nova estrutura**: `Última · 09 de mar. de 2026 · 09:00` em linha única + título do evento abaixo (pequeno, azul) se existir.
- Implementadas classes CSS: `.visit-compact-row`, `.v-time-inline`, `.v-title-compact`.

#### Acesso Rápido Removido

- Removida a linha de 6 botões de navegação rápida (Anamnese, Evoluções, etc.) da aba Geral — menu lateral já cobre esse acesso.

#### Computeds e Dados Reais

- `computedClinicalTags`: lê anamnese real (alergias, medicamentos, histórico médico — diabetes, hipertensão, cardiopatia, gravidez, implantes).
- `activePlanSummary`: busca plano de tratamento ativo (`in_progress` ou `approved`) dos planos reais.
- `responsibleProfName`: resolve da lista de agents pelo `responsible_professional_id`; fallback para o usuário logado.
- `lastAppointmentFormatted` / `nextAppointmentFormatted`: formata data+hora+título dos compromissos reais retornados pelo endpoint `/summary`.
- `onMounted` agora carrega anamnese, planos de tratamento e agents para popular a aba Geral ao abrir.

**Arquivos modificados:**

- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`
- `app/javascript/dashboard/api/patients/index.js`

---

## [1.3.0.0] - 2026-03-12 14:04:00-03:00

### Agenda: Drag-and-Drop de Eventos no Calendário (estilo Google Calendar)

Implementação completa de arrastar-e-soltar eventos na visão semanal e diária da agenda, com animações suaves, snapping em intervalos de 15 minutos e validação de horários bloqueados.

- **Interação fluida**: Clique e segure qualquer evento para iniciar o drag; solte no horário desejado para mover o evento.
- **Ghost de preview**: Durante o arraste, o evento original fica translúcido (25% opacidade) e um ghost azul tracejado se move em tempo real indicando a nova posição.
- **Ancoragem ao clique**: O ponto de clique dentro do evento fica fixo no cursor durante todo o arraste — não importa onde na barra do evento o usuário clicou.
- **Correção de scroll**: A posição do ghost é calculada usando `getBoundingClientRect()` (já inclui o scroll), eliminando o bug onde o ghost descía conforme o usuário rolava a página.
- **Snap a 15 minutos**: A posição final é arredondada para o intervalo de 15 minutos mais próximo, igual ao comportamento do Google Calendar.
- **Preservação de duração**: O evento mantém exatamente a mesma duração após ser movido.
- **Bloqueio de horários**: Se soltar em feriado, exceção, folga ou fora do expediente → alerta e reverte para a posição original.
- **Threshold anti-clique**: O drag só ativa após 6px de movimento — clicar no evento sem arrastar ainda abre o modal de edição.
- **Persistência via API**: No `mouseup`, o evento é atualizado via `agendaEvents/update` com os novos `starts_at` e `ends_at`.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

### Agenda: Correção — Paciente Não Persistido ao Editar Evento

Quando um evento era reaberto para edição, o campo "Paciente" aparecia vazio ("Selecione o paciente") mesmo que um paciente houvesse sido selecionado e salvo anteriormente.

**Causa raiz**: O método `openEditEvent` carregava `contact_id` mas não populava `selectedPatientName` / `selectedPatientPhone`. A computed `selectedContactLabel` dependia dessas propriedades para exibir o nome, e ao encontrá-las vazias, não exibia nada.

**Solução implementada**:
- **`selectContact`**: Agora também salva `patient_id` (ID do registro de paciente) em `newEvent`.
- **Payload de salvamento**: Inclui `patient_id`, `patient_name` e `patient_phone` em `custom_attributes` do evento para garantir persistência independente do vínculo com o contato nativo.
- **`openEditEvent`**: Ao abrir evento existente, lê `custom_attributes.patient_name` / `patient_phone` / `patient_id` para restaurar o estado do dropdown corretamente.
- **Dropdown "selected"**: A classe `selected` agora usa `newEvent.patient_id === patient.id` em vez de comparar `contact_id`, pois `contact_id` pode ser `null` quando o contato nativo foi deletado.
- **Label do campo**: "Contato (Paciente)" → **"Paciente"** em todos os textos da interface (i18n `pt_BR`).

**Arquivos modificados:**
- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`
- `app/javascript/dashboard/i18n/locale/pt_BR/settings.json`

---

### Agenda: Notificações Automáticas com Fallback de Nome do Paciente

O serviço de template das notificações automáticas dependia exclusivamente do `contact.name` (contato nativo do Chatwoot) para preencher a variável `{nome_paciente}`. Quando o contato era deletado e o `contact_id` do evento era nulo, o template exibia "Paciente" genérico.

**Fix**: O `Agenda::NotificationTemplateService` agora usa a seguinte cascata:
1. `event.contact.name` — contato Chatwoot vinculado (quando existe) ✅
2. `event.custom_attributes['patient_name']` — nome salvo no evento (fallback) ✅
3. `'Paciente'` — fallback genérico de último recurso

**Arquivos modificados:**
- `app/services/agenda/notification_template_service.rb`

---

### Pacientes: Busca de Contatos por Telefone no Cadastro — com Avatar

Ao cadastrar um novo paciente, digitar o celular agora sugere contatos existentes do Chatwoot em um dropdown.

**Correção de busca**: O código anterior passava o número formatado `(47)` para a API de busca, mas os contatos no banco estão em formato internacional `+554784226825`. A API usa `ILIKE %query%`, então a busca não encontrava correspondência. Agora os dígitos são extraídos antes de chamar a API — buscar `47` encontra `+554784226825` corretamente.

**Avatar no dropdown**: Cada contato sugerido exibe uma miniatura circular:
- Se o contato tem `avatar_url`: exibe a foto real.
- Se não tem foto: exibe a inicial do nome com cor determinística gerada por hash do nome (paleta de 10 cores, igual ao Chatwoot).

**Ajustes adicionais**:
- Busca começa com apenas **2 dígitos** (antes precisava de 3 chars formatados).
- Debounce reduzido para **400ms** para resposta mais ágil.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/components/NewPatientModal.vue`

---

## [1.2.9.9] - 2026-03-12 01:45:00-03:00

### Agenda: Busca Dinâmica de Pacientes no Agendamento

O componente de agendamento na Agenda Geral da BeClinic foi refatorado para usar uma busca dinâmica em tempo real (com debounce de 300ms) conectada diretamente ao sistema de Pacientes (Prontuário Eletrônico), em vez de depender da listagem completa em memória de Contatos (Chatwoot nativo).

- **Busca via `PatientsAPI`**: O input de "Contato (Paciente)" agora busca na tabela real de pacientes independente do status (`ativo`, `arquivado`, etc).
- **Tratamento Seguro de Chaves Estrangeiras**: O banco de dados do AgendaEvent está associado a `contact_id` nativo. A interface preserva essa estrutura internamente salvando o `contact_id` real vinculado ao paciente selecionado evitando problemas de integridade.
- **Labels Otimizados**: A interface adota preferencialmente o nome capturado na busca na mesma sessão (salvo localmente como `selectedPatientName`) se o contato não possuir um `contact_id`.
- **Experiência Otimizada**: Estado "Vazio", placeholder amigável e dropdown dinâmico acionado na abertura sem pré-carregar os milhares de perfis do banco logo ao inicializar o componente.

**Arquivos modificados:**

- `app/javascript/dashboard/routes/agenda/AgendaDashboard.vue`

---

## [1.2.9.8] - 2026-03-11 20:30:00-03:00

### Prontuário Eletrônico: Aba de Consentimentos — Sistema Completo de Gestão Jurídica

Esta versão entrega a **aba de Consentimentos e Assinaturas** completamente funcional, baseada em auditoria das melhores práticas do setor (Clinicorp, Dentrix, Jane App, Consentz).

#### 11 Tipos de Termos Pré-Definidos com Templates Completos

- **Termo LGPD / Privacidade de Dados**: autorização de coleta e uso de dados conforme Lei 13.709/2018
- **Autorização de Uso de Imagem**: fotos/vídeos para documentação clínica
- **Toxina Botulínica (Botox)**: riscos, efeitos esperados, contra-indicações e ausência de garantia de resultado
- **Preenchimento Dérmico (Filler)**: inclui alerta sobre oclusão vascular e risco de cegueira (extremamente raro)
- **Laser / Fototerapia / LED / Radiofrequência**: cuidados pós-procedimento com fotoproteção
- **Peeling Químico / Dermabrasão**: diferentes profundidades, contra-indicações (isotretinoína, herpes ativo)
- **Paciente Menor de Idade**: autorização do responsável legal (conforme ECA + CFM/CFF)
- **Procedimento Cirúrgico Minor**: biópsia, exérese e outros procedimentos ambulatoriais
- **Anestesia Local/Tópica**: declaração de alergias e medicamentos em uso
- **Termo de Consentimento Geral**: cobertura para procedimentos não enquadrados nas categorias acima

#### Modal de Criação (3 Passos)

- **Passo 1**: Grid visual com ícones para seleção do tipo de consentimento
- **Passo 2**: Título editável + seleção de validade (1, 3, 6, 12, 24, 60 meses ou sem vencimento)
- **Passo 3**: Editor completo do corpo do termo — auto-preenchido com nome e CPF do paciente, 100% customizável

#### Assinatura Digital via Canvas HTML5

- Canvas interativo com suporte a toque (tablet/celular) e mouse
- Traço azul suave com `lineCap: 'round'` para experiência de assinatura premium
- Botão "Limpar" para refazer a assinatura
- Exportação como `data:image/png;base64` via `.toDataURL()`
- Hash SHA-256 gerado automaticamente no backend após confirmar

#### Dashboard de Status (4 KPIs)

Total | Assinados | Pendentes | Vencidos — atualização automática após cada operação

#### Tabela Enriquecida

- Colunas: Documento | Categoria | Validade | Status | Ações
- Badges coloridos: Pendente (amber), Assinado (emerald), Vencido (red), Revogado (slate)
- Hash de integridade truncado + data e IP de assinatura
- Botões context-aware: pendentes → Enviar + Assinar; assinados → Hash + Revogar

#### Demais Funcionalidades

- **Modal de Visualização**: corpo completo do termo + painel de auditoria forense (hash SHA-256, data e IP)
- **Revogação**: confirmação nativa antes de revogar via `PATCH /revoke`
- **Envio Remoto**: link de assinatura por WhatsApp via `POST /send_remote`
- **Empty state inteligente**: mensagem contextual com botão CTA

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — substituição completa da aba de Consentimentos: estado, constantes (`CONSENT_TYPES`, `CONSENT_STATUS_CONFIG`), todas as funções (criar, assinar, visualizar, enviar, revogar), template HTML/Vue com KPIs, tabela enriquecida e 3 modais (criação, assinatura digital com canvas, visualização/auditoria)
- `app/javascript/dashboard/api/patients/consents.js` — adicionados métodos `revoke()` e `delete()`

---

## [1.2.9.7] - 2026-03-11 19:51:00-03:00

### Prontuário Eletrônico: Galeria de Exames — Filtros por Tipo e Visualização Global

- **Filtros por Categoria de Mídia (Frontend)**: Introduzida uma nova barra de filtragem dinâmica na aba de "Exames e Imagens". Agora o profissional pode alternar instantaneamente entre **Imagens**, **Vídeos**, **PDFs** e **Documentos (Word/Excel)** através de botões segmentados com feedback visual por cores exclusivas.
- **Escopo "Todos os Arquivos" (Refatorado)**: A pasta raiz da galeria foi reestruturada para exibir **literalmente todos os arquivos** do paciente, independente de estarem organizados em subpastas ou não. Anteriormente, a visualização "Todos" mostrava apenas arquivos soltos na raiz, o que dificultava a localização rápida de mídias categorizadas.
- **Inteligência de Mimetypes**: Sistema de filtro agora identifica formatos variados (jpg, png, webp, heic, mp4, mov, pdf, docx, xlsx, csv, etc.) cruzando extensões de arquivo com `mime_type` retornado pela API.
- **UX Premium**: Filtros horizontais com suporte a scroll e estados ativos coloridos (Azul para Imagens, Vermelho para PDFs, Esmeralda para Documentos) mantendo a linguagem visual BeClinic.

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue`

---

## [1.2.9.6] - 2026-03-11 16:38:00-03:00

### Prontuário Eletrônico: Aba de Documentos — Geração, Visualização e Gestão Completa

Esta versão entrega a **aba de Documentos** completamente funcional do prontuário eletrônico, cobrindo o ciclo completo de geração server-side de PDFs clínicos via Prawn, exibição na lista com metadados ricos, download via URL assinada do Active Storage, envio por WhatsApp e exclusão com confirmação.

---

#### 🆕 Modal de Geração de Documentos (Novo)

- **Modal inteligente e dinâmico** (`showDocModal`): Substituiu o antigo botão "Gerar Receita Doc" completamente inerte por um modal estruturado que coleta todos os dados necessários antes de chamar o backend. O modal detecta o tipo de documento selecionado e exibe **somente os campos relevantes** para aquele tipo, evitando poluição visual e reduzindo erros de preenchimento.
- **Suporte a 9 tipos de documento** com campos específicos por tipo:

  | Tipo de Documento | Campos Específicos Exibidos |
  |---|---|
  | Atestado Médico (`atestado`) | CID-10 + Dias de afastamento (numérico) |
  | Receita Médica (`receita`) | Medicamentos (nome) + Posologia/instruções |
  | Pedido de Exame (`pedido_exame`) | Exames solicitados — textarea (um por linha) |
  | Encaminhamento (`encaminhamento`) | Para quem (destino) + Especialidade |
  | Relatório Clínico (`relatorio_clinico`) | Campo de conteúdo livre (textarea longa) |
  | Declaração (`declaracao`) | Campo de conteúdo livre |
  | Instruções de Procedimento (`instrucao_procedimento`) | Campo de conteúdo livre |
  | Contrato de Serviços (`contrato`) | Campo de conteúdo livre |
  | Orçamento (`orcamento`) | Campo de conteúdo livre |

- **Campo de observações adicionais**: presente em todos os tipos de documento.
- **Campo de título customizável**: pré-preenchido automaticamente com o label padrão do tipo selecionado, mas 100% editável pelo profissional.
- **Estado de loading** (`docModalLoading`): botão "Gerar e Baixar PDF" entra em estado desabilitado com indicador visual durante o processamento, prevenindo duplo envio.
- **Função `openDocModal()`**: reinicializa o `docForm` com valores padrão toda vez que o modal abre, garantindo formulário limpo independentemente de usos anteriores.

---

#### 🔧 Correção Crítica: Integração Backend — `NoMethodError` 500 na Geração

**Problema:** O endpoint `POST /documents/generate` retornava 500 consistentemente com `NoMethodError: undefined method 'to_unsafe_h' for nil`.

**Causa raiz 1 — Payload aninhado incorretamente:** O método `DocumentsAPI.generate()` enviava o payload dentro de `{ document: payload }`, fazendo `params[:document_type]`, `params[:variables]` e `params[:title]` chegarem como `nil` no controller Rails (que espera params flat, não aninhados sob a chave `document`).

**Fix:** Removido o wrapper `{ document: ... }` — o payload é enviado flat diretamente.

**Causa raiz 2 — Nil não tratado:** O controller chamava `params[:variables].to_unsafe_h.symbolize_keys` sem proteção contra nil. Mesmo após o fix do wrapper, se o usuário não preencher campos de variáveis o objeto pode chegar vazio.

**Fix no controller:** `(params[:variables]&.to_unsafe_h || {}).symbolize_keys` — nil-safe com fallback para hash vazio.

---

#### 🔧 Correção Crítica: PDF Corrompido ("Falha ao carregar documento PDF")

**Problema:** Mesmo quando a geração ocorria com sucesso (HTTP 201), o arquivo baixado era inválido — o Chrome exibia "Falha ao carregar documento PDF".

**Causa raiz — `responseType: 'blob'` incorreto:** O método `generate()` do API client usava `{ responseType: 'blob' }`, esperando receber bytes binários de PDF. Porém, o `DocumentsController#generate` faz `render :show, status: :created` — que invoca o **template Jbuilder** e retorna **JSON** com metadados do documento (`{ id, title, document_type, status, url, generated_by, ... }`). O PDF real é salvo no **Active Storage** e acessado via URL assinada. O frontend tratava o JSON como blob binário, corrompendo o conteúdo.

**Fix:** Removido `responseType: 'blob'`. O fluxo correto agora é:
1. `POST /generate` → Rails gera o PDF com **Prawn**, salva no Active Storage, retorna JSON com `url` (signed URL do Active Storage com validade de 15 min)
2. Frontend extrai `docData.url` diretamente da resposta — o partial `_document.json.jbuilder` já incluía `json.url document.signed_url`
3. `window.open(signedUrl, '_blank')` → abre o PDF real no browser, sem download intermediário

Isso elimina a necessidade de um segundo request ao endpoint `/download` após a geração, simplificando o fluxo para **um único request**.

---

#### 🐛 Correção Crítica: Documentos Não Apareciam na Lista Após Geração

**Problema:** Após gerar um documento e chamar `fetchDocuments()`, a lista permanecia vazia ou com dados antigos — o novo documento não aparecia.

**Causa raiz — Envelope paginado não tratado:** O endpoint `GET /documents` retorna `{ data: [...], meta: { total_count, current_page, total_pages } }` (paginado via Kaminari/Jbuilder). O `fetchDocuments()` fazia `documents.value = res.data` — recebendo o objeto completo `{ data, meta }` em vez do array interno.

**Fix:** `documents.value = res.data?.data || res.data || []` — extrai corretamente o array do envelope paginado, com duplo fallback para compatibilidade com potenciais mudanças futuras do contrato da API.

---

#### 📋 Tabela de Documentos — Exibição Enriquecida e Correta

- **Tipos traduzidos** via `DOC_TYPE_LABELS`: tipos técnicos (ex: `receita`) são exibidos como labels amigáveis (ex: "Receita Médica") — antes aparecia o tipo cru ou traço.
- **Badges de status coloridos** via `DOC_STATUS_CONFIG`:
  - `gerado` → 🔵 Azul — "Gerado"
  - `pendente_assinatura` → 🟡 Amarelo — "Aguard. Assinatura"
  - `assinado` → 🟢 Verde — "Assinado"
  - `enviado` → 🟣 Roxo — "Enviado"
  - `arquivado` → ⚫ Cinza — "Arquivado"
- **Profissional exibido corretamente**: corrigido mapeamento de `doc.generated_by_name` (campo inexistente na API) para `doc.generated_by?.name`, respeitando a estrutura aninhada do Jbuilder (`json.generated_by { json.name ... }`). Antes exibia sempre "Sistema" mesmo para documentos com profissional identificado.
- **Colunas completas**: Documento (título + versão), Tipo, Data, Profissional, Status, Ações.
- **Empty state**: mensagem clara e botão "Gerar Documento" quando a lista de documentos está vazia.

---

#### 🔘 Botões de Ação por Documento

Cada linha da tabela possui três botões de ação:

- **⬇️ Download**: Chama `GET /documents/:id/download` → obtém signed URL do Active Storage → abre em nova aba. Guard: `if (!doc?.id) return` previne chamadas com ID undefined.
- **💬 WhatsApp**: Chama `POST /documents/:id/send_whatsapp` → invoca `DocumentWhatsappSender` no backend que monta o payload no formato Chatwoot e dispara para o WhatsApp do paciente. Guard: `if (!documentId) return` previne 404s com ID undefined (problema que aparecia nos logs de documentos antigos/mock).
- **🗑️ Excluir**: Exibe `confirm()` nativo antes de chamar `DocumentsAPI.delete()`. Remove o item do array local imediatamente após sucesso sem necessidade de refetch.

---

#### 🏗️ Novas Variáveis de Estado e Constantes

```javascript
// Estado do modal
const showDocModal = ref(false);
const docModalLoading = ref(false);
const docActionsOpenId = ref(null);

// Formulário de geração (todos os campos possíveis)
const docForm = ref({
  document_type: 'atestado', title: '',
  cid: '', dias_afastamento: '',
  medicamentos: '', posologia: '',
  exames_solicitados: '',
  encaminhado_para: '', especialidade: '',
  conteudo_livre: '', observacoes: '',
});

// Labels amigáveis para exibição na tabela
const DOC_TYPE_LABELS = {
  receita: 'Receita Médica', atestado: 'Atestado Médico',
  pedido_exame: 'Pedido de Exame', encaminhamento: 'Encaminhamento',
  relatorio_clinico: 'Relatório Clínico', declaracao: 'Declaração',
  instrucao_procedimento: 'Instrução de Procedimento',
  contrato: 'Contrato', orcamento: 'Orçamento',
};

// Configuração visual dos status badges
const DOC_STATUS_CONFIG = {
  gerado:               { label: 'Gerado',             cls: '...' },
  pendente_assinatura:  { label: 'Aguard. Assinatura',  cls: '...' },
  assinado:             { label: 'Assinado',            cls: '...' },
  enviado:              { label: 'Enviado',             cls: '...' },
  arquivado:            { label: 'Arquivado',           cls: '...' },
};
```

---

**Arquivos modificados:**
- `app/javascript/dashboard/routes/dashboard/patients/Record.vue` — Adição de estado e constantes para o modal de geração; função `openDocModal()`; refatoração completa de `generateDocument()` com mapeamento correto de variáveis para o PdfGenerator; refatoração de `downloadDocument()` (removido get() redundante, adicionado guard de `!doc?.id`); refatoração de `sendWhatsAppDocument()` (adicionado guard de `!documentId`); refatoração de `deleteDocument()`; **correção crítica em `fetchDocuments()`** (`res.data.data` em vez de `res.data`); substituição completa do template da aba Documentos com modal de geração, tabela enriquecida, badges coloridos e profissional correto
- `app/javascript/dashboard/api/patients/documents.js` — Removido `{ document: payload }` wrapper e `{ responseType: 'blob' }` do método `generate()`; payload agora é enviado flat para compatibilidade com o controller Rails
- `app/controllers/api/v1/accounts/patients/documents_controller.rb` — Nil-safety adicionada em `params[:variables]&.to_unsafe_h || {}` para prevenir `NoMethodError: undefined method 'to_unsafe_h' for nil:NilClass` quando `variables` não é enviado ou chega como objeto JS vazio

---
