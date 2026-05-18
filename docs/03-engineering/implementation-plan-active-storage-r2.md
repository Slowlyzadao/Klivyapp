# 🛠️ Plano de Implementação: Active Storage → Cloudflare R2

**Data:** 2026-04-27
**Escopo:** migrar Active Storage de `Disk` (filesystem do container) para `S3` apontando para Cloudflare R2.
**Status:** plano aprovado — cutover limpo, sem migração de blobs (cliente ainda não enviou arquivos reais).
**Contexto:** o container do Easypanel tem filesystem efêmero. Cada redeploy/restart apaga `/app/storage`, deixando registros `ActiveStorage::Blob` órfãos no banco e gerando 404 em avatars, exames e anexos. Diagnóstico completo no resumo abaixo; auditoria detalhada em [audit-exames-imagens.md](audit-exames-imagens.md).

---

## ⚠️ Resumo executivo

A causa raiz é a combinação de três coisas, todas no nível de configuração — **nenhuma mudança de código de aplicação é necessária**:

1. [config/environments/production.rb:43](../../config/environments/production.rb#L43) lê `ENV['ACTIVE_STORAGE_SERVICE']` com fallback `local`.
2. [.env](../../.env) hoje tem `ACTIVE_STORAGE_SERVICE=local`.
3. [config/storage.yml:5-7](../../config/storage.yml#L5-L7) define `local` como `service: Disk` em `Rails.root.join("storage")` → `/app/storage` no container.

Easypanel não monta volume nesse caminho, então tudo se perde no próximo deploy.

A solução é trocar a ENV para `s3_compatible` (já existe em [config/storage.yml:32-39](../../config/storage.yml#L32-L39)) e apontar para R2. Como **não há migração de dados** a fazer, o cutover é uma única operação atômica de redeploy.

---

## 1. Pré-requisitos

### 1.1 Bucket R2

Já criado: `klivy-storage` (account `8f43f78998e85b147a3a3502dfe18c7f`).

### 1.2 Credenciais R2 — ⚠️ ATENÇÃO

O token salvo em `docs/R2_Cloudlare_info.md` (`cfut_...`) é um **Cloudflare User API Token**, usado para gerenciar a conta via API REST do Cloudflare. **Não serve para Active Storage.**

O Active Storage usa o protocolo S3 e exige um par **Access Key ID + Secret Access Key** específicos do R2. Como gerar:

1. Cloudflare Dashboard → **R2** → **Manage R2 API Tokens** → **Create API token**.
2. Permissions: **Object Read & Write**.
3. Specify bucket: `klivy-storage` (escopar — não dar acesso global à conta).
4. TTL: nenhum (token permanente; rotacionar manualmente a cada 6 meses).
5. Copiar **Access Key ID** e **Secret Access Key** (mostrados uma única vez).

### 1.3 Rotacionar token vazado

O arquivo [docs/R2_Cloudlare_info.md](../R2_Cloudlare_info.md) está **untracked** (ainda não commitado), mas o token `cfut_...` já apareceu em conversa. Antes de qualquer deploy:

1. Cloudflare Dashboard → **My Profile** → **API Tokens** → revogar o `cfut_vlqzO1UPLOZ...`.
2. Adicionar `docs/R2_Cloudlare_info.md` ao `.gitignore` (ou apagar — credenciais ficam só no Easypanel).

### 1.4 CORS no bucket

Necessário para `direct_uploads` (frontend faz `PUT` direto para R2) e para qualquer fetch via JS que precise ler headers (`ETag`).

Cloudflare Dashboard → R2 → bucket `klivy-storage` → **Settings** → **CORS Policy** → **Add CORS policy**:

```json
[
  {
    "AllowedOrigins": [
      "https://sistema.klivy.app"
    ],
    "AllowedMethods": ["GET", "PUT", "POST", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag", "Content-Length", "Content-Type"],
    "MaxAgeSeconds": 3600
  }
]
```

Se houver ambiente de staging (`staging.klivy.app`), incluir na lista. Para dev local com Vite, adicionar `http://localhost:3036` e `http://localhost:3000` em um bucket separado `klivy-storage-dev` — não misturar dev e prod no mesmo bucket.

---

## 2. Mudanças no repositório

### 2.1 Initializer para corrigir quirk de checksum (obrigatório)

A `aws-sdk-s3` 1.178+ envia headers de checksum (`x-amz-sdk-checksum-algorithm`, `x-amz-checksum-crc32`) que R2 rejeita com `501 NotImplemented`. Estamos em [Gemfile.lock:156](../../Gemfile.lock#L156) com **1.208.0**, então o problema vai aparecer.

Criar [config/initializers/aws_sdk_r2_compat.rb](../../config/initializers/aws_sdk_r2_compat.rb):

```ruby
# Cloudflare R2 ainda não implementa o protocolo de checksum CRC32 introduzido
# pela aws-sdk-s3 ≥ 1.178. Sem isso, todo PUT volta 501 NotImplemented.
# Removível quando R2 anunciar suporte completo a flexible checksums.
if ENV['ACTIVE_STORAGE_SERVICE'] == 's3_compatible'
  Aws.config.update(
    request_checksum_calculation: 'when_required',
    response_checksum_validation: 'when_required'
  )
end
```

### 2.2 Ajuste em `config/storage.yml`

A entrada `s3_compatible` em [config/storage.yml:32-39](../../config/storage.yml#L32-L39) está quase pronta. Adicionar a chave `upload` para neutralizar ACL (R2 não suporta ACLs estilo S3) e fixar `region: auto`:

```yaml
s3_compatible:
  service: S3
  access_key_id: <%= ENV.fetch('STORAGE_ACCESS_KEY_ID', '') %>
  secret_access_key: <%= ENV.fetch('STORAGE_SECRET_ACCESS_KEY', '') %>
  region: <%= ENV.fetch('STORAGE_REGION', 'auto') %>
  bucket: <%= ENV.fetch('STORAGE_BUCKET_NAME', '') %>
  endpoint: <%= ENV.fetch('STORAGE_ENDPOINT', '') %>
  force_path_style: <%= ENV.fetch('STORAGE_FORCE_PATH_STYLE', true) %>
  upload:
    acl: ""
```

Nota: mantemos `ENV.fetch` para os valores sensíveis — config nunca commitada.

### 2.3 Expiração de signed URLs (curativo + segurança)

Hoje [plugins/patients/app/models/exam_media.rb:68](../../plugins/patients/app/models/exam_media.rb#L68) usa `expires_in: 15.minutes`, o que quebra galerias revisitadas (M2 da auditoria de exames). Como Klivy lida com PHI, **não** podemos expirar tudo em horas. Compromisso:

Criar [config/initializers/active_storage.rb](../../config/initializers/active_storage.rb):

```ruby
# Signed URLs do Active Storage. PHI: prazo curto, mas longo o bastante
# pra que galerias e lightboxes não quebrem em uso normal.
Rails.application.config.active_storage.urls_expire_in = 1.hour
```

Para vídeos longos (>30 min) considerar gerar URL específica com `expires_in: 2.hours` no momento do play — fica fora deste plano, abrir issue separada.

### 2.4 `.env.example` — documentar as novas chaves

Adicionar bloco em [.env.example](../../.env.example), abaixo do bloco `Storage` existente:

```bash
# Cloudflare R2 (S3-compatible) — produção usa esta config
# ACTIVE_STORAGE_SERVICE=s3_compatible
# STORAGE_ACCESS_KEY_ID=<gerado em Cloudflare Dashboard → R2 → Manage R2 API Tokens>
# STORAGE_SECRET_ACCESS_KEY=
# STORAGE_REGION=auto
# STORAGE_BUCKET_NAME=klivy-storage
# STORAGE_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
# STORAGE_FORCE_PATH_STYLE=true
```

Não preencher valores reais — apenas o template comentado.

### 2.5 `.gitignore` — proteger arquivo de notas

Adicionar ao final do [.gitignore](../../.gitignore):

```
# Notas locais com credenciais — nunca commitar
docs/R2_Cloudlare_info.md
docs/**/credentials*.md
```

---

## 3. ENVs no Easypanel (produção)

Easypanel → Service `rails` (e `sidekiq`, se separado) → **Environment** → adicionar:

```
ACTIVE_STORAGE_SERVICE=s3_compatible
STORAGE_ACCESS_KEY_ID=<R2 access key id>
STORAGE_SECRET_ACCESS_KEY=<R2 secret>
STORAGE_REGION=auto
STORAGE_BUCKET_NAME=klivy-storage
STORAGE_ENDPOINT=https://8f43f78998e85b147a3a3502dfe18c7f.r2.cloudflarestorage.com
STORAGE_FORCE_PATH_STYLE=true
```

**Importante:**
- Aplicar nas **duas** services (`rails` + `sidekiq`). Sidekiq processa variants/previews — se ele apontar pra outro service que o web, variants somem.
- Remover o volume `storage_data` antigo do Easypanel **só depois** que o smoke test (passo 5) passar. Mantém como fallback durante a janela.

---

## 4. Roteiro de execução (ordem importa)

| # | Etapa | Onde | Reversível? |
|---|-------|------|-------------|
| 1 | Gerar R2 API token (Access Key + Secret) | Cloudflare Dashboard | sim (revogar token) |
| 2 | Configurar CORS no bucket | Cloudflare Dashboard | sim |
| 3 | Revogar token `cfut_...` vazado | Cloudflare Dashboard | n/a |
| 4 | Criar branch `feat/active-storage-r2` | local | sim |
| 5 | Aplicar mudanças §2.1 a §2.5 | repo | sim (revert) |
| 6 | Adicionar entrada no `CHANGELOG.md` (§7) | repo | sim |
| 7 | Abrir PR, revisar, mergear | GitHub | sim |
| 8 | Setar ENVs no Easypanel (§3) — **antes** do deploy | Easypanel | sim |
| 9 | Disparar deploy do branch mergeado | Easypanel | sim (rollback do deploy anterior) |
| 10 | Smoke test (§5) | produção | n/a |
| 11 | Limpar registros órfãos no DB (§6) | rails console prod | **não** |
| 12 | Remover volume `storage_data` antigo | Easypanel | sim |

---

## 5. Smoke test pós-deploy

Executar **na ordem** logo após o deploy. Se qualquer passo falhar, executar rollback (§8) antes de investigar.

### 5.1 Rails console — sanity de configuração

```ruby
# bundle exec rails console RAILS_ENV=production
ActiveStorage::Blob.service.class
# => ActiveStorage::Service::S3Service ✅
ActiveStorage::Blob.service.bucket.name
# => "klivy-storage" ✅
```

### 5.2 Upload programático

```ruby
blob = ActiveStorage::Blob.create_and_upload!(
  io: StringIO.new("smoke test #{Time.current}"),
  filename: "smoke.txt",
  content_type: "text/plain"
)
puts blob.url(expires_in: 5.minutes)
# Abrir URL no browser → deve baixar "smoke test ..."
blob.purge  # limpa o objeto e o registro
```

Se retornar 501/NotImplemented → confirmar §2.1 foi aplicado.
Se retornar 403 → revisar CORS e permissões do token.
Se retornar 404 no bucket name → endpoint errado (verificar account ID).

### 5.3 Fluxo end-to-end via UI

1. Login em `sistema.klivy.app`.
2. Pacientes → criar paciente novo → fazer upload de avatar (PNG pequeno).
3. Conferir no Network tab: o GET do avatar deve ser **302 redirect** para `*.r2.cloudflarestorage.com` (não mais `/rails/active_storage/disk/...`).
4. Aba **Exames e Imagens** → upload de imagem JPG, PDF e vídeo MP4 pequeno.
5. F5 na página → arquivos continuam acessíveis.
6. Force restart no Easypanel → F5 → arquivos **continuam acessíveis** (este é o teste real).

### 5.4 Sidekiq — variants

Se o paciente tem avatar com variants/previews, abrir o registro e conferir que a thumbnail renderiza. Variants são geradas pelo Sidekiq — falha aqui = ENVs não foram aplicadas no service `sidekiq`.

---

## 6. Limpeza de registros órfãos (uma única vez)

Como o Disk antigo perdeu os blobs mas o DB ainda tem `ActiveStorage::Blob` + `ActiveStorage::Attachment` apontando pra eles, qualquer tentativa de carregar esses registros vai dar 404 mesmo depois do R2 estar online.

```ruby
# bundle exec rails console RAILS_ENV=production
# CUIDADO: rodar SOMENTE depois do smoke test §5 passar.
orphans = ActiveStorage::Blob.where(service_name: ['local', nil])
puts "Blobs órfãos encontrados: #{orphans.count}"
orphans.find_each(&:purge_later)  # purga via Sidekiq, não bloqueia o console
```

`purge_later` remove o `Blob`, todos os `Attachment` associados e tenta apagar o objeto remoto (que já não existe — falha silenciosamente). Após isso, o sintoma "avatar quebrado / 404" desaparece para sempre.

---

## 7. CHANGELOG.md (obrigatório por AGENTS.md)

Adicionar entrada no topo, abaixo do bloco "Estrutura de Versão":

```markdown
## [1.5.0.11] - 2026-04-27T<HH:MM>:00-03:00

### Active Storage: migrar de Disk (efêmero) para Cloudflare R2

**Problema:**
Em produção (Easypanel), o container roda sem volume persistente em `/app/storage`. Active Storage usa `service: Disk`, então qualquer redeploy ou restart apaga avatares, exames e anexos. Banco mantém os registros `ActiveStorage::Blob`, mas as URLs `/rails/active_storage/disk/...` retornam 404.

**Solução:**
1. Trocar `ACTIVE_STORAGE_SERVICE=local` por `s3_compatible` apontando para Cloudflare R2 (bucket `klivy-storage`).
2. Adicionar `config/initializers/aws_sdk_r2_compat.rb` para neutralizar headers de checksum CRC32 que R2 ainda não suporta (incompatíveis com `aws-sdk-s3 ≥ 1.178`).
3. Ajustar `config/storage.yml` `s3_compatible` com `region: auto`, `force_path_style: true` e `upload.acl: ""` (R2 não suporta ACLs).
4. Definir `urls_expire_in = 1.hour` em initializer para evitar 404 em galerias revisitadas mantendo prazo curto compatível com PHI.
5. Documentar variáveis em `.env.example` e gitignorar `docs/R2_Cloudlare_info.md`.
6. Purgar registros órfãos via `ActiveStorage::Blob.where(service_name: 'local').find_each(&:purge_later)` no console pós-deploy.

**Arquivos Modificados:**
- `config/initializers/aws_sdk_r2_compat.rb` (novo)
- `config/initializers/active_storage.rb` (novo)
- `config/storage.yml`
- `.env.example`
- `.gitignore`
- `docs/03-engineering/implementation-plan-active-storage-r2.md` (novo)
- `CHANGELOG.md`
```

(Versão `1.5.0.11` assume que a próxima livre é essa — confirmar contra o `CHANGELOG.md` no momento do commit; se já houver `1.5.0.11`, usar `1.5.0.12`.)

---

## 8. Plano de rollback

Se o smoke test falhar e não for possível diagnosticar em <15 min:

1. Easypanel → Service `rails` → Environment → trocar `ACTIVE_STORAGE_SERVICE` de volta para `local`.
2. Easypanel → Deploys → **Rollback** para o release anterior (mantém `Disk` ativo).
3. Volume `storage_data` antigo continua montado nesta janela — uploads voltam a funcionar imediatamente (com o mesmo problema de efemeridade, mas operacional).
4. **Não rodar** o passo §6 (purge de órfãos) durante a janela de rollback.

Ponto de não-retorno é o §6 (purge): depois disso, mesmo voltando para `Disk`, os registros antigos não voltam.

---

## 9. Custo estimado

R2 hoje (2026):
- Storage: **$0.015 / GB / mês**.
- Class A operations (PUT/POST/LIST): $4.50 / milhão.
- Class B operations (GET/HEAD): $0.36 / milhão.
- **Egress: $0** (esse é o ponto-chave para vídeos médicos).

Projeção Klivy primeiros 6 meses (estimativa conservadora):
- 100 pacientes × 50 MB médio (exames + imagens + vídeos curtos) = ~5 GB → **$0.08/mês**.
- 50k operações/mês (uploads + reads) = ~$0.05/mês.
- **Total: <$1/mês** durante MVP.

Mesmo escalando 100×: $10–15/mês até passar de 1 TB.

---

## 10. Riscos & mitigações

| Risco | Probabilidade | Mitigação |
|-------|---------------|-----------|
| R2 retorna 501 nos PUTs (checksum quirk) | **alta** sem o initializer §2.1 | Initializer já incluído no plano; smoke test §5.2 detecta no minuto 1 |
| ENVs aplicadas só no `rails` e não no `sidekiq` | média | Checklist §3 explícito; smoke test §5.4 detecta |
| CORS faltando → uploads do frontend falham | média | §1.4 com configuração pronta; smoke test §5.3 passo 4 detecta |
| Token R2 com escopo errado (account-wide em vez de bucket-only) | baixa | §1.2 passo 3 instrui a escopar; auditável depois |
| Variants antigas (do Disk) referenciadas por views | baixa | §6 purga junto com o blob pai |
| Token vazado em `docs/R2_Cloudlare_info.md` ser reutilizado | baixa após §1.3 | Revogar antes do deploy é passo 3 do roteiro |

---

## 11. Fora de escopo (próximas iterações)

- **Direct uploads (frontend → R2 direto):** [.env](../../.env) tem `DIRECT_UPLOADS_ENABLED=` vazio. Ativar reduz carga do Rails para vídeos grandes. Requer ajuste em `app/javascript/shared/helpers/AudioRecorderHelper.js` e similares — abrir issue separada.
- **CDN com domínio próprio (`assets.klivy.app`):** vincular bucket R2 a custom domain Cloudflare para servir via CDN edge. Vale quando passarmos de ~50 GB ou tivermos usuários geograficamente distribuídos.
- **Lifecycle rules no bucket:** mover blobs com mais de 2 anos para R2 Infrequent Access (custo menor). Esperar até ter ≥10 GB.
- **Mirror service para DR:** configurar `service: Mirror` com primary R2 + mirror em outro provider (Backblaze B2) para resiliência multi-cloud. Avaliar quando a base superar 100 GB.
