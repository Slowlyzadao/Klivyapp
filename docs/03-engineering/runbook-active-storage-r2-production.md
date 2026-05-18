# 📘 Runbook: Ativar R2 em Produção (Easypanel)

**Data:** 2026-04-27
**Escopo:** ligar o switch do Active Storage em produção para usar Cloudflare R2 em vez do filesystem efêmero.
**Pré-requisito:** PR #1 (`feat(storage): migrate Active Storage from Disk to Cloudflare R2`) já mergeado em `main` (commit `ade5ed05`).
**Tempo estimado:** ~30 minutos (sem incluir tempo de deploy).
**Reversível?** Sim em qualquer ponto antes da Etapa 6. Após Etapa 6 (purge), os registros órfãos são apagados de forma irreversível.

> **Como ler este runbook:** cada etapa tem (a) o que fazer, (b) onde fazer (Cloudflare/Easypanel/CLI), (c) como validar, (d) como reverter. Siga em ordem — não pule etapas.

---

## ⚠️ Antes de começar

- [ ] Confirmar que `main` local está em `ade5ed05` ou mais novo: `git log --oneline -1`
- [ ] Confirmar que o smoke test em **localhost** já foi validado contra `klivy-storage-dev` (upload, listing no R2 dashboard, render via UI)
- [ ] Ter acesso admin a:
  - Cloudflare Dashboard (account `8f43f78998e85b147a3a3502dfe18c7f`)
  - Easypanel Dashboard (waha-chatwoot.efqhwo.easypanel.host)

---

## Etapa 1 — Criar bucket de produção no R2

**Onde:** Cloudflare Dashboard

1. Menu lateral esquerdo → **R2 Object Storage**
2. Botão **Create bucket** (canto superior direito)
3. Preencher:

   | Campo | Valor |
   |---|---|
   | **Bucket name** | `klivy-storage` |
   | **Location** | Automatic |
   | **Default Storage Class** | Standard |

4. **Create bucket**

**Validação:** o bucket aparece na lista da página R2 com tamanho `0 B` e zero objetos.

**Reverter:** Settings do bucket → Excluir bucket. (Vazio, sem risco.)

---

## Etapa 2 — Configurar CORS no bucket prod

**Onde:** Cloudflare Dashboard → R2 → bucket `klivy-storage`

1. Aba **Settings**
2. Seção **CORS Policy** → **Add CORS policy**
3. Colar:

```json
[
  {
    "AllowedOrigins": ["https://sistema.klivy.app"],
    "AllowedMethods": ["GET", "PUT", "POST", "HEAD"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag", "Content-Length", "Content-Type"],
    "MaxAgeSeconds": 3600
  }
]
```

4. **Salvar**

**Por que PUT/POST/HEAD além de GET?** Por padrão, Active Storage server-side só precisa de GET (o Rails proxia o upload). Mas se um dia ativar `DIRECT_UPLOADS_ENABLED=true` (browser sobe direto pro R2), os outros métodos já estarão liberados — evita rebumbo depois.

**Validação:** policy aparece listada.

**Reverter:** botão delete na policy. Sem risco.

---

## Etapa 3 — Criar token R2 de produção

**Onde:** Cloudflare Dashboard → R2 Object Storage → menu superior **Manage R2 API Tokens**

⚠️ **Importante:** este é o caminho R2-específico. **Não** use "My Profile → API Tokens" (gera token Bearer `cfut_...` que não funciona com S3).

1. Botão **Create API token** → **Account API token** (recomendado para produção; User token morre se você sair da org)
2. Preencher:

   | Campo | Valor |
   |---|---|
   | **Token name** | `klivy-r2-prod` |
   | **Permissions** | **Object Read & Write** (não Admin) |
   | **Specify bucket(s)** | **Apply only to specific buckets** → selecionar **`klivy-storage`** apenas |
   | **TTL** | em branco (Sempre) |

3. **Create API Token**
4. A tela seguinte mostra **uma única vez** três valores — copiar **agora** para `docs/R2_Cloudlare_Prod.md` (gitignored):
   - **Access Key ID** (32 hex chars)
   - **Secret Access Key** (longo)
   - **Endpoint** (já conhecido: `https://8f43f78998e85b147a3a3502dfe18c7f.r2.cloudflarestorage.com`)

**Princípio de menor privilégio:** este token só pode ler/escrever objetos no `klivy-storage`. Se vazar, o blast radius está contido — não pode criar/deletar buckets nem tocar em outros buckets.

**Validação:** o token aparece em **R2 API Tokens** com status **Active**, escopo `klivy-storage`.

**Reverter:** menu `...` ao lado do token → **Roll** (gera novo par, invalida o antigo) ou **Delete**.

---

## Etapa 4 — Configurar 7 ENVs no Easypanel

**Onde:** Easypanel Dashboard → projeto KlivyApp

⚠️ **Crítico:** repita as 7 ENVs **no service `rails` E no service `sidekiq`** separadamente. Sidekiq processa variants/previews de imagem — se ele apontar para storage diferente do web, thumbnails somem ou ficam órfãs.

### 4.1 — Service `rails`

