---
name: migrate-css-to-scss
description: Migra arquivo CSS puro de um plugin Beclinic para SCSS modular (entry point + partials por domínio + _variables.scss + nesting BEM opcional). Use quando o user pedir para migrar/converter um módulo (ex.: `plugins/agenda`, `plugins/financial`, `plugins/ajuda`) de `.css` para `.scss` seguindo o padrão Chatwoot já adotado em `plugins/patients/frontend/styles/`. Reproduz exatamente o trabalho feito em `plugins/patients` (entrada CHANGELOG `1.5.1.62`).
---

# Migrate CSS → SCSS modular

Esta skill executa a migração de um arquivo CSS plano de plugin Beclinic para a estrutura SCSS modular padrão Chatwoot. O caso de referência é [plugins/patients/frontend/styles/](plugins/patients/frontend/styles/) (migração concluída em `1.5.1.62`).

## Pré-requisitos confirmados (não precisa verificar de novo)

- `sass: 1.79.3` está em `pnpm-lock.yaml` — Vite resolve `.scss` nativamente.
- Padrão SCSS é a convenção oficial documentada em [AGENTS.md](AGENTS.md) seção "Plugin Styles (SCSS por padrão)".
- Pre-commit hook em `.husky/pre-commit` bloqueia novos `.css` em `plugins/` — confere a whitelist de legacy lá ao final.

## Quando usar

Quando o user pedir para migrar um plugin específico, ex.:
- "migrar o CSS do plugin agenda para SCSS"
- "fazer o plugin financial seguir o padrão do patients"
- "converter `<arquivo>.css` para SCSS modular"

Não use para:
- Reorganizar SCSS já existente (use refat manual).
- Arquivos < 500 linhas (overhead não compensa — manter como está).
- Plugins com ≤ 3 domínios distintos (1 partial só não justifica a estrutura).

## Inputs

- **arquivo CSS principal** do plugin (geralmente `plugins/<engine>/frontend/.../<nome>.css`)
- **import points** (quais `.vue` fazem `import './X.css'`)
- **prefixos de classe** distintos por domínio (ex: `.evo-*`, `.fin-*`, `.aud-*`)

## Fluxo de 4 fases

### Fase 1 — Rename + smoke test (zero risco)

**Objetivo:** garantir que pipeline SCSS funciona com o conteúdo atual sem mudança.

```bash
PLUGIN=<engine>            # ex: agenda
SRC_CSS=<caminho/atual>    # ex: plugins/agenda/frontend/styles/agenda-events.css
NEW_DIR=plugins/$PLUGIN/frontend/styles
NEW_SCSS=$NEW_DIR/<nome>.scss

mkdir -p $NEW_DIR
git mv $SRC_CSS $NEW_SCSS  # preserva histórico Git
```

Atualizar imports nos `.vue` que carregam o arquivo:
```diff
- import '<caminho/relativo>.css';
+ import '@plugins/<engine>/frontend/styles/<nome>.scss';
```

Use Grep para encontrar todos os imports antes de editar. Pode haver mais de um arquivo `.vue` importando.

**Validação:** rode `pnpm dev` ou peça pro user fazer e confirmar que abre. SCSS é superset de CSS — conteúdo idêntico compila sem erro.

### Fase 2 — Extrair partials por domínio

**Identificar marcadores** de seção no SCSS (comentários):

```bash
grep -nE "^/\\* (={3,}|═{3,}|── )" $NEW_SCSS | head -50
```

Mapear cada bloco de linhas → partial. Critério:
- Prefixo de classe único (`.fin-*` → `_financial.scss`, `.evo-*` → `_evolution.scss`).
- Headers/wrappers/layouts → `_layout.scss`.
- Animações → `_animations.scss`.
- Refinements light/dark mode → `_dark-mode-overrides.scss`.

**Extrair via `sed -n 'M,Np'`** em loop:

```bash
mkdir -p $NEW_DIR/<nome>
SRC=$NEW_SCSS

# Para cada partial: extrair faixa de linhas exatas. Suporta múltiplos
# ranges concatenados quando um domínio aparece em vários blocos do
# arquivo original (preserva ordem crescente de linha = ordem original).
{ sed -n 'A1,B1p' $SRC; sed -n 'A2,B2p' $SRC; } > $NEW_DIR/<nome>/_<dominio>.scss
```

Exemplo concreto (do patients):
```bash
{ sed -n '32,55p' $SRC; sed -n '93,108p' $SRC; sed -n '3255,3297p' $SRC; } > record/_header-actions.scss
```

**Sobrescrever entry** (`<nome>.scss`) com 38-linhas de cabeçalho + `@use`:

```scss
/* Comentário de propósito + import path no Vue.
   Ordem de @use respeita cascata da primeira ocorrência de cada
   partial no arquivo original — mover de lugar pode alterar override
   resolution para classes que competem. */

@use '<nome>/layout';
@use '<nome>/animations';
@use '<nome>/<dominio-1>';
// ... ordem de primeira-ocorrência
```

