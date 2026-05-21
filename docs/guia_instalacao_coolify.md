# Guia de Instalação do Coolify – Evitando Conflitos de Portas e Containers

## 📋 Visão geral
Este documento descreve como instalar **Coolify** em um ambiente de desenvolvimento que já executa o stack do **KlivyApp** (Docker Compose com Rails, Vite, Redis, Postgres, etc.). O objetivo é garantir que os serviços do Coolify **não** entrem em conflito com as portas ou redes dos containers já existentes.

---

## 1️⃣ Pré‑requisitos
| Requisito | Versão / Observação |
|-----------|---------------------|
| **Docker Engine** | `>= 24.x` (já inclui Docker Compose v2) |
| **Git** | `>= 2.40` |
| **rbenv / Ruby** (somente para o KlivyApp) | Conforme especificado em `.ruby-version` |
| **Node.js** (opcional, para compilação de assets) | `20.x` |
| **Portas livres** | Ao menos duas portas que **não** estejam sendo usadas pelo stack atual (ex.: `4000` para a UI do Coolify e `8081` para a API) |

> **Dica:** Execute `docker ps --format "table {{.Names}}	{{.Ports}}"` para listar os mapeamentos de portas atuais.

---

## 2️⃣ Identificar as portas já em uso
Saída do seu `docker ps`:
```
beclinic-rails-1             0.0.0.0:3000->3000/tcp
beclinic-vite-1              0.0.0.0:3036->3036/tcp
beclinic-redis-1             0.0.0.0:6379->6379/tcp
beclinic-postgres-1          0.0.0.0:5433->5432/tcp
beclinic-whatsapp_bridge-1   0.0.0.0:3002->3002/tcp
beclinic-mailhog-1           0.0.0.0:1025->1025/tcp, 0.0.0.0:8025->8025/tcp
```
**Portas em uso:** `3000, 3002, 3036, 6379, 5433, 1025, 8025`.

Para evitar conflitos, vamos usar **4000** (UI) e **8081** (API) – ambas livres.

---

## 3️⃣ Clonar e preparar o Coolify
```bash
# 1. Clonar o repositório oficial
git clone https://github.com/Coolify/Coolify.git && cd Coolify

# 2. Copiar o arquivo de exemplo de variáveis de ambiente
cp .env.example .env
```
Edite o arquivo `.env` (use seu editor favorito) e ajuste as portas:
```bash
# Alterar as portas para evitar colisões
APP_PORT=8000          # UI ficará em http://localhost:8000
API_PORT=8081          # API (opcional) ficará em http://localhost:8081

# Gerar uma chave secreta forte para o JWT interno
APP_KEY=$(openssl rand -hex 32)

# (Opcional) Desativar registro público caso queira apenas acesso de admin
ENABLE_REGISTRATION=false
```
Salve o arquivo.

---

## 4️⃣ Sobrescrever o mapeamento de portas do Docker‑Compose
Crie um **docker‑compose.override.yml** na raiz do Coolify:
```yaml
version: "3.8"

services:
  coolify:
    ports:
      - "8000:3000"   # host:container (UI)
      - "8081:8080"   # host:container (API, opcional)
```
O Docker Compose mescla automaticamente esse arquivo com o `docker-compose.yml` quando você executar `docker compose up`.

---

## 5️⃣ Isolar o nome do projeto Docker‑Compose
O Docker Compose cria nomes de containers e uma rede própria baseada no **nome do projeto**. Por padrão ele usa o nome da pasta (`coolify`). Para garantir isolamento, exporte um nome customizado antes de iniciar:
```bash
export COMPOSE_PROJECT_NAME=coolify_beclinic   # qualquer identificador único
```
Você também pode colocar essa linha no seu `.env` (`COMPOSE_PROJECT_NAME=coolify_beclinic`).

---

## 6️⃣ Construir e iniciar o Coolify
```bash
# Certifique‑se de estar no diretório do Coolify
docker compose down          # limpa execuções anteriores
docker compose up -d         # inicia em modo detached
```
O comando baixa as imagens base, compila a UI e inicia três containers:
- `coolify_beclinic_coolify`
- `coolify_beclinic_postgres`
- `coolify_beclinic_redis`

---

## 7️⃣ Verificar a implantação
```bash
# Listar containers com as portas mapeadas
docker ps --format "table {{.Names}}	{{.Ports}}"
```
Saída esperada (exemplo):
```
coolify_beclinic_coolify   0.0.0.0:8000->3000/tcp, 0.0.0.0:8081->8080/tcp
coolify_beclinic_postgres  0.0.0.0:5432->5432/tcp
coolify_beclinic_redis      0.0.0.0:6379->6379/tcp
```
Abra o navegador em **http://localhost:4000** e conclua o wizard de configuração (criar usuário admin, senha, etc.).