1. Service **rails** → aba **Environment** (ou **Env Vars**)
2. Adicionar/editar as 7 entradas:

   ```
   ACTIVE_STORAGE_SERVICE=s3_compatible
   STORAGE_ACCESS_KEY_ID=<da Etapa 3>
   STORAGE_SECRET_ACCESS_KEY=<da Etapa 3>
   STORAGE_REGION=auto
   STORAGE_BUCKET_NAME=klivy-storage
   STORAGE_ENDPOINT=https://8f43f78998e85b147a3a3502dfe18c7f.r2.cloudflarestorage.com
   STORAGE_FORCE_PATH_STYLE=true
   ```

3. **Save** — Easypanel pode pedir confirmação para restartar o container. **Aceitar.**

### 4.2 — Service `sidekiq`

Repetir **exatamente** as mesmas 7 ENVs no service `sidekiq`. Mesmos valores.

**Validação:** ambos os services listam as 7 ENVs em sua aba de Environment, com `ACTIVE_STORAGE_SERVICE=s3_compatible`.

**Reverter:** mudar `ACTIVE_STORAGE_SERVICE` de volta para `local` em ambos services e restartar. Volta ao Disk efêmero (com problema antigo, mas operacional).

---

## Etapa 5 — Forçar redeploy

**Onde:** Easypanel Dashboard

Se Easypanel está com auto-deploy ativo no `main`, o deploy do commit `ade5ed05` já pode ter rodado quando o PR foi mergeado. Mesmo assim, **forçar um redeploy** depois de configurar as ENVs garante que os processos já subam com elas:

1. Service **rails** → aba **Deployments** → botão **Deploy**
2. Service **sidekiq** → mesma coisa

Aguardar status verde (Running) em ambos. Tipicamente 2–5 minutos.

**Validação:** logs do service rails (aba Logs) mostram boot do Rails sem erros, e a primeira request HTTP responde (curl `https://sistema.klivy.app/` deve retornar 200 ou 302).

**Reverter:** Easypanel → Deployments → encontrar o deploy anterior → **Rollback**.

---

## Etapa 6 — Smoke test em produção (CRÍTICO)

**Onde:** browser + Easypanel container shell

### 6.1 — Validação via Rails runner

1. Easypanel → service **rails** → aba **Console** (ou **Shell**)
2. Colar:

```bash
bundle exec rails runner - <<'RUBY'
puts "Service: #{ActiveStorage::Blob.service.class.name}"
puts "Bucket:  #{ActiveStorage::Blob.service.bucket.name}"

blob = ActiveStorage::Blob.create_and_upload!(
  io: StringIO.new("prod smoke test #{Time.current}"),
  filename: "prod_smoke.txt",
  content_type: "text/plain"
)
puts "URL:     #{blob.url(expires_in: 30.minutes)}"
puts "Blob ID: #{blob.id}"
RUBY
```

**Saída esperada:**
```
Service: ActiveStorage::Service::S3Service
Bucket:  klivy-storage
URL:     https://8f43f78998e85b147a3a3502dfe18c7f.r2.cloudflarestorage.com/klivy-storage/...
Blob ID: <número>
```

3. Abrir a URL retornada no browser → deve baixar/exibir "prod smoke test ...".
4. Cloudflare Dashboard → R2 → `klivy-storage` → conferir que o objeto apareceu.

### 6.2 — Validação via UI

1. Login em `https://sistema.klivy.app`
2. Pacientes → criar um paciente de teste → upload de avatar (PNG pequeno).
3. F5 → avatar persiste.
4. F12 → Network: clique numa imagem → request `/rails/active_storage/blobs/redirect/...` deve responder **302** com `Location: https://...r2.cloudflarestorage.com/klivy-storage/...`
5. Cloudflare Dashboard → R2 → `klivy-storage` → conferir objeto novo.

### 6.3 — Limpar o blob de smoke test

```bash
bundle exec rails runner "ActiveStorage::Blob.where(content_type: 'text/plain', filename: 'prod_smoke.txt').destroy_all; puts 'cleaned'"
```

**Diagnósticos comuns:**

| Erro | Causa provável | Fix |
|---|---|---|
| `501 NotImplemented (x-amz-acl)` | Initializer `aws_sdk_r2_compat` não rodou | Conferir `ACTIVE_STORAGE_SERVICE=s3_compatible` foi setado **antes** do deploy |
| `403 InvalidAccessKeyId` | Token errado ou expirado | Recriar token escopado em Etapa 3 |
| `NoSuchBucket` | `STORAGE_BUCKET_NAME` divergente | Conferir spelling exato `klivy-storage` |
| Avatar quebra após F5 | Thumbnails: sidekiq não tem ENVs | Conferir Etapa 4.2 |

**Reverter:** se algo falhar, mudar `ACTIVE_STORAGE_SERVICE=local` no Easypanel + redeploy. Volta ao Disk efêmero (com problema, mas operacional). Não rodar Etapa 7.

---

## Etapa 7 — Purgar blobs órfãos do Disk antigo (NÃO REVERSÍVEL)