**Validar contagem:**
```bash
ORIG_LINES=$(wc -l < /tmp/<nome>-backup.scss || echo 0)
PARTIALS_LINES=$(cat $NEW_DIR/<nome>/*.scss | wc -l)
echo "Original: $ORIG_LINES, Partials: $PARTIALS_LINES, Diff: $((ORIG_LINES - PARTIALS_LINES))"
```

Diferença esperada: 0 ou pequena (apenas comentários descritivos do entry original que não foram migrados).

### Fase 3 — Variáveis SCSS

**Análise de frequência** — identifica cores hardcoded com ≥5 ocorrências:

```bash
cd $NEW_DIR/<nome>
echo "=== rgba semantic counts ==="
for color in "34, 197, 94" "220, 38, 38" "217, 119, 6" "59, 130, 246" \
             "124, 58, 237" "239, 68, 68" "245, 158, 11" "22, 163, 74"; do
  count=$(grep -hr "rgba($color" *.scss | wc -l)
  printf "rgba(%-22s | %d\n" "$color)" "$count"
done

echo ""
echo "=== hex counts ==="
for hex in "#16a34a" "#dc2626" "#d97706" "#2563eb" "#7c3aed" "#475569" \
           "#64748b" "#fbbf24" "#4ade80" "#f87171" "#60a5fa" "#3b82f6" \
           "#15803d" "#b91c1c" "#94a3b8" "#25D366"; do
  count=$(grep -hor "$hex" *.scss | wc -l)
  printf "%-12s | %d\n" "$hex" "$count"
done
```

**Criar `_variables.scss`** com as cores que passam do threshold (5+). Use o template de [plugins/patients/frontend/styles/_variables.scss](plugins/patients/frontend/styles/_variables.scss):

```scss
// Brand semantic colors
$brand-success:        #16a34a;
$brand-success-strong: #15803d;
$brand-success-light:  #4ade80;
$brand-success-bright: #22c55e;

$brand-danger:         #dc2626;
$brand-danger-light:   #f87171;
$brand-danger-strong:  #b91c1c;
$brand-danger-bright:  #ef4444;

$brand-info:           #2563eb;
$brand-info-bright:    #3b82f6;
$brand-info-light:     #60a5fa;

$brand-amber:          #d97706;
$brand-amber-bright:   #f59e0b;
$brand-amber-strong:   #fbbf24;

$brand-purple:         #7c3aed;
$brand-purple-bright:  #a855f7;
$brand-purple-light:   #c084fc;

$brand-slate-mid:      #475569;
$brand-slate-light:    #94a3b8;

$whatsapp-green: #25D366;
```

**Substituição em batch** via `perl` (regex com lookahead negativo evita match em hex maiores):

```bash
for f in $NEW_DIR/<nome>/_*.scss; do
  perl -i -pe '
    # rgba semantic
    s/rgba\(\s*59\s*,\s*130\s*,\s*246\s*,/rgba(\$brand-info-bright,/g;
    s/rgba\(\s*22\s*,\s*163\s*,\s*74\s*,/rgba(\$brand-success,/g;
    s/rgba\(\s*245\s*,\s*158\s*,\s*11\s*,/rgba(\$brand-amber-bright,/g;
    s/rgba\(\s*220\s*,\s*38\s*,\s*38\s*,/rgba(\$brand-danger,/g;
    s/rgba\(\s*239\s*,\s*68\s*,\s*68\s*,/rgba(\$brand-danger-bright,/g;
    s/rgba\(\s*217\s*,\s*119\s*,\s*6\s*,/rgba(\$brand-amber,/g;
    s/rgba\(\s*124\s*,\s*58\s*,\s*237\s*,/rgba(\$brand-purple,/g;
    s/rgba\(\s*34\s*,\s*197\s*,\s*94\s*,/rgba(\$brand-success-bright,/g;
    # hex (lookahead negativo evita match parcial em hex maior)
    s/#16a34a(?![0-9a-fA-F])/\$brand-success/g;
    s/#dc2626(?![0-9a-fA-F])/\$brand-danger/g;
    s/#2563eb(?![0-9a-fA-F])/\$brand-info/g;
    s/#3b82f6(?![0-9a-fA-F])/\$brand-info-bright/g;
    s/#d97706(?![0-9a-fA-F])/\$brand-amber/g;
    s/#7c3aed(?![0-9a-fA-F])/\$brand-purple/g;
    s/#15803d(?![0-9a-fA-F])/\$brand-success-strong/g;
    s/#60a5fa(?![0-9a-fA-F])/\$brand-info-light/g;
    s/#f87171(?![0-9a-fA-F])/\$brand-danger-light/g;
    s/#fbbf24(?![0-9a-fA-F])/\$brand-amber-strong/g;
    s/#4ade80(?![0-9a-fA-F])/\$brand-success-light/g;
    s/#94a3b8(?![0-9a-fA-F])/\$brand-slate-light/g;
    s/#25D366(?![0-9a-fA-F])/\$whatsapp-green/gi;
    s/#475569(?![0-9a-fA-F])/\$brand-slate-mid/g;
    s/#b91c1c(?![0-9a-fA-F])/\$brand-danger-strong/g;
  ' "$f"
  # Add @use no topo SE o partial usa pelo menos uma var
  if grep -qE '\$brand-|\$whatsapp-' "$f"; then
    sed -i '1i @use "../variables" as *;\n' "$f"
  fi
done
```

