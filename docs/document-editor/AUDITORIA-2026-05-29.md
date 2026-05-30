# Auditoria completa — Área de Documentos (29/05/2026)

Auditoria de ponta a ponta da nova área de Documentos: backend (banco, modelos,
controllers, renderer, variáveis), frontend (design system, visual, UX) e
verificação funcional em runtime (criação, pastas, exclusão, isolamento por
conta, variáveis).

**Método:** 2 varreduras paralelas de leitura (backend + frontend), suíte RSpec
(76 exemplos), e um *smoke-test* transacional no banco de dev (rollback no fim —
nada foi gravado) exercitando o comportamento real.

---

## TL;DR

- ✅ **Funcional: tudo passou.** Banco isolado por conta, exclusão é real (não
  arquiva escondido) e bloqueia quando há documentos gerados, variáveis
  substituem/formatam corretamente. 76/76 specs verdes.
- ✅ **Segurança: postura sólida.** XSS, injeção de CSS, SSRF, escopo por conta e
  autorização estão tratados. Nenhum buraco crítico encontrado.
- 🔧 **Corrigi nesta auditoria:** aba ativa preta→azul, lupa da busca,
  `deep_dup` no duplicar, guarda de profundidade no renderer.
- 🔴 **1 risco ALTO não-código exige sua decisão:** o plugin inteiro está **fora
  do Git** (risco de perda de trabalho).

---

## 🔴 ALTO

### A1 — O plugin inteiro está FORA do controle de versão (risco de perda)
`plugins/document_templates/` tem **0 arquivos versionados** no Git. Não está no
`.gitignore` — simplesmente nunca foi `git add`ado. O mesmo vale para
`docs/document-editor/`.

**Por que importa:** toda a feature (código + docs) só existe na sua cópia local.
Um `git clean -fd`, um checkout de branch ou um reset agressivo apaga tudo, e não
há commit pra recuperar. É literalmente "perder os arquivos".

**Como corrigir:** versionar o plugin.
```bash
git add plugins/document_templates docs/document-editor
git commit -m "feat(document-templates): adiciona plugin de modelos de documentos"
```
> Não fiz o commit porque mexer no histórico é decisão sua. É só dar OK.

---

## 🟠 MÉDIO

### M1 — Sem specs de controller / autorização
Existem specs de modelo, catálogo e renderer (76 exemplos), mas **nenhum** spec
de controller. As regras de autorização (só admin escreve; clínica não edita
template Klivy; isolamento por conta no `load_template`) só estão cobertas por
leitura de código, não por teste automatizado. Uma regressão silenciosa de
permissão não seria pega.
**Ação sugerida:** request specs para index/create/update/destroy cobrindo
admin-vs-agente e conta-A-não-acessa-conta-B.

### M2 — Variável inexistente vira fallback silencioso
`Resolver#resolve` → se a chave não existe no catálogo, devolve o fallback
(`_______`) **sem logar nada**. Um typo num template (`{{patient.nome}}` em vez
de `patient.full_name`) some no PDF como uma linha em branco, e ninguém percebe.
**Ação sugerida:** `Rails.logger.warn` quando a chave não existe no `Catalog`.
(Arquivo: `app/services/document_templates/resolver.rb`.)