⚠️ **Só executar se Etapa 6 passou inteira e você está confortável.** Esta etapa apaga registros do banco que apontam para arquivos que já não existem (legado do `service: Disk` no container efêmero).

**Onde:** Easypanel → service rails → Console

> **Lição aprendida (validado em dev em 2026-04-27):** `purge_later` **não funciona** para esses órfãos. O job `ActiveStorage::PurgeJob` tenta deletar o arquivo físico do Disk → arquivo não existe → `Errno::ENOENT` → job falha → record não é destruído. Os 68 órfãos permaneceram no DB mesmo após enfileirar `purge_later` neles.
>
> O caminho correto é **force destroy direto** — pula a tentativa de deletar arquivo e mata só as rows do DB:

```bash
bundle exec rails runner - <<'RUBY'
orphans = ActiveStorage::Blob.where(service_name: ['local', nil])
puts "Órfãos do Disk antigo: #{orphans.count} (#{(orphans.sum(:byte_size)/1024.0/1024).round(2)} MB)"

if orphans.any?
  puts "Force-destroying records (arquivos físicos do Disk antigo já não existem)..."
  count = 0
  orphans.find_each do |blob|
    ActiveStorage::Attachment.where(blob_id: blob.id).destroy_all
    blob.destroy
    count += 1
  end
  puts "Destruídos: #{count} blobs + attachments associados"
end

puts ""
puts "=== Estado final ==="
ActiveStorage::Blob.group(:service_name).count.each do |svc, n|
  size_mb = (ActiveStorage::Blob.where(service_name: svc).sum(:byte_size) / 1024.0 / 1024).round(2)
  puts "  service=#{(svc || 'nil').to_s.ljust(20)} #{n.to_s.rjust(4)} blobs  #{size_mb} MB"
end
puts "Total: #{ActiveStorage::Blob.count} blobs"
RUBY
```

Esperado após executar: a linha `service=local` desaparece, restam apenas blobs `service=s3_compatible` que correspondem a arquivos reais no R2.

**Validação:**
1. Acompanhar Sidekiq (Easypanel → service sidekiq → Logs) — vai processar `ActiveStorage::PurgeJob`.
2. Após processar, repetir o conta:
   ```bash
   bundle exec rails runner "puts ActiveStorage::Blob.where(service_name: ['local', nil]).count"
   ```
   Deve retornar `0`.
3. Recarregar páginas que antes tinham avatar quebrado / 404 — agora exibem fallback (não tentam URL morta).

**Reverter:** **não há reversão direta.** Os registros foram apagados. Mas como os arquivos físicos já não existiam, o "estado restaurado" seria o mesmo — só com row morta no banco.

---

## Etapa 8 — Limpeza opcional pós-cutover

Após 1–2 semanas estável em prod com R2:

1. **Easypanel:** remover o volume `storage_data` antigo (se foi criado um dia) — Service rails → Volumes/Mounts → delete `/app/storage`.
2. **Cloudflare:** revisar uso do bucket no dashboard (Métrica) — confirmar custo está dentro do esperado (<$5/mês para os primeiros meses).
3. **Token rotation:** marcar no calendário rotacionar `klivy-r2-prod` a cada 6 meses (Cloudflare → R2 API Tokens → ... → Roll).

---

## ✅ Checklist final

Marcar conforme avança:

- [ ] **Etapa 1:** bucket `klivy-storage` criado
- [ ] **Etapa 2:** CORS configurado
- [ ] **Etapa 3:** token `klivy-r2-prod` criado, credentials salvas em `docs/R2_Cloudlare_Prod.md`
- [ ] **Etapa 4.1:** 7 ENVs no service `rails`
- [ ] **Etapa 4.2:** 7 ENVs no service `sidekiq`
- [ ] **Etapa 5:** redeploy disparado, ambos services em "Running"
- [ ] **Etapa 6.1:** rails runner smoke test passou
- [ ] **Etapa 6.2:** UI smoke test passou (upload + F5 + 302 redirect)
- [ ] **Etapa 6.3:** blob de teste purgado
- [ ] **Etapa 7:** blobs órfãos purgados (irreversível)
- [ ] **Etapa 8:** limpeza opcional agendada

---

## 📞 Em caso de problema

1. **Reverter rapidamente:** Easypanel → ambos services → mudar `ACTIVE_STORAGE_SERVICE=local` → redeploy. Sistema volta ao estado anterior em ~2 min.
2. **Diagnóstico:** logs do service rails no Easypanel + smoke test §6.1 isolado.
3. **Documentação base:** [implementation-plan-active-storage-r2.md](implementation-plan-active-storage-r2.md) tem o plano completo da migração com todos os "porquês".

---

## 📎 Referências

- Plano de implementação completo: [implementation-plan-active-storage-r2.md](implementation-plan-active-storage-r2.md)
- Auditoria do módulo Exames e Imagens (afetado): [audit-exames-imagens.md](audit-exames-imagens.md)
- Cloudflare R2 S3 API: https://developers.cloudflare.com/r2/api/s3/api/
- Active Storage S3 service: https://api.rubyonrails.org/classes/ActiveStorage/Service/S3Service.html
