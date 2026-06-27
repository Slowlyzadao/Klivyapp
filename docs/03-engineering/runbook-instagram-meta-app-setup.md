# Runbook: Configurar App Meta para Instagram Business Login

> **Quando usar este runbook:** ao conectar uma conta Instagram em `Settings → Inboxes → New → Instagram` aparecer o erro:
> ```
> Houve um erro ao conectar ao Instagram, por favor, tente novamente
> Failed to exchange token: {"error":{"message":"Unsupported request - method type: get","type":"IGApiException","code":100,"fbtrace_id":"..."}}
> ```

---

## TL;DR

- **NÃO é bug no Klivy/Chatwoot** — código está correto, método GET está correto, doc oficial Meta confirma.
- A mensagem `"Unsupported request - method type: get"` é **misleading** da Meta — significa "app não autorizada a acessar essa conta Instagram", não problema de HTTP method.
- **Solução:** configurar corretamente a app Meta em `developers.facebook.com` (adicionar tester ou passar App Review).

---

## Índice

1. [Causa raiz](#1-causa-raiz)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Diagnóstico rápido (5 minutos)](#3-diagnóstico-rápido-5-minutos)
4. [Caminho A: Modo Development (testes e clínicas piloto)](#4-caminho-a-modo-development-testes-e-clínicas-piloto)
5. [Caminho B: Modo Live (produção SaaS)](#5-caminho-b-modo-live-produção-saas)
6. [Validação pós-configuração](#6-validação-pós-configuração)
7. [Debug: conectei mas não recebo mensagens](#7-debug-conectei-mas-não-recebo-mensagens)
8. [Troubleshooting](#8-troubleshooting)
9. [Checklist final](#9-checklist-final)
10. [Referências](#10-referências)

---

## 1. Causa raiz

A Meta retorna o erro `"Unsupported request - method type: get"` em pelo menos **três cenários distintos** que confundem developers:

| Cenário | O que de fato está acontecendo |
|---|---|
| App em modo **Development** + conta IG não é "Instagram Tester" | A app só pode operar em contas explicitamente autorizadas como testers. Ao tentar outra, Meta rejeita silenciosamente com esse erro genérico. |
| App em modo **Live** sem **App Review** aprovado pra `instagram_business_basic` / `instagram_business_manage_messages` | A app só tem permissão pros próprios admins. Qualquer conta externa = mesmo erro. |
| **Business Verification** pendente ou **Data Use Checkup** vencido | Bloqueio cascateado em todas as permissions Instagram. Mesmo App Review aprovado pode falhar. |

O erro é confuso porque a Meta retorna a mesma string pra todos os três casos, em vez de algo como `"Permission denied"` ou `"App not approved for this scope"`.

**Confirmação técnica:**
- Doc oficial Meta: [/access_token endpoint](https://developers.facebook.com/docs/instagram-platform/reference/access_token/) confirma que método é **GET**.
- Código do Klivy: [app/controllers/concerns/instagram_concern.rb:28-38](../../app/controllers/concerns/instagram_concern.rb#L28-L38) faz GET corretamente.
- Issue de referência: [chatwoot/chatwoot#12656](https://github.com/chatwoot/chatwoot/issues/12656) — "Failed to exchange token for non tester accounts instagram".
- Thread Meta Dev: [resposta aceita](https://developers.facebook.com/community/threads/1300473464802212/) — "Make sure you have added your account in App dashboard".

---

## 2. Pré-requisitos

Antes de começar:

- [ ] Acesso ao Meta for Developers com o email dono da app (`klivy.app@gmail.com` no caso atual)
- [ ] Conta Instagram a ser conectada **deve ser Business ou Creator** (não pode ser perfil pessoal)
- [ ] Conta Instagram **deve estar vinculada a uma Facebook Page** (mesmo se for usar Instagram Direct Login — Meta exige isso para apps business)
- [ ] App Meta já criada com tipo **"Instagram"** ou **"Business"** (não Basic Display — que foi descontinuada em 04/12/2024)
- [ ] `INSTAGRAM_APP_ID` e `INSTAGRAM_APP_SECRET` configurados em `/super_admin/app_config?config=instagram`
- [ ] `INSTAGRAM_VERIFY_TOKEN` configurado (qualquer string aleatória — vai colar igual no painel Meta)

---

## 3. Diagnóstico rápido (5 minutos)

Antes de seguir os caminhos longos, faça este teste pra saber qual cenário você está:

### Teste 1: tente conectar a SUA própria conta Instagram

A conta Instagram **do dono da app Meta** (você, `klivy.app@gmail.com`) é tratada implicitamente como "tester" pela Meta — sempre funciona em modo Development.

1. Logue no Klivy com conta admin da Account de teste.
2. Vá em `Settings → Inboxes → New → Instagram`.
3. Clique "Continuar com o Instagram".
4. Logue na **SUA conta Instagram pessoal/da Klivy** (a vinculada ao email dono da app Meta).

| Resultado | Cenário | Caminho a seguir |
|---|---|---|
| Funciona | App está em Development, sua conta é "tester implícito". Precisa adicionar contas das clínicas como testers ou ir Live | [Caminho A](#4-caminho-a-modo-development-testes-e-clínicas-piloto) ou [Caminho B](#5-caminho-b-modo-live-produção-saas) |
| Mesmo erro | Tem problema mais fundamental: app mal configurada, Business Verification pendente, ou app é tipo errado | Pular pra [Troubleshooting](#7-troubleshooting) seção "App não funciona nem pro dono" |

### Teste 2 (se Teste 1 funcionou): verificar tipo da app

1. Acesse `https://developers.facebook.com/apps/<SEU_INSTAGRAM_APP_ID>/`
2. No menu lateral, procure o item **"Instagram"** ou **"Instagram Basic Display"**.
3. Confirme:

| O que aparece | Significa | Ação |
|---|---|---|
| "Instagram" (sem "Basic Display") | App correto, "Instagram API with Instagram Login" | Seguir [Caminho A](#4-caminho-a-modo-development-testes-e-clínicas-piloto) |
| "Instagram Basic Display" | App tipo descontinuado em 04/12/2024 | Precisa **criar app nova** do tipo correto |
| Nenhum dos dois | App configurada como Facebook Login só, sem produto Instagram | Adicionar produto "Instagram" no menu "Add product" |

---

## 4. Caminho A: Modo Development (testes e clínicas piloto)

Use este caminho enquanto você está em **testes** ou tem **poucas clínicas piloto** (até ~25). É rápido (sem aprovação Meta) mas exige cadastrar cada conta IG como tester antes de conectar.

### Passo A.1: confirmar que a app está em Development

1. `https://developers.facebook.com/apps/<INSTAGRAM_APP_ID>/`
2. No topo da página, perto do nome da app, deve estar escrito **"Em desenvolvimento"** (App Mode badge).
3. Se está como **"Em ativo"** (Live), você está no [Caminho B](#5-caminho-b-modo-live-produção-saas).

### Passo A.2: adicionar a conta Instagram como Tester

Para CADA clínica que vai conectar Instagram:

1. No menu lateral da app, vá em **App Roles → Roles**.
2. Role até a seção **"Instagram Testers"**.
3. Clique **"Add Instagram Testers"**.
4. Digite o **username** da conta Instagram da clínica (exatamente, sem `@`, sem URL completa — só o nome).
   - Exemplo: se o IG é `https://instagram.com/clinicasaomateus`, digite `clinicasaomateus`.
5. Clique **"Submit"**.

**Importante:** o sistema NÃO valida se o username existe. Se digitar errado, o convite vai pra ninguém.

### Passo A.3: clínica aceita o convite

A pessoa dona da conta Instagram da clínica precisa aceitar o convite:

1. Pedir pra ela acessar `https://www.instagram.com/accounts/manage_access/` (logada na conta IG dela).
2. Aba **"Tester Invites"** (ou "Convites de Testador").
3. Verá o convite da sua app Meta. Clicar **"Accept"**.

Convite expira em **30 dias** se não aceito. Se expirar, refazer A.2.

### Passo A.4: conectar pelo Klivy

Agora a clínica consegue conectar:

1. Logue no Klivy com a conta admin da clínica.
2. `Settings → Inboxes → New → Instagram → Continuar com o Instagram`.
3. Logar na conta Instagram da clínica.
4. Autorizar Klivy a acessar mensagens e perfil.
5. Redirect pro Klivy completa. Inbox criada com sucesso.

### Passo A.5: configurar webhook no painel Meta (uma vez só por app)

Isso é por APP, não por conta — então faz uma vez só.

1. No menu lateral, vá em **Instagram → API setup with Instagram login**.
2. Seção **"Configure webhooks"**.
3. Preencher:
   - **Callback URL:** `https://<seu-host-klivy>/webhooks/instagram`
     - Exemplo: `https://app.klivy.com.br/webhooks/instagram`
   - **Verify Token:** o valor que você setou em `INSTAGRAM_VERIFY_TOKEN` no super_admin.
4. Clicar **"Verify and Save"**.
5. Subscribir aos campos:
   - `messages`
   - `messaging_postbacks`
   - `message_reactions`
   - `message_seen`
   - (opcional, conforme necessidade) `messaging_handovers`

Se a verificação falhar, confira:
- URL está acessível publicamente (sem firewall, sem auth)
- Verify Token bate exato (sem espaços extras)
- Endpoint responde 200 com `params['hub.challenge']` (já implementado em [app/controllers/webhooks/instagram_controller.rb:38-42](../../app/controllers/webhooks/instagram_controller.rb#L38-L42))

### Limites do modo Development

- Máximo **25 testers** por app.
- Cada tester precisa aceitar convite manualmente (cantil pesado pra >5 clínicas).
- Sem aprovação Meta = sem permissão pra contas externas.
- **Não pode** anunciar publicamente o produto Klivy como "integra Instagram" sem App Review.

Quando essas limitações apertarem, ir pro [Caminho B](#5-caminho-b-modo-live-produção-saas).

---

## 5. Caminho B: Modo Live (produção SaaS)

Use este caminho quando você quer **qualquer clínica conectar sem precisar cadastro prévio**. Exige App Review da Meta (~5-15 dias úteis) e Business Verification (~1-3 dias úteis).

### Passo B.1: Business Verification

A Klivy (você) precisa estar verificada como business legítimo na Meta.

1. Acesse `https://business.facebook.com/settings/` (Business Manager).
2. Menu **Security Center** ou **Business Info → Verification**.
3. Submeter:
   - **CNPJ** da Klivy
   - **Comprovante de endereço comercial** (conta de luz, contrato de aluguel, etc.)
   - **Website oficial** (Klivy.com.br)
   - **Telefone comercial** verificável
4. Meta envia código por carta/SMS pra confirmar endereço (pode levar 5-10 dias úteis).

**Sem Business Verification, App Review NÃO é aprovado.**

### Passo B.2: Data Use Checkup

Cada permission Instagram exige declaração anual de uso de dados.

1. `developers.facebook.com/apps/<APP_ID>/app-review/`
2. Aba **"Data Use Checkup"**.
3. Pra cada permission requested:
   - Confirmar como você usa os dados
   - Anexar política de privacidade ([Klivy precisa ter URL pública com política](https://klivy.com.br/privacidade))
   - Confirmar que não vende dados a terceiros

### Passo B.3: App Review — submeter permissions

1. `developers.facebook.com/apps/<APP_ID>/app-review/permissions/`
2. Solicitar:

| Permission | Pra que serve | Documentação a anexar |
|---|---|---|
| `instagram_business_basic` | Ler perfil básico (username, profile pic, account_type) | Screencast mostrando onde aparece username/foto no Klivy |
| `instagram_business_manage_messages` | Ler e responder DMs do Instagram | Screencast mostrando inbox + envio/recebimento de mensagem |

3. Pra cada permission, preencher:
   - **Use case:** descrição em inglês (Meta exige) de como o produto Klivy usa essa permission. Exemplo:
     ```
     Klivy is a clinic management SaaS that allows healthcare professionals to
     centralize patient communications. We use instagram_business_manage_messages
     to display Instagram Direct Messages from patients inside the clinic's unified
     inbox, so that receptionists can reply to appointment inquiries without
     leaving the platform.
     ```
   - **Step-by-step instructions:** como o reviewer Meta pode testar (credenciais de uma conta demo, link de login Klivy, conta IG já conectada). Reviewer Meta testa LITERALMENTE seguindo seus passos — escreva detalhado.
   - **Screencast:** vídeo MP4 (60-120s) mostrando o fluxo de conectar IG + receber DM + responder. Sem música, sem cortes confusos. Hospedar no Loom ou YouTube unlisted.

4. Submeter. Tempo de revisão: **5-15 dias úteis**. Meta pode rejeitar pedindo mais info — comum levar 2-3 ciclos pra aprovar.

### Passo B.4: Ativar modo Live

Depois de App Review aprovado:

1. No topo do dashboard da app, alternar **App Mode** de "Development" pra **"Live"**.
2. Meta pode pedir confirmações finais (declaração de uso de dados, política de privacidade vigente, contato de suporte).

### Passo B.5: configurar webhook (mesmo do Passo A.5)

Mesmo procedimento de [Passo A.5](#passo-a5-configurar-webhook-no-painel-meta-uma-vez-só-por-app). Não precisa refazer se já estava configurado em Development.

### Passo B.6: agora qualquer clínica conecta

Sem cadastro prévio de tester. Fluxo idêntico ao Klivy admin do Passo A.4.

---

## 6. Validação pós-configuração

Independente do caminho A ou B, valide depois:

### 6.1 Validação de OAuth (1 minuto)

- [ ] Settings → Inboxes → New → Instagram → "Continuar com o Instagram"
- [ ] Janela popup do Instagram abre
- [ ] Consent screen mostra os escopos:
  - "Acessar dados do perfil"
  - "Acessar mensagens"
- [ ] Após autorizar, redireciona pro Klivy sem erro
- [ ] Inbox aparece em `Settings → Inboxes` com nome = username Instagram da clínica

### 6.2 Validação de webhook (5 minutos)

- [ ] Da conta Instagram conectada, peça pra alguém **enviar uma DM** pra essa conta
- [ ] Mensagem aparece em `Caixa de Entrada` do Klivy em até 5 segundos
- [ ] Responder pela inbox do Klivy
- [ ] Resposta chega no Instagram do remetente

### 6.3 Validação de token long-lived

No Rails console (container `rails-1` ou `web-1` do Easypanel):

```ruby
channel = Channel::Instagram.last
channel.expires_at  # deve ser ~60 dias no futuro
channel.access_token.present?  # true
```

Se `expires_at` é `nil` ou no passado, alguma coisa quebrou no fluxo. Voltar a [Troubleshooting](#7-troubleshooting).

---

## 7. Debug: conectei mas não recebo mensagens

Cenário extremamente comum: o OAuth completa com sucesso, a inbox aparece no Klivy, mas nenhuma DM enviada à conta conectada chega na inbox. Em **90% dos casos** é configuração de webhook **no painel Meta** que não foi feita ou ficou incompleta — não é bug de código.

Esta seção tem 3 verificações em ordem de probabilidade. Faça em sequência — geralmente para na 1ª.

### 7.1 Verificação 1: webhook configurado no painel Meta?

Este é o passo A.5 do [Caminho A](#passo-a5-configurar-webhook-no-painel-meta-uma-vez-só-por-app). Sem isso, a Meta literalmente não sabe pra onde enviar as DMs — o OAuth pode funcionar perfeitamente e as mensagens nunca chegam ao seu servidor.

**Passos:**

1. Acessar `https://developers.facebook.com/apps/<INSTAGRAM_APP_ID>/`
2. Menu lateral: **Instagram → API Setup with Instagram Login**
3. Rolar até a seção **"3. Configure webhooks"**
4. Verificar se aparece preenchido:
   - **Callback URL:** `https://<seu-host-klivy>/webhooks/instagram`
     - Exemplo: `https://app.klivy.com.br/webhooks/instagram`
   - **Verify Token:** mesmo valor que está em `/super_admin/app_config?config=instagram → INSTAGRAM_VERIFY_TOKEN`
   - **Status:** deve aparecer **"Verified"** (verde). Se aparecer "Not Verified" (vermelho), a verificação inicial falhou.
5. Mais abaixo, na seção **"Webhook fields"**, conferir se o campo **`messages`** está com toggle **verde (ativo)**. Os outros (`message_reactions`, `message_seen`, `messaging_postbacks`) são opcionais — mas `messages` é obrigatório.

**Resultado:**

| Situação | Causa | Ação |
|---|---|---|
| Tudo em branco / nunca configurado | Setup nunca foi feito | Seguir [passo A.5](#passo-a5-configurar-webhook-no-painel-meta-uma-vez-só-por-app) — mensagens começam a chegar imediatamente após salvar |
| Configurado mas status "Not Verified" (vermelho) | Verify Token errado OU URL inacessível | Reconferir Verify Token caractere por caractere; testar URL com `curl` (próxima seção) |
| Configurado e Verified mas `messages` desativado | Subscription incompleta | Ativar toggle do campo `messages` |
| Tudo configurado e Verified, `messages` ativo | Webhook OK do lado Meta — problema é outro | Ir pra Verificação 2 |

### 7.2 Verificação 2: o webhook está realmente chegando no Klivy?

Se o painel Meta está OK mas mensagens não chegam, precisamos saber se a Meta está enviando POSTs e se o backend está respondendo certo.

**Passos:**

1. Abrir log do container `web-1` (ou equivalente) no Easypanel — mesmo lugar onde você acompanha logs do Rails normalmente.
2. Manter o log aberto e rolando em tempo real.
3. De **outra conta Instagram** (não a conectada), enviar uma DM curta pra conta conectada. Não funciona se você mandar da própria conta pra ela mesma.
4. Esperar até 10 segundos.
5. Procurar no log por linhas tipo:
   ```
   Started POST "/webhooks/instagram"
   Processing by Webhooks::InstagramController#events
   Completed 200 OK
   ```

**Resultado:**

| O que aparece | Diagnóstico | Ação |
|---|---|---|
| `POST /webhooks/instagram` + `Completed 200 OK` | Webhook chegou e backend processou. Bug está depois (job de processamento ou mapping `instagram_id → Channel`) | Ir pra Verificação 3 |
| `POST /webhooks/instagram` + `Completed 401 Unauthorized` | Verify Token na requisição não bate com o que o backend espera | Reconferir `INSTAGRAM_VERIFY_TOKEN` no super_admin |
| `POST /webhooks/instagram` + `Completed 500` | Erro no processamento | Olhar o stack trace, abrir issue |
| Nada aparece no log | Meta não está mandando | Voltar à Verificação 1 OU subscribe na conta específica falhou (Verificação 3) |

### 7.3 Verificação 3: o Channel::Instagram conseguiu subscribir nessa conta?

Quando você cria um Channel::Instagram pelo Klivy, o backend automaticamente chama a Meta para subscribir webhooks **naquela conta IG específica** (não basta configurar no painel da app). Esse subscribe acontece em `after_create_commit :subscribe` no [app/models/channel/instagram.rb](../../app/models/channel/instagram.rb), e é executado dentro de `rescue StandardError => e` — então **falha silenciosamente**, deixando o channel criado mas sem subscription ativa na Meta.

**Passos:**

1. Conectar no Rails console do container backend:
   ```bash
   # No Easypanel, abrir terminal do container web/rails-1, e:
   bundle exec rails console
   ```
   Em ambiente Docker local (WSL):
   ```bash
   docker compose exec rails-1 bundle exec rails console
   ```
2. Checar o estado do channel criado:
   ```ruby
   c = Channel::Instagram.last
   puts "instagram_id: #{c.instagram_id}"      # deve ter valor numérico longo
   puts "account_id:   #{c.account_id}"
   puts "token presente: #{c.access_token.present?}"
   puts "expires_at:   #{c.expires_at}"        # ~60 dias no futuro
   ```
3. Tentar fazer o subscribe manualmente pra ver o erro real (que foi engolido na criação do channel):
   ```ruby
   require 'httparty'
   response = HTTParty.post(
     "https://graph.instagram.com/v22.0/#{c.instagram_id}/subscribed_apps",
     query: {
       subscribed_fields: 'messages,messaging_postbacks,message_reactions,message_seen',
       access_token: c.access_token
     }
   )
   puts response.code
   puts response.body
   ```

**Resultado:**

| Resposta | Causa | Ação |
|---|---|---|
| `200` + `{"success":true}` | Subscribe agora deu certo. Pode ter sido falha temporária. Tente enviar DM de novo. | Reenviar DM de teste; se ainda falhar, problema é outro |
| `400` + `{"error":{"code":10,"message":"Application does not have permission..."}}` | App sem permission `instagram_business_manage_messages` | Modo Development: adicionar a conta como Instagram Tester. Modo Live: solicitar App Review pra essa permission |
| `400` + `{"error":{"code":100,"message":"Unsupported get request"}}` | App não autorizada nessa conta IG específica | Conta IG precisa virar Tester aceito (Caminho A passo A.3) ou app passar App Review (Caminho B) |
| `400` + `{"error":{"code":190,...}}` | Token expirou ou foi revogado | Reconectar inbox (Settings → Inbox → Reauthorize) |
| `400` + `{"error":{"code":200,...}}` | Conta IG não está conectada a Facebook Page | Vincular Instagram à FB Page em https://accountscenter.instagram.com/ |

### 7.4 Matriz de decisão

| V1 webhook configurado? | V2 chega no log? | V3 subscribe manual | Causa raiz | Solução |
|---|---|---|---|---|
| Não | Não chega | N/A | Webhook nunca foi setado no painel Meta | [Passo A.5](#passo-a5-configurar-webhook-no-painel-meta-uma-vez-só-por-app) |
| Sim mas Not Verified | Não chega | N/A | Verify Token mismatch OU URL inacessível | Reconferir token; `curl https://<host>/webhooks/instagram` |
| Sim e Verified, mas `messages` off | Não chega | N/A | Subscription do campo vazia | Ativar toggle `messages` |
| Sim e tudo OK | Não chega | `success: true` | Subscribe app-level OK mas account-level desconhecido | Verificar V3 retorna OK manualmente; se sim, aguardar 60s e testar de novo |
| Sim e tudo OK | Não chega | `error code 10` | App sem permission Instagram messaging | Caminho A (tester) ou Caminho B (App Review) |
| Sim e tudo OK | Não chega | `error code 190` | Token expirado | Reauthorize inbox |
| Sim e tudo OK | Chega 200 OK | `success: true` | Backend recebe mas não cria conversa | Bug processamento — ver [chatwoot#11578](https://github.com/chatwoot/chatwoot/issues/11578) e logs do Sidekiq (`docker logs sidekiq-1`) |
| Sim e tudo OK | Chega 401 | N/A | `INSTAGRAM_VERIFY_TOKEN` no super_admin não bate com painel Meta | Reconferir caractere por caractere; salvar e re-verificar |
| Sim e tudo OK | Chega 500 | N/A | Erro no processamento backend | Stack trace no log; ChatwootExceptionTracker se Sentry ativo |

### 7.5 Coletar info se nada resolver

Se as 3 verificações não apontaram causa óbvia, colete estas informações antes de abrir issue/perguntar:

- Output do Rails console no Passo 7.3 (sanitizar `access_token` antes de compartilhar)
- 30 segundos de log do `web-1` quando você envia DM de teste
- Screenshot do painel Meta seção "Webhooks" da app
- Versão do Klivy (rodar `git rev-parse --short HEAD` no diretório do projeto)
- Resposta do Sidekiq job (se chegou no backend): `docker logs sidekiq-1 --tail 100`

---

## 8. Troubleshooting

### "Continuou dando o mesmo erro depois de adicionar como tester"

Possíveis causas:
1. **Tester não aceitou o convite ainda.** Confirmar em `https://www.instagram.com/accounts/manage_access/` da conta tester que aparece em "Active" (não "Pending").
2. **Username digitado errado.** Apagar e re-cadastrar (passo A.2).
3. **Conta Instagram NÃO é Business/Creator.** Conta pessoal não funciona. Converter pelo app Instagram: `Configurações → Conta → Mudar para conta profissional`.
4. **Conta Instagram NÃO está vinculada a Facebook Page.** Mesmo Instagram Direct Login exige link no backstage. Vincular em `https://accountscenter.instagram.com/`.

### "App não funciona nem pro dono" (Teste 1 do diagnóstico falha)

1. **App é tipo Basic Display (descontinuado).** Confirmar em `Add Product` no menu lateral. Se aparecer "Instagram Basic Display" listado e não "Instagram", a app é do tipo errado. Solução: criar app nova do zero como tipo "Business" e adicionar produto "Instagram".
2. **App Secret está errado.** Confirmar em `Settings → Basic` do painel Meta. Comparar caractere por caractere com o que está em `/super_admin/app_config?config=instagram → INSTAGRAM_APP_SECRET`.
3. **Business Verification pendente.** Conferir em Business Manager → Security Center.
4. **Data Use Checkup vencido.** Conferir em App Review → Data Use Checkup. Se está "Action Required" ou "Expired", bloqueia tudo.

### "Webhook não chega no Klivy mesmo após Verify and Save"

1. **Verify Token errado.** Comparar valor exato. Meta é case-sensitive.
2. **URL não pública.** Tentar `curl https://<host>/webhooks/instagram` de fora do servidor — deve responder algo (mesmo que 401). Se conexão recusa, é firewall/DNS.
3. **HTTPS sem certificado válido.** Meta exige cert válido (Let's Encrypt OK). Self-signed ou expirado é rejeitado.
4. **Subscrição de campos não feita.** No painel Meta: `Instagram → API Setup → Webhooks → campos subscritos`. Tem que estar verde, com pelo menos `messages` ativado.

### "Token expira antes de 60 dias / mensagens param de chegar"

1. **Refresh lazy não roda.** O Chatwoot só refresca o long-lived token quando envia mensagem ([app/services/instagram/refresh_oauth_token_service.rb](../../app/services/instagram/refresh_oauth_token_service.rb)). Se a conta nunca envia, token expira em 60 dias.
2. **Solução de longo prazo:** implementar `InstagramRefreshAllJob` agendado (1x/dia) — descrito na fase F7 do plano [docs/03-engineering/social-channels-meta-apps-per-account.md](social-channels-meta-apps-per-account.md).
3. **Solução imediata:** reconectar a inbox quando expirar (Settings → Inbox → Reauthorize).

### "Mensagens novas chegam mas Klivy não cria conversa"

Bug conhecido em algumas versões do Chatwoot relacionado ao `RuntimeError "Unsupported operation for this channel: Channel::Instagram"` — ver [chatwoot/chatwoot#11983](https://github.com/chatwoot/chatwoot/issues/11983).

Workaround: confirmar que o webhook de `messages` está ativo (não só `message_seen` e outros).

### "Logs mostram tokens vazando" (legado)

Se você ainda vê log com `user_access_token: EAAB...` ou `page_access_token: EAAB...` em `Rails.logger.debug`:
- Já corrigido em commit `1.8.0.17` (vide [CHANGELOG.md](../../CHANGELOG.md)).
- Se aparecer de novo, é regressão — abrir issue.

---

## 9. Checklist final

Quando tudo estiver funcionando, valide:

**Configuração Meta:**
- [ ] App tipo "Instagram" (não "Basic Display")
- [ ] Business Verification: concluída
- [ ] Data Use Checkup: concluído
- [ ] App Review (se modo Live): `instagram_business_basic` + `instagram_business_manage_messages` aprovadas
- [ ] App Mode: Development (com testers) OU Live (com aprovação)
- [ ] Webhook callback URL configurada e verificada
- [ ] Webhook fields subscritos: `messages` (mínimo)

**Configuração Klivy:**
- [ ] `/super_admin/app_config?config=instagram` preenchido com App ID + Secret + Verify Token + API Version
- [ ] App ID bate com o do painel Meta
- [ ] App Secret bate (sem espaços extras)
- [ ] Verify Token bate exato com o colado no painel Meta

**Validação operacional:**
- [ ] Pelo menos 1 conta IG conectada com sucesso
- [ ] DM de teste chega na inbox em <5s
- [ ] Resposta da inbox chega no Instagram do remetente
- [ ] `Channel::Instagram.last.expires_at` ~60 dias no futuro
- [ ] Logs do Easypanel não mostram tokens em texto plano

---

## 10. Referências

### Doc oficial Meta
- [Instagram API with Instagram Login — Overview](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login)
- [Business Login Guide](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login/)
- [/access_token endpoint reference](https://developers.facebook.com/docs/instagram-platform/reference/access_token/)
- [App Review process](https://developers.facebook.com/docs/app-review/)
- [Business Verification](https://www.facebook.com/business/help/2058515294227817)

### Issues e threads relevantes
- [chatwoot/chatwoot#12656](https://github.com/chatwoot/chatwoot/issues/12656) — "Failed to exchange token for non tester accounts instagram"
- [Meta Dev Community — Unsupported request long-lived token](https://developers.facebook.com/community/threads/1300473464802212/)
- [Chatwoot self-hosted docs — Instagram via Business Login](https://developers.chatwoot.com/self-hosted/configuration/features/integrations/instagram-via-instagram-business-login)

### Documentos internos Klivy
- [Plano arquitetural Meta Apps per-account](social-channels-meta-apps-per-account.md) — proposta futura caso queira app per-clínica em vez de app global
- [AGENTS.md — Multi-tenancy](../../AGENTS.md) — regras de isolamento per-account
- [CHANGELOG.md](../../CHANGELOG.md) — entrada `1.8.0.17` (hardening relacionado a Facebook/Instagram channel)

### Código relevante
- [app/controllers/concerns/instagram_concern.rb](../../app/controllers/concerns/instagram_concern.rb) — OAuth client + token exchange
- [app/controllers/instagram/callbacks_controller.rb](../../app/controllers/instagram/callbacks_controller.rb) — callback flow
- [app/controllers/webhooks/instagram_controller.rb](../../app/controllers/webhooks/instagram_controller.rb) — webhook handler
- [app/models/channel/instagram.rb](../../app/models/channel/instagram.rb) — Channel model
- [app/services/instagram/refresh_oauth_token_service.rb](../../app/services/instagram/refresh_oauth_token_service.rb) — refresh long-lived token (lazy)
- [app/jobs/webhooks/instagram_events_job.rb](../../app/jobs/webhooks/instagram_events_job.rb) — processamento de eventos

---

## Histórico de atualização

| Data | Mudança |
|---|---|
| 2026-05-26 | Versão inicial — criado após debugging do erro "Unsupported request - method type: get" reportado na clínica de teste. Diagnóstico: app em modo Development sem tester cadastrado. |
| 2026-05-26 | Adicionada seção 7 "Debug: conectei mas não recebo mensagens" com 3 verificações estruturadas (webhook configurado no painel Meta, webhook chegando no Klivy, subscribe na conta IG específica) + matriz de decisão. Criada após cenário real: OAuth concluiu mas DMs não chegavam na inbox. |
