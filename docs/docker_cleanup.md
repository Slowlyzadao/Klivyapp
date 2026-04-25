# Limpeza de Imagens Docker — Passo a Passo

Guia rápido para liberar espaço em disco removendo imagens antigas de `mamedes/klivy-prod`. Cada imagem tem ~5 GB, então acumula rápido.

---

## Parte 1 — Limpeza LOCAL (sua máquina)

### Quando fazer

A cada **~5 builds novas**, ou sempre que o Docker Desktop estiver consumindo muito disco.

### Passo a passo

**1. Abre o terminal WSL no projeto:**

```bash
cd ~/KlivyApp
```

**2. Preview — vê o que seria deletado (não deleta nada ainda):**

```bash
DRY_RUN=1 bin/cleanup-prod-images.sh
```

Exemplo de saída:
```
Keeping the 3 most recent:
  ✓ v1.4.4.52
  ✓ v1.4.4.51
  ✓ v1.4.4.50

Will remove 10 older version(s):
  ✗ v1.4.4.49
  ...
  ✗ v1.4.4.40
```

**3. Confere a lista.** Se tiver alguma versão que você NÃO quer deletar (ex: rodando em staging), pare aqui.

**4. Deleta de verdade:**

```bash
bin/cleanup-prod-images.sh
```

**5. Remove camadas órfãs sem tag (libera mais espaço):**

```bash
docker image prune -f
```

**6. Confere quanto de disco liberou:**

```bash
docker system df
```

### Atalho — tudo de uma vez

Depois do preview, se estiver tudo ok, copia-e-cola:

```bash
bin/cleanup-prod-images.sh && docker image prune -f && docker system df
```

### Variações

**Manter mais versões** (ex: últimas 5):
```bash
bin/cleanup-prod-images.sh 5
```

**Preview mantendo 5:**
```bash
DRY_RUN=1 bin/cleanup-prod-images.sh 5
```

### Via VS Code (sem terminal)

`Ctrl+Shift+P` → `Run Task` → escolhe:
- 🔍 **Cleanup: preview** (DRY-RUN primeiro)
- 🗑️ **Cleanup: remover imagens antigas** (executa)

Pergunta quantas manter (padrão: 3).

### Segurança do script

- Só toca em tags `vX.Y.Z.W` de `mamedes/klivy-prod`.
- **Não toca** em: `latest`, `chatwoot`, `postgres`, `redis`, `pgvector`, nem nenhuma outra imagem.
- **Não toca** no Docker Hub (só local).
- Se a imagem está em uso por um container rodando, Docker rejeita a remoção e o script pula — seguro.

---

## Parte 2 — Limpeza no DOCKER HUB (online)

### Quando fazer

Uma vez por **trimestre** (3-4 meses), manualmente. Não automatizar — risco de quebrar rollback em produção.

### Regra de ouro

**Manter no Hub:**
- ✅ Versão **ativa em produção** (obrigatório)
- ✅ 2-3 versões anteriores (pra rollback rápido)
- ✅ As **últimas 10-15** em geral

**Pode deletar:**
- ❌ Versões muito antigas (ex: `v1.4.4.30` ou anteriores)
- ❌ Versões que você tem certeza que nenhum cliente/ambiente usa

### Passo a passo

**1. Antes de deletar, confere quais versões estão ativas:**

Em cada painel de deploy (Coolify, EasyPanel, compose local), veja qual tag de imagem está configurada. Anota as versões em uso.

**2. Abre o Docker Hub:**

<https://hub.docker.com/r/mamedes/klivy-prod/tags>

**3. Faz login** (usuário `mamedes`).

**4. Para cada tag que você quer deletar:**

- Localiza a linha da tag na lista.
- Clica no ícone de **lixeira 🗑️** à direita.
- Confirma.

**5. Deleta em lote** (opcional):

O Docker Hub permite selecionar múltiplas tags com checkbox e deletar todas de uma vez pelo botão "Delete" no topo.

### ⚠️ Cuidados

- **Deletar do Hub é irreversível.** Depois que a tag foi apagada, o `docker pull` dela falha. Se algum cliente tiver um `docker compose pull` agendado na versão deletada, o redeploy dele quebra.
- **Nunca deletar a tag `latest`** a menos que você saiba exatamente o que está fazendo.
- **Nunca deletar a versão em produção.** Sempre confira antes.

---

## Checklist rápido — faço isso quando?

- [ ] Disco local encheu → Parte 1 (local)
- [ ] Muitas versões acumuladas no Hub → Parte 2 (online)
- [ ] Antes de um big build importante (mais cache disponível) → Parte 1 dry-run pra ter certeza que mantém a versão base

---

## Comandos úteis relacionados

```bash
# Ver quanto disco o Docker está usando
docker system df

# Ver todas imagens locais
docker images

# Ver só do klivy-prod
docker images mamedes/klivy-prod

# Remover TUDO (cuidado! apaga imagens, containers parados, networks, etc.)
docker system prune -a
```

**Não use `docker system prune -a` se não souber o que está fazendo** — ele apaga muito mais do que o script dedicado.
