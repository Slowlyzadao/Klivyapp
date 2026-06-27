# Build e Deploy — KlivyApp

Padrão de build da imagem Docker de produção para `mamedes/klivy-prod`.

## Forma recomendada — script automatizado

O jeito suportado é via [`bin/build-prod.sh`](../bin/build-prod.sh). Ele:

- Valida o formato da versão (`vX.Y.Z.W`).
- Autodetecta a versão anterior a partir das imagens locais e usa como `--cache-from`.
- Executa `docker pull` (best-effort), `docker build --platform linux/amd64`, e `docker push`.
- Captura todo o stdout/stderr em `build_production.log` (sobrescrito a cada execução), para auditoria.

> **Setup inicial (uma vez só):** se for o primeiro uso após `clone` ou em WSL, dê permissão de execução nos scripts:
> ```bash
> chmod +x bin/*.sh
> ```
> Sem isso, `bin/build-prod.sh` e `bin/cleanup-prod-images.sh` retornam `Permission denied`.

```bash
# Build + push de uma nova versão. Autodetecta a anterior localmente.
bin/build-prod.sh v1.4.4.53

# Ou forçando a versão anterior explicitamente:
bin/build-prod.sh v1.4.4.53 v1.4.4.52
```

Flags via variáveis de ambiente:

| Variável | Efeito |
|---|---|
| `SKIP_PUSH=1` | Faz o build mas **não** dá push. Útil para teste local. |
| `NO_CACHE=1` | Ignora `--cache-from` e força rebuild completo. |

```bash
SKIP_PUSH=1 bin/build-prod.sh v1.4.4.53
NO_CACHE=1 bin/build-prod.sh v1.4.4.53
```

## Forma manual (equivalente, caso precise rodar passo a passo)

Substitua `<NOVA_VERSAO>` pela próxima tag e `<VERSAO_ANTERIOR>` pela última já publicada (usada como cache).

```bash
docker pull mamedes/klivy-prod:<VERSAO_ANTERIOR> || true

docker build \
  --platform linux/amd64 \
  --cache-from mamedes/klivy-prod:<VERSAO_ANTERIOR> \
  -t mamedes/klivy-prod:<NOVA_VERSAO> \
  .

docker push mamedes/klivy-prod:<NOVA_VERSAO>
```

### Exemplo real

Última versão publicada `v1.4.4.52`, nova versão `v1.4.4.53`:

```bash
docker pull mamedes/klivy-prod:v1.4.4.52 || true

docker build \
  --platform linux/amd64 \
  --cache-from mamedes/klivy-prod:v1.4.4.52 \
  -t mamedes/klivy-prod:v1.4.4.53 \
  .

docker push mamedes/klivy-prod:v1.4.4.53
```

## Checklist antes de buildar

- [ ] Commit e push das alterações no git
- [ ] Bumpar a tag (não reutilizar a mesma versão)
- [ ] Build e push usam **a mesma tag** (erro comum: buildar `.52` e dar push em `.53`)
- [ ] `--platform linux/amd64` é obrigatório quando buildando de Mac (Apple Silicon) para servidor x86

## Depois do push

1. Atualizar a tag da imagem no painel de deploy (Coolify/EasyPanel/compose) para `<NOVA_VERSAO>`.
2. Redeploy do serviço.
3. Conferir logs de startup (`web.1`, `worker.1`, `whatsapp.1`).

## Limpeza de imagens antigas

📖 **Guia detalhado passo a passo:** [docs/docker_cleanup.md](docker_cleanup.md)

Cada build gera uma imagem de ~5 GB. Depois de algumas versões, o disco local enche. Use [`bin/cleanup-prod-images.sh`](../bin/cleanup-prod-images.sh) para remover imagens **locais** antigas, mantendo apenas as N mais recentes:

```bash
# Preview (não deleta nada — só mostra o que seria removido)
DRY_RUN=1 bin/cleanup-prod-images.sh          # mantém 3 (default)
DRY_RUN=1 bin/cleanup-prod-images.sh 5        # mantém 5

# Executa de verdade
bin/cleanup-prod-images.sh                    # mantém 3
bin/cleanup-prod-images.sh 5                  # mantém 5
```

O script:
- Só toca em tags `vX.Y.Z.W` de `mamedes/klivy-prod` — `latest`, outras tags e outras imagens (chatwoot, postgres, etc.) ficam intocadas.
- Ordena por versão (descendente) e remove o que passar do limite.
- Não deleta imagens em uso por container rodando (Docker rejeita e o script pula).

Depois, para recuperar os layers dangling:

```bash
docker image prune            # remove layers órfãos sem tag
docker system df              # mostra uso total de disco
```

### Docker Hub

O script **não** limpa o Docker Hub — fazer manualmente em <https://hub.docker.com/r/mamedes/klivy-prod/tags>. Recomendação: manter as últimas 10-15 versões no Hub (pra poder fazer rollback rápido em produção) e só deletar o que claramente não vai mais ser usado.

## Processos dentro da imagem

A imagem roda três processos via foreman ([Procfile](../Procfile)):

- `web` — Rails/Puma na porta 3000
- `worker` — Sidekiq
- `whatsapp` — Bridge Node.js ([lib/whatsapp/server.js](../lib/whatsapp/server.js)) na porta 3002
