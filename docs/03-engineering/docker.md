# 🐳 Guia de Comandos Docker — KlivyApp

> Todos os comandos devem ser executados no terminal WSL, na pasta do projeto:
> `~/KlivyApp`

---

## 🚀 Primeira vez (build completo)

```bash
# 1. Construir a imagem base (só se nunca fez ou limpou tudo)
docker build -t chatwoot:development -f docker/Dockerfile .

# 2. Subir tudo com rebuild
docker compose up --build
```

---

## 📅 Dia a dia

### Iniciar o ambiente
```bash
docker compose up
```

### Parar (mantém containers, retoma instantâneo)
```bash
docker compose stop
```

### Retomar após `stop`
```bash
docker compose start
```

### Derrubar containers (volumes/dados ficam intactos)
```bash
docker compose down
```

---

## 🔍 Monitorar logs

```bash
# Ver todos os logs
docker compose logs -f

# Ver só o Rails
docker compose logs -f rails

# Ver só o Vite
docker compose logs -f vite
```

---

## 🌐 URLs de acesso

| Serviço     | URL                      |
|-------------|--------------------------|
| App (Rails) | http://localhost:3000     |
| Vite (HMR)  | http://localhost:3036     |
| MailHog     | http://localhost:8025     |
| WhatsApp    | http://localhost:3002     |

---

## 🏗️ Produção (Build & Push)

> Deploy atual: **EasyPanel** puxando imagem privada `mamedes/klivy-prod` do Docker Hub.
> A imagem é buildada localmente no WSL, pushada pro Docker Hub, e o EasyPanel redeploya.

### 1. Build para Produção (AMD64)

```bash
# Substitua vX.X.X.X pela próxima versão (CHANGELOG)
# --cache-from usa a última versão publicada para acelerar o build
docker build \
  --platform linux/amd64 \
  --cache-from mamedes/klivy-prod:v1.4.4.44 \
  -t mamedes/klivy-prod:vX.X.X.X \
  .
```

> **Observação:** o `--platform linux/amd64` é obrigatório se buildar de um Mac Apple Silicon.
> No Windows/Linux x86 não muda nada mas deixar não atrapalha.

### 2. Enviar para o Docker Hub

```bash
docker push mamedes/klivy-prod:vX.X.X.X
```

### 3. Verificar que a imagem subiu íntegra

Antes de implantar, valida que a imagem tem os scripts de `bin/` executáveis
(esse problema nos mordeu no deploy v1.4.4.43 — ver seção de Troubleshooting):

```bash
docker pull mamedes/klivy-prod:vX.X.X.X
docker run --rm mamedes/klivy-prod:vX.X.X.X ls -la /app/bin/rails
```

Saída esperada: `-rwxr-xr-x 1 root root ... /app/bin/rails`.
Se vier `-rw-r--r--` (sem `+x`), **não implante** — abra issue e investigue o Dockerfile.

### 4. Atualizar tag no EasyPanel

1. Serviço **klivy** → **Fonte**
2. Troca o campo **Imagem** para `mamedes/klivy-prod:vX.X.X.X`
3. **Salvar**
4. Volta na visão principal → **Implantar**
5. Acompanha **Implantações** → **Visualizar** no deploy em andamento até aparecer `Success`
6. Abre logs de runtime do serviço `klivy` — deve ver `Listening on http://0.0.0.0:3000`

### 5. (Opcional) Atualizar tag `latest`

Só fazer se você quer que `:latest` reflita a última versão estável.
O EasyPanel está pinado em tag versionada, então isso é mais pra conveniência local.

```bash
docker tag mamedes/klivy-prod:vX.X.X.X mamedes/klivy-prod:latest
docker push mamedes/klivy-prod:latest
```

---

## 🔧 Troubleshooting de deploy

### `sh: bin/rails: Permission denied` (exit code 126)

O `COPY . /app` no Docker Desktop + WSL2 às vezes descarta o bit `+x` dos scripts do `bin/`.
**Já resolvido no Dockerfile** com `RUN chmod +x /app/bin/*` logo após o `COPY . /app`.

Se voltar a aparecer, confere que esse `RUN chmod` ainda existe no [Dockerfile](../../Dockerfile)
entre o `COPY . /app` e o `RUN ... assets:precompile`.

### `YAML syntax error` no `config/database.yml`

Causa comum: indentação inconsistente (linha com 3 espaços em um bloco de 2 espaços).
O Rails reporta "Tabs are not allowed" mesmo quando o problema não é tab —
é uma mensagem genérica para qualquer `Psych::SyntaxError`.

### Banco "database" does not exist / senha errada

Variáveis de ambiente do `.env` precisam bater com as credenciais reais do serviço `database` no EasyPanel:

| .env                 | Vem de (EasyPanel → database → Credenciais) |
|----------------------|---------------------------------------------|
| `POSTGRES_HOST`      | Host Interno (ex: `klivy_database`)         |
| `POSTGRES_DATABASE`  | Nome do Banco de Dados                      |
| `POSTGRES_USERNAME`  | Usuário                                     |
| `POSTGRES_PASSWORD`  | Senha (atualiza sempre que o EasyPanel rotacionar) |

### `REDIS_URL` com caracteres especiais na senha

Caracteres `/`, `&`, `#`, `=`, `@`, `:`, `+` precisam ser URL-encoded na senha,
senão o parser de URL corta a string no meio.
**Mais simples:** gere senhas com só letras + números pro Redis.

### Warning de collation version mismatch no Postgres

```
WARNING: database "klivy" has a collation version mismatch
```

Não bloqueia nada — só barulho por conta de o volume ter sido criado com glibc
de versão diferente. Pra silenciar, abra terminal do serviço `database` e rode:

```sql
psql -U postgres -c "ALTER DATABASE template1 REFRESH COLLATION VERSION;"
psql -U postgres -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;"
psql -U postgres -c "ALTER DATABASE klivy REFRESH COLLATION VERSION;"
```

---

## 🧹 Manutenção

### Executar comando dentro do container Rails
```bash
docker exec -it beclinic-rails-1 bash
```

### Rails console
```bash
docker exec -it beclinic-rails-1 bundle exec rails console
```

### Rodar migrations
```bash
docker exec -it beclinic-rails-1 bundle exec rails db:migrate
```

### Ver volumes em uso
```bash
docker volume ls
```

### Limpar volumes órfãos (sem afetar dados ativos)
```bash
docker volume prune -f
```

---

## ☢️ Reset total (apaga TUDO, inclusive banco)

```bash
docker compose down
docker rm -f $(docker ps -aq)
docker volume rm $(docker volume ls -q)
docker system prune -a -f

# Depois, rebuild do zero:
docker build -t chatwoot:development -f docker/Dockerfile .
docker compose up --build
```

> ⚠️ **Isso apaga o banco de dados!** Só use se quiser começar do zero.

---

## 📝 Notas importantes

- O nome do projeto é **beclinic** (configurado em `.env` → `COMPOSE_PROJECT_NAME=beclinic`)
- Não precisa digitar `-p beclinic` nos comandos
- O `docker compose stop` + `start` é mais rápido que `down` + `up`
- O HMR (Hot Reload) funciona automaticamente — alterações em arquivos `.vue` refletem no navegador sem F5