---

## 8️⃣ Adicionando o projeto KlivyApp ao Coolify
1. No painel do Coolify, vá em **Projects → New Project**.
2. Escolha **From Repository** e informe a URL do seu repositório KlivyApp (`git@github.com:danilomamedes/KlivyApp.git`).
3. **Build Settings** – selecione **Dockerfile** (ou o `docker-compose.yml` existente, caso use). Se houver um Dockerfile de desenvolvimento (`Dockerfile.dev`), aponte para ele.
4. **Environment Variables** – copie todas as variáveis que o KlivyApp usa localmente (`RAILS_ENV=development`, `DATABASE_URL=postgres://...`, `REDIS_URL=redis://...`, `PNPM_INSTALL=1`, etc.).
5. **Ports** – exponha a porta web do Rails (`3000`) e a porta do Vite (`5173` ou a que você usa). O Coolify pode mapear essas portas automaticamente para portas aleatórias no host, ou você pode fixá‑las (ex.: `4002` e `4003`).
6. **Deploy Strategy** – comece com **Manual** para testar; depois habilite **Auto‑Deploy** (webhook) se desejar.
7. Salve e clique em **Deploy**.

---

## 9️⃣ Problemas comuns e como resolvê‑los
| Problema | Sintoma | Solução |
|----------|----------|--------|
| **Porta já vinculada** | `docker compose up` falha com `bind: address already in use` | Alterar o mapeamento `host:container` no `docker‑compose.override.yml` para outra porta livre. |
| **Colisão de rede** | Containers não conseguem se comunicar porque compartilham a mesma rede do outro stack | Definir um `COMPOSE_PROJECT_NAME` exclusivo (ex.: `coolify_isolado`). |
| **Conflito de banco de dados** | Dois containers PostgreSQL tentando usar o mesmo diretório de dados | Coolify usa seu próprio volume (`coolify_postgres_data`); não há conflito. |
| **Variável de ambiente ausente** | Aplicação quebra ao iniciar (ex.: `APP_KEY` não definido) | Adicionar a variável faltante no `.env` e reiniciar (`docker compose down && docker compose up -d`). |

---

## 🔁 Checklist rápido (execute antes de iniciar o Coolify)
- [ ] Rode `docker ps` e anote todas as portas **host** em uso.
- [ ] Escolha duas portas livres (ex.: **8000** para UI e **8081** para API).
- [ ] Clone o repositório Coolify e copie `.env.example → .env`.
- [ ] Edite o .env: defina APP_PORT=8000 e API_PORT=8081 (se precisar).
- [ ] Crie `docker‑compose.override.yml` com os novos mapeamentos.
- [ ] Exportar um `COMPOSE_PROJECT_NAME` único (`coolify_isolado`).
- [ ] `docker compose down && docker compose up -d`.
- [ ] Verifique com `docker ps` que as portas do host são as escolhidas.
- [ ] Abra http://localhost:8000 e conclua o wizard.
- [ ] Adicione o KlivyApp como projeto no Coolify, mantendo suas portas originais intactas.

---
## 10️⃣ Domínio personalizado local (klivy.localhost)

Você pode mapear um domínio local para a aplicação rodando no Coolify:

1. **Editar `/etc/hosts`**  
   ```bash
   sudo bash -c 'echo "127.0.0.1   klivy.localhost" >> /etc/hosts'
   ```

2. **Adicionar o domínio no Coolify**  
   - Acesse o painel (`http://localhost:8000`).  
   - *Project → Settings → Domain* → `klivy.localhost`.  
   - Marque **Enable TLS** se quiser `https://`. O Caddy gera um certificado auto‑signed.  

3. **Atualizar a variável de ambiente da aplicação** (opcional)  
   ```bash
   APP_URL=https://klivy.localhost   # ou http://klivy.localhost
   ```

4. **Redeploy** o projeto.  
   O Caddy passa a rotear `klivy.localhost` para a porta interna do seu container (ex.: 3000).

Agora a aplicação pode ser acessada via `http://klivy.localhost` (ou `https://klivy.localhost`) sem precisar especificar a porta.
## 📚 Recursos adicionais
- **Documentação do Coolify**: https://coolify.io/docs
- **Docker Compose – arquivos de sobrescrita**: https://docs.docker.com/compose/extends/#multiple-compose-files
- **Configuração Docker do Chatwoot/KlivyApp**: veja os arquivos `Procfile.dev` e `docker-compose.yml` dentro da pasta `KlivyApp`.

---

*Criado por Antigravity – seu parceiro de programação AI.*