### M3 — `KlivyLibrarySection` é código morto
O componente `KlivyLibrarySection.vue` e o partial
`styles/index/_klivy-library-section.scss` **não são montados em lugar nenhum**
(a biblioteca Klivy hoje aparece pela aba "Biblioteca Klivy"). Além de CSS morto
embarcado no bundle, ele ainda usa **tokens Radix antigos** (`rgb(var(--slate-N))`,
`rgb(var(--blue-11))`) em vez dos tokens M3 (`--kl-*`) — ou seja, se fosse
remontado, sairia fora do design system.
**Ação sugerida:** apagar o componente + o partial (princípio "sem arquivos
mortos / arquitetura limpa").

### M4 — `archived_at` x `status` sem garantia no banco
O `status='archived'` e o timestamp `archived_at` são mantidos em sincronia por
um callback (`sync_archived_at`). Funciona pela aplicação, mas se algum dia algo
escrever direto no banco (migration, correção manual), os dois divergem e a query
de arquivados por índice mente.
**Ação sugerida:** `CHECK ((status='archived') = (archived_at IS NOT NULL))`.

---

## 🟡 BAIXO

### B1 — `content_json` com aninhamento > ~100 níveis vira `nil` silenciosamente
JSON com > 100 níveis de aninhamento é **rejeitado pelo parser de request do
Rails** com `JSON::NestingError` (400 gracioso) — então **não é vetor de ataque
externo nem trava o sistema**. Internamente, o round-trip do JSONB no
ActiveRecord também degrada pra `nil` em vez de estourar a pilha. Resumo: não é
crash, mas um documento patologicamente aninhado viraria `nil` sem aviso.
(Já mitigado pela guarda de profundidade que adicionei no renderer — ver C4.)

### B2 — Azuis da marca hardcoded no seletor de cor do editor
`EditorColorPicker.vue` lista `#003cc1` e `#1552f1` como swatches fixos (que são
exatamente `--kl-primary` e `--kl-primary-container`). São cores de **conteúdo**
(escolha do usuário pro texto), então não é bug — mas se a paleta da marca mudar,
esses dois não acompanham. Cosmético/manutenção.

### B3 — Cores fixas no conteúdo do editor e nos chips de variável
`_editor.scss` e `_variable-node.scss` usam hex fixos (texto escuro, fundo
branco, azul de link `#0066cc`). **É intencional e correto** — o conteúdo
representa o que vai pro PDF (sempre papel branco), independente do tema
dark/light da clínica. Documentado nos próprios arquivos. Sem ação.

---

## ✅ CORRIGIDO nesta auditoria

| # | O quê | Arquivo |
|---|-------|---------|
| C1 | **Aba ativa preta → azul da marca.** "Meus modelos" selecionado usava `--kl-on-surface` (#1c1b1b, preto). Trocado por `--kl-primary` (#003cc1). Badge de contagem na aba ativa trocado de cinza-escuro pra branco translúcido (lê bem no azul). | `styles/shared/_segmented-tabs.scss` |
| C2 | **Lupa sobre o texto da busca.** A fonte já tinha `padding-left: 42px` limpando o ícone de 18px em `left:14px` (estava correta). Reforcei a centralização vertical do ícone (`top:50% / translateY`) pra não depender do comportamento de `align-items` com elemento absoluto. *Se ainda aparecer sobreposto, é cache do browser — ver nota abaixo.* | `styles/index/_documents-header.scss` |
| C3 | **`duplicate` copiava JSONB por referência.** `@template.dup` faz cópia rasa de `content_json` e `metadata`; agora ambos vão por `deep_dup`. Sem isso, editar a cópia podia mutar o original em memória. | `controllers/.../document_templates_controller.rb` |
| C4 | **Guarda de profundidade no renderer.** Walk recursivo não tinha teto; conteúdo aninhado demais (via seeds/import em Ruby puro, que pulam o parser de request) poderia estourar a pilha. Adicionado `MAX_NODE_DEPTH = 100` (casa com o limite do parser JSON). Defesa-em-profundidade. | `services/document_templates/renderer.rb` |

> **Nota sobre cache (C2 e o input de tamanho de fonte):** o app roda em
> `development` com o **vite dev server (3036) ativo**, então ele serve o CSS
> fresquinho por HMR — o build em `public/vite` é ignorado nesse modo. Bugs
> visuais "que voltam" geralmente são o browser segurando CSS antigo: um
> **hard reload (Cmd+Shift+R)** resolve.

---

## ✅ Verificação funcional (evidências de runtime)

Smoke-test transacional (rollback no fim — não gravou nada) + 76 specs.

| Área | Resultado |
|------|-----------|
| **Biblioteca Klivy** | 22 modelos, **todos** com `account_id = NULL` (global, read-only). 22 tipos. |
| **Isolamento por conta** | Conta A enxerga o próprio modelo ✓ · Conta B **NÃO** enxerga o privado de A ✓ · Conta B enxerga a biblioteca Klivy ✓ → **banco separadinho confirmado**. |
| **Pastas** | Cria + aninha ✓ · pasta com subpasta **bloqueia** exclusão ✓ · pasta com modelo **bloqueia** exclusão ✓ · pasta vazia é **excluída de verdade** ✓. |
| **Exclusão de modelo** | Registro **removido do banco** (não vira arquivado) ✓ · associação `documents` é `restrict_with_error` → bloqueia delete se já gerou documentos (sugere arquivar) ✓. |
| **Variáveis** | `full_name` substitui ✓ · CPF formata (`123.456.789-00`) ✓ · idade calcula do `birthdate` ✓ · variável inexistente **não quebra** (fallback) ✓ · nenhum `{{...}}` cru vaza ✓. |
| **Catálogo** | 55 variáveis: Paciente 23, Clínica 12, Profissional 9, Data 11. |
| **RSpec** | `76 examples, 0 failures`. |

---

## ✅ Postura de segurança (o que está BOM)

- **XSS:** todo texto livre e valor de variável passa por `ERB::Util.html_escape`
  (exceto formatter `:image_tag`, que gera tag controlada com URL escapada).
- **Injeção de CSS:** `color`, `font-family`, `font-size`, `line-height` passam
  por allowlists estritas (regex ancorada `\A...\z`); valores com `;`/`:`/`\`/
  `url()` são **descartados**. `text-align` só aceita 4 valores; `indent` é
  clampado em 8 níveis.
- **SSRF / esquemas perigosos:** links e imagens passam por `safe_href?` —
  rejeita `javascript:`, `data:`, `vbscript:`; aceita só http/https/mailto/tel/
  relativo/âncora.
- **Escopo por conta:** `load_template` e `policy_scope` usam
  `for_account(Current.account)` (próprios + Klivy global). Pasta sempre filtrada
  por `account`.
- **Autorização:** Pundit exige `administrator?` em toda escrita; clínica não
  edita/exclui template Klivy; `parent_id` de pasta de outra conta é barrado por
  validação de modelo.
- **Integridade:** `rendered_html` dos documentos gerados é **imutável** após a
  primeira geração (trilha de auditoria/LGPD). Exclusão de modelo com documentos
  vinculados é bloqueada por FK (`restrict_with_error`).

---

## Apêndice — arquitetura do banco (separação confirmada)

- `document_template_folders` — pastas, **sempre** com `account_id` (not null).
- `document_templates` — `account_id` **nullable de propósito**: `NULL` = modelo
  Klivy global (read-only); preenchido = modelo da clínica. `source` ∈
  {`klivy`, `clinic`, `cloned`}; `status` ∈ {`draft`, `active`, `archived`}.
- Índices compostos por `(account_id, document_type, status)` e
  `(account_id, folder_id)`; índice parcial pra biblioteca Klivy
  (`WHERE account_id IS NULL`).
- 22 modelos Klivy seedados em código (idempotente via `LibrarySeeder`): 10
  clínicos + 12 de consentimento.
