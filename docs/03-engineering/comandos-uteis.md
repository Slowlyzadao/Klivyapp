# Comandos Úteis — Operações e Manutenção

> Comandos pontuais de manutenção, migração de dados e operações em produção.

## Onde executar os comandos

Existem **dois contextos** possíveis para rodar os comandos abaixo. A escolha do contexto muda a forma do comando:

### 1. Terminal local (WSL) — desenvolvimento

- **Onde:** terminal bash na pasta do projeto (`~/KlivyApp`)
- **Como:** comandos prefixados com `docker compose exec <serviço> ...`
- **Exemplo:** `docker compose exec rails bundle exec rails db:migrate`
- O `docker compose exec` abre uma conexão para o container do serviço (rails, database, redis, etc.).

### 2. Console do Easypanel — produção

- **Onde:** Easypanel → serviço **klivy** → **Console do Serviço** → aba **Bash**
- **Como:** você já está **dentro** do container, então **não precisa** do `docker compose exec`. Roda direto.
- **Prompt típico:** `root@<hash>:/app#`
- **Exemplo:** `bundle exec rails db:migrate`

> **Regra prática:** se o prompt do terminal mostra `/app#`, você está dentro do container — use a forma curta (sem `docker compose exec`). Se está no terminal do WSL na pasta do projeto, use a forma completa (com `docker compose exec`).

Para comandos no banco ou redis, troque `rails` pelo serviço alvo: `docker compose exec database ...` / `docker compose exec redis ...`.

---

## Migrations do Rails

### Rodar migrations pendentes (no host)

```bash
docker compose exec rails bundle exec rails db:migrate
```

### Rodar migrations dentro do container

```bash
bundle exec rails db:migrate
```

### Verificar status das migrations

```bash
bundle exec rails db:migrate:status
```

### Reverter última migration

```bash
bundle exec rails db:rollback
```

---

## Migrações de dados (Data Migrations)

### Migrar categorias antigas (custom_attributes → Agenda::Category)

Migra dados antigos de "categoria" guardados em `AgendaEvent#custom_attributes` para a entidade `Agenda::Category`. **Idempotente** — pode rodar múltiplas vezes sem efeito colateral.

**Dentro do container do rails:**

```bash
bundle exec rails runner 'Account.find_each { |acc| puts "acc=#{acc.id} #{Agenda::MigrateCategoriesFromCustomAttributes.new(acc).call}" }'
```

**A partir do host (com docker compose):**

```bash
docker compose exec rails bundle exec rails runner "Account.find_each { |acc| puts \"acc=#{acc.id} #{Agenda::MigrateCategoriesFromCustomAttributes.new(acc).call}\" }"
```

**Para testar em uma única conta antes:**

```bash
bundle exec rails runner 'acc = Account.first; puts Agenda::MigrateCategoriesFromCustomAttributes.new(acc).call'
```

**Output esperado** (uma linha por conta):

```
acc=1 {:events_scanned=>120, :categories_created=>4, :events_linked=>87}
```

- `events_scanned` — eventos sem categoria que foram avaliados
- `categories_created` — categorias novas criadas
- `events_linked` — eventos efetivamente vinculados a uma categoria

Implementação: [plugins/agenda/app/services/agenda/migrate_categories_from_custom_attributes.rb](../../plugins/agenda/app/services/agenda/migrate_categories_from_custom_attributes.rb)

---

## Backup do PostgreSQL

### Via Easypanel (recomendado para histórico)

1. Acessar o serviço `database` → **Cópias de Segurança**
2. **Criar backup do banco de dados**
3. Configurar:
   - Ativado: ON
   - Agendar: `Todos os dias às 00:00` (cron `0 0 * * *`)
   - Nome do Banco de Dados: `klivy`
   - Provedor de Armazenamento: `Local Disk` (ou S3/R2 se configurado)
   - Caminho: `klivy/database`
4. Após criar, usar o botão **"Fazer backup agora"** na lista para disparar manualmente.

### Via pg_dump direto (backup pontual rápido)

**A partir do host:**

```bash
docker compose exec database pg_dump -U postgres klivy | gzip > backup_$(date +%Y%m%d_%H%M).sql.gz
```

**Restaurar de um dump:**

```bash
gunzip -c backup_YYYYMMDD_HHMM.sql.gz | docker compose exec -T database psql -U postgres klivy
```

---

## Console do Rails

### Console interativo (no host)

```bash
docker compose exec rails bundle exec rails console
```

### Dentro do container

```bash
bundle exec rails console
```

### Console em modo sandbox (rollback automático ao sair)

```bash
bundle exec rails console --sandbox
```

---

## Rails Runner — comandos úteis

### Iterar por todas as contas

```bash
bundle exec rails runner 'Account.find_each { |acc| puts acc.id }'
```

### Executar um arquivo .rb

```bash
bundle exec rails runner script/algum_script.rb
```

### Verificar versão do Rails / Ruby

```bash
bundle exec rails --version
ruby --version
```

---

## Logs e diagnóstico

### Ver logs do rails (no host)

```bash
docker compose logs -f rails
```

### Ver logs do banco

```bash
docker compose logs -f database
```

### Status dos containers

```bash
docker compose ps
```

### Acessar shell de um serviço

```bash
docker compose exec rails bash
docker compose exec database bash
```

---

## Operações em PostgreSQL

### Acessar psql

**No host:**

```bash
docker compose exec database psql -U postgres klivy
```

**Comandos úteis dentro do psql:**

```sql
\dt                    -- Listar tabelas
\d nome_tabela         -- Descrever tabela
\du                    -- Listar usuários/roles
\l                     -- Listar databases
\q                     -- Sair
```

### Tamanho do banco

```sql
SELECT pg_size_pretty(pg_database_size('klivy'));
```

### Tabelas maiores

```sql
SELECT relname AS tabela,
       pg_size_pretty(pg_total_relation_size(relid)) AS tamanho
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 10;
```

---

## Cache / Redis

### Limpar cache do Rails

```bash
bundle exec rails runner 'Rails.cache.clear'
```

### Acessar redis-cli

```bash
docker compose exec redis redis-cli
```

---

## Active Storage / R2

> Ver documentação dedicada:
> - [Setup R2 Dev](../R2_Cloudlare_Dev.md)
> - [Setup R2 Prod](../R2_Cloudlare_Prod.md)
> - [Runbook Active Storage R2](runbook-active-storage-r2-production.md)

---

## Sidekiq / Background Jobs

### Verificar filas (no rails console)

```ruby
Sidekiq::Queue.all.map { |q| [q.name, q.size] }
Sidekiq::RetrySet.new.size
Sidekiq::DeadSet.new.size
```

### Limpar fila de retry

```ruby
Sidekiq::RetrySet.new.clear
```

---

## Notas de segurança

- **Sempre criar backup antes** de rodar data migrations em produção, mesmo que o serviço seja idempotente.
- Comandos com `update_columns` pulam validations e callbacks — confirme o impacto antes.
- Em produção, prefira testar em **uma única conta** (`Account.first` ou ID específico) antes de iterar todas.
- O volume `/app/storage` no Easypanel **não pode ser removido** — guarda credenciais Baileys do bridge WhatsApp.