**Validação:** SCSS resolve `rgba($brand-info-bright, 0.07)` em compile-time para `rgba(59, 130, 246, 0.07)` — output CSS final é byte-equivalente ao da Fase 2. Zero risco visual.

### Fase 4 — Nesting BEM (parcial, opcional)

**Aplicar APENAS** em partials com padrão BEM forte e poucos `!important` (ex: famílias `.X-toggle`, `.X-icon`, `.X--variant`).

**Padrão de transformação:**

```scss
// Antes
.fin-kpi-card { ... }
.fin-kpi-card--green { ... }
.fin-kpi-card--green:hover { ... }
.fin-kpi-icon { ... }

// Depois
.fin-kpi {
  &-card {
    ...
    &--green {
      ...
      &:hover { ... }
    }
  }
  &-icon { ... }
}
```

**Cuidados:**
- Output CSS pelo SCSS é **byte-idêntico** ao plano (nesting é puramente sintático).
- NÃO mergear blocos com `!important` em ranges sobrepostos do arquivo original — risco de mudar cascata.
- Skipar partials curtos (< 100 linhas) — overhead de leitura > ganho.
- Validar diff do CSS compilado: `pnpm build` e comparar `dist/`.

**Recomendação:** fazer em 1 partial como prova de conceito + deixar resto plano. Migração orgânica nos próximos refators.

## Validação final

1. **Diff visual completo** das views afetadas (viewport 1440 + 375).
2. **`pnpm dev`** sem erro de compilação SCSS.
3. **`pnpm build`** gera CSS sem erro.
4. **Spot check** de 5-10 classes aleatórias via DevTools.
5. **Pre-commit hook** confirma que não houve regressão (não bloqueia, pois não há `.css` novo).

## Armadilhas conhecidas

| Problema | Causa | Solução |
|---|---|---|
| Diferença de linhas entre original e partials | Comentários descritivos do header não migrados | Aceitável se for só comentário (verificar `git diff -U0` da linha original) |
| `@use` falha com erro de namespace | Variáveis não exportadas com `as *` | Confirmar `@use "../variables" as *;` no topo (não só `@use`) |
| Cor não substituída pelo perl | Espaços inconsistentes ou case mismatch | Adicionar `\s*` entre vírgulas e flag `/i` para hex case-insensitive |
| Cascata de override quebra após split | Ordem de `@use` no entry diferente da ordem original | Reordenar `@use` para ordem de primeira-ocorrência no arquivo original |
| Vite não recompila ao salvar | Cache do dev server | Reiniciar `pnpm dev` |

## Documentação obrigatória ao finalizar

1. **Atualizar [CHANGELOG.md](CHANGELOG.md)** seguindo o padrão Beclinic (incrementa `D`, ISO `-03:00`, **Problema** + **Solução** + **Arquivos Modificados**). Use a entrada `1.5.1.62` como referência.
2. **Documentar a migração no CHANGELOG** com as 4 fases (rename + smoke test, extração de partials, variáveis, nesting BEM opcional) e seus deltas (linhas movidas, ocorrências hardcoded substituídas). Não criar doc separado em `docs/03-engineering/` — a entrada do CHANGELOG + commit são a fonte da verdade.
3. Se houver `.css` legacy restante no plugin (porque migrou só um arquivo), **NÃO** alterar `.husky/pre-commit` — a whitelist desses arquivos legacy continua válida até migrar 100% do plugin.

## Não-objetivos

- ❌ Refatorar lógica de negócio do `.vue` enquanto migra CSS — escopo é puramente CSS.
- ❌ Mudar `<style scoped>` em `.vue` (esse é trabalho separado — usa skill diferente).
- ❌ Renomear classes ou prefixos durante a migração (causa risco de quebra de templates).
- ❌ Aplicar nesting agressivo em todos os partials (Fase 4 é opcional e cirúrgica).

## Resultado esperado

Replicação fiel do que foi feito em `plugins/patients`:
- Entry SCSS com 30-40 linhas (era 3.000+).
- 15-25 partials médios de ~150 linhas cada, organizados por domínio.
- `_variables.scss` com 15-25 tokens semânticos.
- 1 partial com nesting BEM como prova de conceito.
- CSS compilado byte-equivalente ao original.
- Zero regressão visual após validação.
