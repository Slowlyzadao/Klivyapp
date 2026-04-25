# BeClinic — Design & Style Guidelines

> Este documento é a **fonte de verdade de design** do projeto BeClinic.
> Todo componente novo ou refatorado deve seguir estas diretrizes sem exceção.
> **Leia este arquivo COMPLETO antes de qualquer trabalho de UI.**

---

## ⚠️ REGRAS ABSOLUTAS — LEIA ANTES DE QUALQUER COISA

> [!CAUTION]
> **PROIBIDO `box-shadow` em inputs, cards de formulário e qualquer campo de dados.**
> Isso foi a causa de dezenas de bugs visuais no tema claro. Zero sombra em inputs. Ponto final.

> [!CAUTION]
> **PROIBIDO bordas coloridas laterais (`border-left`/`border-right`) em cards.**
> Cards devem manter seu design "limpo" focado no conteúdo e nos ícones no header, sem listras coloridas na lateral imitando indicadores. O uso de cores laterais distrai e polui o layout de grids.

> [!CAUTION]
> **PROIBIDO hardcodar cores** como `#1e1f3c`, `#0a0c10`, `rgba(0,0,0,0.2)` em componentes que precisam funcionar em ambos os temas. Sempre use variáveis CSS `rgb(var(--slate-N))`.

> [!CAUTION]
> **PROIBIDO usar classes Tailwind com opacidade fixa para fundos** como `bg-slate-800/40`, `bg-slate-700/50`, `bg-white/5` em elementos que precisam funcionar em ambos os temas. Essas classes hardcodam o tom escuro e viram uma "barra preta" no light mode.

> [!CAUTION]
> **O projeto agora tem DOIS temas ativos: dark (padrão legado) e light (padrão novo).** Todo componente novo deve funcionar em ambos. Todo CSS deve usar variáveis CSS (`--slate-N`, `--blue-N`, etc.) que se adaptam automaticamente ao tema ativo.

> [!CAUTION]
> **PROIBIDO EMOJIS NA UI — SEM EXCEÇÃO.** Nunca use emojis (🌅 ☀️ 🌙 ✅ ❌ etc.) como ícones ou elementos visuais em componentes Vue. O BeClinic é software clínico profissional. **Sempre use ícones da biblioteca Phosphor (`i-ph-*`) ou Lucide (`i-lucide-*`).** Emojis variam de renderização entre sistemas operacionais, são inacessíveis para leitores de tela e transmitem informalidade incompatível com o produto.

> [!CAUTION]
> **IDIOMA OBRIGATÓRIO: PORTUGUÊS DO BRASIL.** Todo texto de UI — labels, placeholders, tooltips, mensagens de erro, textos de botão, badges — deve estar em **pt-BR**. As chaves de i18n ficam em `en.json` mas os **valores devem ser escritos em português**. Nunca escreva strings de UI em inglês neste projeto. Isso inclui o arquivo `en.json` que, neste projeto, é usado como repositório único de strings pt-BR (não há tradução real para inglês).

> [!CAUTION]
> **ORGANIZAÇÃO OBRIGATÓRIA EM PASTAS — SEM EXCEÇÃO.** Todo novo módulo ou feature deve ser criado em **pasta própria** dentro de `app/javascript/dashboard/features/` ou da rota correspondente. Cada arquivo tem uma única responsabilidade: componente, store, API, constantes. **PROIBIDO** adicionar lógica de novo domínio a arquivos existentes sem criar subpastas. Estrutura esperada: `features/meu-modulo/store.js`, `features/meu-modulo/MinhaView.vue`, `features/meu-modulo/MeuItem.vue`. Arquivos com mais de 400 linhas misturando múltiplos domínios violam esta regra.

---

## 🧠 Filosofia de Design — Como Pensamos

O BeClinic é uma ferramenta clínica profissional. O design deve transmitir:

- **Confiança e precisão** — quem usa é profissional de saúde. Sem infantilidade.
- **Clareza absoluta** — informação sempre legível, nunca decoração sobre conteúdo.
- **Leveza visual** — elementos que "flutuam" por contraste sutil, **nunca por sombras pesadas**.
- **Progressividade** — formulários longos são divididos em blocos com hierarquia clara.

### Regra de ouro

> "Se o elemento não adiciona informação ou orientação ao usuário, ele não deve existir."

Remova gradientes desnecessários, sombras coloridas, animações de bounce, ícones decorativos sem função, textos redundantes.

### ⛔ Regra crítica — Fundos Sempre Sólidos

> **PROIBIDO** usar fundos com transparência reduzida (ex: `rgba(255,255,255,0.03)`, `bg-white/5`, `bg-slate-900/50`) em elementos que são **fixos, sticky, modais, popups ou painéis sobrepostos**.

- Elementos `position: sticky` ou `position: fixed` **devem** ter `background` com cor **100% opaca**.
- Transparência reduzida em elementos sobrepostos faz o conteúdo de baixo "vazar" — **é um bug visual crítico**.
- Uso de `rgba` com alpha < 1.0 só é permitido em **bordas** e **badges/pills** decorativos que **nunca** ficam sobre conteúdo rolável.

---

## 🌗 Sistema de Temas — Dark e Light

O projeto usa variáveis de cor via Radix UI (`--slate-1` a `--slate-12`). Essas variáveis **se invertem automaticamente** entre os temas. Use-as **sempre**:

| Variável CSS | Dark Mode | Light Mode |
| --- | --- | --- |
| `--slate-1` | Quase preto | Branco puro |
| `--slate-2` | Cinza muito escuro | Branco quase puro |
| `--slate-3` | Cinza escuro | Cinza claríssimo |
| `--slate-4` | Cinza médio-escuro | Cinza claro |
| `--slate-5` | Cinza médio | Cinza médio-claro |
| `--slate-6` | Cinza | Cinza médio |
| `--slate-9` | Cinza claro | Cinza médio-escuro |
| `--slate-11` | Quase branco | Cinza escuro |
| `--slate-12` | Branco | Quase preto |

### Lógica de uso
- **Fundo de input:** `rgb(var(--slate-2))` → no dark fica escuro, no light fica branco ✅
- **Borda de input:** `rgb(var(--slate-5))` → no dark fica sutil, no light fica visível ✅
- **Texto:** `rgb(var(--slate-12))` → no dark fica branco, no light fica preto ✅
- **Texto secundário:** `rgb(var(--slate-11))` ✅
- **Texto placeholder:** `rgb(var(--slate-9))` ✅

> [!IMPORTANT]
> **NUNCA** use `color: #fff` ou `color: white` em texto de inputs — isso some no light mode. Sempre `rgb(var(--slate-12))`.

---

## 🎨 Paleta de Cores — Dark Mode (Legado)

Mantida para compatibilidade com componentes antigos que ainda não foram migrados.

### Fundos (dark)
| Uso | Valor |
| --- | --- |
| Fundo de página / modal backdrop | `#0a0c10` |
| Fundo de card / container principal | `rgba(255,255,255,0.03)` |
| Fundo de input | `rgba(0,0,0,0.2)` |
| Fundo hover de item | `rgba(255,255,255,0.04)` |

### Bordas (dark)
| Uso | Valor |
| --- | --- |
| Borda de card principal | `rgba(255,255,255,0.07)` |
| Borda de input padrão | `rgba(255,255,255,0.10)` |
| Borda de input focus | `#3b82f6` |

---

## ☀️ Paleta de Cores — Light Mode (Padrão Novo)

Todo componente novo deve usar este padrão. Migrar os antigos progressivamente.

### Fundos (light)
| Uso | Variável CSS | Valor aproximado no light |
| --- | --- | --- |
| Fundo de página | `rgb(var(--slate-1))` | Branco puro |
| Fundo de card | `rgb(var(--slate-2))` | Branco quase puro |
| Fundo de input | `rgb(var(--slate-2))` | Branco quase puro |
| Hover leve | `rgb(var(--slate-3))` | Cinza claríssimo |
| Divisor / info box | `rgb(var(--slate-3))` com `border: rgb(var(--slate-4))` | Cinza muito claro |

### Bordas (light)
| Uso | Variável CSS |
| --- | --- |
| Borda de card | `rgb(var(--slate-4))` |
| Borda de input padrão | `rgb(var(--slate-5))` |
| Borda de input focus | `rgb(var(--blue-8))` |
| Borda de input focus (alternativa) | `#3b82f6` |

### Texto (light — mesmas variáveis, funciona nos dois temas)
| Uso | Variável CSS |
| --- | --- |
| Título principal | `rgb(var(--slate-12))` |
| Texto de corpo | `rgb(var(--slate-11))` |
| Label de campo | `rgb(var(--slate-11))` peso 500 |
| Texto auxiliar / meta | `rgb(var(--slate-9))` |
| Placeholder | `rgb(var(--slate-9))` |

---

## 📝 Padrão: Inputs de Formulário

### ✅ Padrão correto (funciona em dark E light)

```css
.form-input {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 10px 14px;
  color: rgb(var(--slate-12));
  font-size: 14px;
  width: 100%;
  outline: none;
  transition: border-color 0.15s, background 0.15s;
  /* ⛔ PROIBIDO: box-shadow em inputs */
}
.form-input:focus {
  border-color: rgb(var(--blue-8));
  background: rgb(var(--slate-1));
  /* ⛔ PROIBIDO: box-shadow no focus */
}
.form-input::placeholder {
  color: rgb(var(--slate-9));
}
```

### ❌ Anti-padrão de input (NÃO FAZER)

```css
/* ❌ hardcoded dark — some no light mode */
.bad-input {
  background: rgba(0, 0, 0, 0.2);
  color: #fff;
  border: 1px solid rgba(255, 255, 255, 0.10);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06); /* ❌ PROIBIDO */
}
.bad-input:focus {
  box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.12); /* ❌ PROIBIDO */
}
```

**Regras absolutas para inputs:**
- `box-shadow: none` — sempre. Zero sombra, zero glow, zero ring.
- `border-radius: 8px` — nunca menos, nunca mais para inputs normais.
- Placeholder sempre em `rgb(var(--slate-9))`.
- `color: rgb(var(--slate-12))` — nunca `#fff` ou `white`.
- `background: rgb(var(--slate-2))` — nunca `rgba(0,0,0,0.2)`.
- Para `<select>`, adicionar `appearance: none` com seta SVG via `background-image`.

---

## 📐 Tokens de Espaçamento e Tamanho

| Elemento | Valor |
| --- | --- |
| Gap entre seções/cards grandes | `20px` |
| Gap interno de campos num card | `16px` |
| Padding interno de card | `20px` (lateral) `16px` (topo) |
| Padding de body de seção colapsável | `0 20px 20px` |
| Border-radius de card | `12px` |
| Border-radius de ícone de seção | `9px` (quadrado) |
| Border-radius de input | `8px` |
| Border-radius de badge/pill | `99px` (full) |
| Border-radius de modal | `16–20px` |
| Largura do ícone de seção | `36×36px` |
| Tamanho de label de campo | `13px`, peso `500` |
| Tamanho de texto de input | `14px` |

---

## 📏 Sistema de Arredondamentos

- **Cards de conteúdo principal:** `12px` (`rounded-xl`). Nunca `rounded-2xl` ou `rounded-3xl`.
- **Botões principais/secundários:** `8px` (`rounded-lg`).
- **Pills e Badges:** `border-radius: 99px` — apenas para status, tags e contadores.
- **Ícones de seção (quadrados):** `9px`.
- **Modais:** `16px` (modais pequenos) a `20px` (modais de câmera / mídia).

---

## 🔠 Tipografia e Hierarquia

| Nível | Uso |
| --- | --- |
| Título de aba/página | `font-size: 18-20px`, `font-weight: 600`, `color: rgb(var(--slate-12))` |
| Subtítulo de aba | `font-size: 13px`, `color: rgb(var(--slate-9))` |
| Título de seção colapsável | `14px font-semibold` |
| Label de campo | `13px font-medium color: rgb(var(--slate-11))` |
| Label de subseção | `11px uppercase tracking-wider color: rgb(var(--slate-9))` |

**Regras:**
- Nunca `font-bold` em títulos de subtelas — `font-semibold` é o máximo.
- Nunca `text-2xl` ou maior em corpo de aba.
- Hierarquia por tamanho + opacidade, nunca por bordas coloridas.

---

## 🖱️ Botões

| Classe | Quando usar |
| --- | --- |
| `.btn-primary` | Ação principal da aba (Salvar, Confirmar) |
| `.btn-secondary` | Ações secundárias (Visualizar, Cancelar) |
| `.btn-xs` | Botões de ação inline dentro de cards |

**Regras absolutas:**
- `box-shadow: none` sempre — zero glow, zero sombra colorida.
- Nunca usar `bg-blue-600` diretamente — sempre `.btn-primary`.

---

## 🃏 Anatomia de um Card de Seção

```
┌──────────────────────────────────────────────────────┐
│ [ícone 36px] Título da Seção                         │
│              Subtítulo descritivo                    │
│                                                  [v] │
├──────────────────────────────────────────────────────┤
│                                                      │
│  [campos, grids, checkboxes, toggles]                │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### Dark Mode
- **Borda:** `1px solid rgba(255,255,255,0.07)`
- **Background:** `rgba(255,255,255,0.03)`
- **Border-radius:** `12px`

### Light Mode
- **Borda:** `1px solid rgb(var(--slate-4))`
- **Background:** `rgb(var(--slate-2))`
- **Border-radius:** `12px`
- **Box-shadow:** ❌ PROIBIDO

---

## 📋 Padrão: Formulários com Seções Colapsáveis (`reg-*`)

### Princípio
- Dividir em blocos temáticos colapsáveis.
- Seções mais importantes abertas por padrão; secundárias fechadas.
- Chevron animado indica estado de expand/collapse.

> [!IMPORTANT]
> O `.reg-section-body` usa `padding: 20px` **uniforme** — nunca `padding: 0 20px 20px`.
> Omitir o padding-top faz o conteúdo colidir com a linha divisória do cabeçalho.

### Classes (`reg-*`)

| Classe | Função |
| --- | --- |
| `.reg-form-grid` | `flex-column`, `gap: 20px` |
| `.reg-section` | Card colapsável — borda + bg sutis + `overflow: hidden` |
| `.reg-section-toggle` | `<button>` full-width, flex, `justify-content: space-between` |
| `.reg-section-toggle-left` | Flex-row com ícone + textos |
| `.reg-section-icon` | `36×36px`, `border-radius: 9px`, colorido por tipo |
| `.reg-icon-blue/green/amber/purple` | Variantes de cor semântica |
| `.reg-section-title` | `14px font-semibold` |
| `.reg-section-subtitle` | `12px color: rgb(var(--slate-9))` |
| `.reg-chevron` | Ícone com `transition: transform 0.2s ease` |
| `.reg-chevron-open` | `transform: rotate(180deg)` |
| `.reg-section-body` | **`padding: 20px`** (uniforme), `flex-column`, `gap: 16px`, `border-top` sutil |
| `.reg-field-grid-2` | `grid 2 colunas`, `gap: 14px` |
| `.reg-field-grid-3` | `grid 3 colunas`, `gap: 14px` |
| `.reg-divider` | `height: 1px`, `rgb(var(--slate-4))` |
| `.reg-subsection-label` | Label de grupo de campos `11px uppercase` |

---

## 🌡️ Info Boxes e Notas

Para caixas de informação dentro de cards (ex: "Campos do sistema são obrigatórios..."):

```css
/* ✅ Correto — funciona em dark E light */
.info-note-box {
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  padding: 12px;
}
```

```html
<!-- ❌ NUNCA FAZER — hardcoded dark, vira barra preta no light -->
<div class="bg-slate-800/40 border border-slate-700/50 ...">
<!-- ✅ FAZER — usa classe CSS com variáveis -->
<div class="info-note-box ...">
```

---

## 🏷️ Padrão: Badges de Status / Tag

```html
<span class="status-badge status-badge--amber">Somente leitura</span>
```

**Cores corretas para AMBOS os temas:**

| Estado | Background | Texto |
| --- | --- | --- |
| Sucesso / Pago | `rgba(22,163,74,0.12)` | `#16a34a` |
| Erro / Falta | `rgba(220,38,38,0.12)` | `#dc2626` |
| Atenção / Pendente | `rgba(217,119,6,0.12)` | `#d97706` |
| Info | `rgba(59,130,246,0.12)` | `#2563eb` |

**Regras:**
- `font-size: 11px`, `font-weight: 600`, `border-radius: 99px`, `padding: 2px 8px`.
- Nunca usar a cor pura (`#16a34a` como background) — sempre versão com opacidade.
- Nunca usar cores dark-only como `#34d399`, `#f87171`, `#fbbf24` — são legíveis apenas no dark.

---

## 🗂️ Padrão: Cabeçalho de Aba (Header)

```
[Título h3]                    [meta texto]  [btn secundário]  [btn primário]
[Subtítulo p]
```

```html
<div class="reg-header mb-5">
  <div>
    <h3 class="text-xl font-semibold" style="color: rgb(var(--slate-12))">Título da Aba</h3>
    <p class="text-sm" style="color: rgb(var(--slate-9))">Subtítulo descritivo.</p>
  </div>
  <div class="flex items-center gap-3">
    <button class="btn-secondary flex items-center gap-2">Ação Secundária</button>
    <button class="btn-primary flex items-center gap-2">Ação Principal</button>
  </div>
</div>
```

---

## 🎥 Padrão: Modal Premium

```
backdrop: bg-black/75 backdrop-blur-md
          clique fora fecha (v-if + @click.self)
container: border-radius 16-20px, max-width definida
header:    ícone 34px + título/subtítulo + botão X 32px
body:      padding 20-24px
footer:    btns alinhados à direita com gap-3
```

**Cores de fundo do modal:**
- **Dark mode:** `#111318` ou `rgb(var(--slate-2))`
- **Light mode:** `rgb(var(--slate-1))` — branco limpo

**Regras críticas:**
- Nunca altura fixa no body — use `max-height` + `overflow-y: auto`.
- Botões de ação: `btn-secondary` (cancelar) e `btn-primary` (confirmar).

---

## 🎨 Filosofia de Uso de Cores

> Lema: **"Cores têm custo. Use-as quando informam, não quando decoram."**

### Cor Primária: Azul

O azul é **a única cor de acento primário** do projeto:

| Uso | Valor (dark/light compatível) |
| --- | --- |
| Tab ativa (underline) | `#3b82f6` |
| Input em foco (borda) | `rgb(var(--blue-8))` |
| Botão primário | `bg-woot-600 hover:bg-woot-500` |
| Hover de botão de ação | `rgba(59,130,246,0.10)` com borda `rgba(59,130,246,0.20)` |
| Badge de link/referência | `rgba(59,130,246,0.08)` + `rgb(var(--blue-9))` |

### Cores Semânticas

| Cor | Uso permitido | Proibido |
| --- | --- | --- |
| 🟢 Verde | Sucesso confirmado, status PAGO | Destacar valores aleatoriamente |
| 🟡 Âmbar | Alertas de atenção, datas próximas | Labels de seção, decoração |
| 🔴 Vermelho | Falta do paciente, erros críticos | Linhas padrão da tabela |
| 🔵 Azul | Navegação ativa, links, botões primários | Excesso de tons de azul |

---

## 🗓️ Padrão: Aba Agenda e Configurações

> [!IMPORTANT]
> A aba de configurações da agenda (`settings/Index.vue`) foi auditada extensivamente.
> Use as lições abaixo para qualquer novo desenvolvimento na agenda.

### Lições aprendidas — o que estava errado (e foi corrigido)

| Problema | Causa | Correção aplicada |
| --- | --- | --- |
| Inputs muito escuros no light | `background: rgb(var(--slate-4))` | `background: rgb(var(--slate-2))` |
| Texto sumindo no light | `color: #fff` hardcoded | `color: rgb(var(--slate-12))` |
| Barra preta "Campos do formulário" | `class="bg-slate-800/40"` | `.info-note-box` com `--slate-3` |
| Sombras pesadas em todos os inputs | `box-shadow: 0 0 0 2px...` | Sombras completamente removidas |
| Badges de status ilegíveis no light | `#34d399`, `#f87171` dark-only | `#16a34a`, `#dc2626` legíveis em ambos |
| Chips de variável ilegíveis | `background: #1e1f3c` | `rgba(99,102,241,0.10)` |
| Preview bubble escuro | `background: #1a2f1a` | Verde semitransparente |
| Botão ativo da IA preto | `background: #2a1e3c` | `rgba(124,58,237,0.10)` |
| Select de agente escuro | `--slate-4` como fundo | `--slate-2` + borda `--slate-5` |
| Datepicker input escuro | `--slate-4` + `--slate-6` | `--slate-2` com `box-shadow: none` |

### Regras específicas da Agenda

- **Horários de funcionamento:** inputs com `rgb(var(--slate-2))`, borda `--slate-5`, sem sombra.
- **Selector de exceções:** `rgb(var(--slate-2))` fundo, hover `--slate-3`, focus border `--blue-8`.
- **Datepicker:** `box-shadow: none !important` — o componente de terceiro tenta impor sombra.
- **Campos do formulário (online scheduling):** usar `.info-note-box` para a nota, jamais classes Tailwind dark hardcoded.
- **Badges de duração/sala:** usar `rgb(var(--blue-9))` e `#7c3aed` — legíveis em ambos os temas.
- **Dia de hoje no calendário:** usar fundo `rgb(var(--blue-9))` com texto branco — nunca texto azul em fundo preto.

---

## ❌ Anti-Padrões — O que NUNCA fazer

| Proibido | Motivo |
| --- | --- |
| `box-shadow` em inputs, fields, cards de form | Causa aspecto pesado e "flutuante" inadequado |
| `box-shadow` colorida em botões | Cria glow artificial, viola o flat design |
| `hover:-translate-y-1` em cards | Animação de flutuação é infantil para software clínico |
| `hover:shadow-lg` ou `hover:shadow-2xl` | Sombras pesadas no hover quebram a leveza visual |
| `style="..."` inline no template Vue | Viola regras ESLint do projeto |
| Emojis como ícone de UI | **NUNCA.** Usar Phosphor (`i-ph-*`) ou Lucide (`i-lucide-*`) — emojis variam por OS, são inacessíveis e transmitem informalidade |
| Strings de UI em inglês | O projeto é em **pt-BR**. `en.json` armazena os textos, mas os valores são em português |
| `font-bold` em títulos de aba | `font-semibold` é o máximo permitido |
| `text-2xl` ou maior em subtelas | Reservado para sidebar de contexto |
| `color: #fff` em qualquer texto de input | Some no light mode |
| `background: rgba(0,0,0,0.2)` em input | Fica preto no light mode |
| `bg-slate-800/40`, `bg-slate-700/50` | Hardcoded dark — vira barra preta no light |
| Cores dark-only como `#34d399`, `#f87171` em badges | Ilegíveis no light (claro sobre claro) |
| `color: #1e1f3c` backgrounds | Roxo escuro hardcoded, some no light |
| Heights fixas em viewfinders/modais | Usar `aspect-ratio` para manter proporção |
| Múltiplas versões do mesmo componente | Um padrão, uma implementação |
| Placeholder com cor muito clara | Usar `rgb(var(--slate-9))` — entre visível e discreto |
| `border: 1px solid rgba(255,255,255,0.12)` em elementos light | Borda invisível no light mode |

---

## ✅ Checklist para todo componente novo

Antes de commitar qualquer UI, verifique:

- [ ] Todos os inputs têm `background: rgb(var(--slate-2))`?
- [ ] Todos os inputs têm `color: rgb(var(--slate-12))`?
- [ ] Todos os inputs têm `border: 1px solid rgb(var(--slate-5))`?
- [ ] Nenhum input tem `box-shadow` (default ou focus)?
- [ ] Nenhuma cor hardcoded dark (`#0a0c10`, `rgba(0,0,0,0.2)`, `rgba(255,255,255,0.X)`) em componentes dual-theme?
- [ ] Nenhuma classe Tailwind dark-opaca (`bg-slate-800/40`) em elementos que renderizam no light?
- [ ] Badges de status usam cores legíveis em ambos os temas (`#16a34a`, `#dc2626`, `#d97706`)?
- [ ] Info boxes usam `.info-note-box` (ou equivalente com `--slate-3`/`--slate-4`)?
- [ ] Dia atual do calendário tem fundo sólido (não texto colorido em fundo preto)?
- [ ] Botões têm `box-shadow: none`?

---

## 🔁 Como Aplicar em Novas Abas (Light Mode)

1. **Cabeçalho:** `reg-header` com título `--slate-12` + subtítulo `--slate-9` + ações.
2. **Conteúdo:** `reg-form-grid` com seções `reg-section` colapsáveis.
3. **Ícone de seção:** Cor semântica (azul=info, verde=contato, âmbar=localização).
4. **Campos:** `.form-group` + `<label>` + input com `--slate-2` bg, `--slate-5` borda, `--slate-12` texto.
5. **Info box:** `.info-note-box` com `--slate-3` bg e `--slate-4` borda.
6. **Badges:** sempre com versão translúcida do background e cor sólida no texto.
7. **Estado desabilitado:** `:disabled` + `opacity: 0.5` — o CSS cuida do visual.

*Consulte a aba Cadastro (`Record.vue`) como referência visual mestra para dark mode.*
*Consulte `settings/Index.vue` (após auditoria) como referência para dual-theme.*

---

## 🏗️ Arquitetura CSS por Módulo — Regra Obrigatória

> **NUNCA adicione estilos em arquivos monolíticos como `Record.vue` (17k linhas).** Criar um CSS separado por módulo/feature é OBRIGATÓRIO.

### Regra de organização de arquivos CSS

Cada área funcional deve ter seu próprio arquivo CSS importado no `<script setup>`:

```
patients/
├── Index.vue                  ← importa patients-index.css
├── patients-index.css         ← estilos da lista de pacientes
├── Record.vue                 ← importa record.css
├── record.css                 ← estilos do prontuário (DUAL-THEME)
└── tabs/
    ├── RegistrationTab.vue    ← pode importar registration.css quando crescer
    └── ...
```

### Como importar

```javascript
// No <script setup> do componente
import './record.css';
```

> O CSS importado via `<script setup>` não é scoped — gera regras globais, o que é desejado para `!important` overrides de tema funcionarem.

---

## 🌓 Guia Prático: Implementar Light Mode em Componente Legado

> Seção baseada na experiência real de converter o `Record.vue` (prontuário completo) para dual-theme.

### Passo 1 — Identificar o mecanismo de tema

O BeClinic adiciona/remove a classe `.dark` no `document.body`:

```javascript
// themeHelper.js
document.body.classList.add('dark');    // dark mode ativado
document.body.classList.remove('dark'); // light mode ativado
```

Use isso no CSS:

- `.minha-classe` com `rgb(var(--slate-N))` → adapta em ambos os temas ✅
- `body:not(.dark) .minha-classe` → aplica APENAS no light mode
- `body.dark .minha-classe` → aplica APENAS no dark mode

### Passo 2 — Prefixos por feature (evitar conflitos globais)

| Feature | Prefixo | Exemplos |
| --- | --- | --- |
| Prontuário geral | `record-` | `.record-modal-box` |
| Financeiro | `fin-` | `.fin-kpi-card`, `.fin-tx-table` |
| Exames e Imagens | `exams-` | `.exams-card`, `.exams-thumb` |
| Agenda/Histórico | `sched-` | `.sched-apt-card` |
| Timeline | `tl-` | `.tl-event-card` |
| Auditoria | `aud-` | `.aud-table-row` |
| Consentimentos | `consent-` | `.consent-canvas` |
| Evolução | `evo-` | `.evo-note-card` |
| Registro/Cadastro | `reg-` | `.reg-section` |
| Modais do prontuário | `record-modal-` | `.record-modal-input` |

### Passo 3 — Estratégia para classes Tailwind dark hardcoded

Quando o template usa `bg-slate-900`, `bg-slate-800`, `text-slate-100` e você não pode editar facilmente o template, use `body:not(.dark)` no CSS para sobrescrever no light mode:

```css
/* Modais com bg-slate-900 ficam brancos no light mode */
body:not(.dark) .bg-slate-900 {
  background-color: rgb(var(--slate-1)) !important;
}
body:not(.dark) .bg-slate-800 {
  background-color: rgb(var(--slate-2)) !important;
}
body:not(.dark) .border-slate-700,
body:not(.dark) [class*="border-slate-700/"] {
  border-color: rgb(var(--slate-4)) !important;
}
body:not(.dark) .text-slate-100 { color: rgb(var(--slate-12)) !important; }
body:not(.dark) .text-slate-400 { color: rgb(var(--slate-9)) !important; }
```

> **ATENÇÃO:** Esses overrides são globais. Quando possível, escope por contexto (`.record-container .bg-slate-900`) para evitar afetar outros componentes.

### Passo 4 — NUNCA usar `style=""` inline no Vue

O ESLint do projeto **proíbe** `style=""` inline. Use classes customizadas:

```html
<!-- ❌ PROIBIDO — style="" inline -->
<div style="background: rgb(var(--slate-1)); border-color: rgb(var(--slate-4));">

<!-- ✅ CORRETO — classe customizada em record.css -->
<div class="record-modal-box">
```

```css
/* record.css */
.record-modal-box {
  background: rgb(var(--slate-1)) !important;
  border-color: rgb(var(--slate-4)) !important;
}
```

### Passo 5 — Grep para encontrar problemas

```bash
# Encontrar classes Tailwind dark hardcoded em templates Vue
grep -n "bg-slate-[789]\|bg-slate-800\|border-slate-[67]\|text-slate-[123]\|text-white\|style=\"" Component.vue | grep -v "<!--"
```

---

## 🩺 Sistema de Classes `record-modal-*`

Classes criadas para modais do prontuário que substituem Tailwind dark hardcoded.
Definidas em `record.css` e usadas nos templates para evitar `style=""` proibido:

| Classe | Propriedades |
| --- | --- |
| `.record-modal-box` | `background: rgb(var(--slate-1))`, `border-color: rgb(var(--slate-4))` |
| `.record-modal-title` | `color: rgb(var(--slate-12))` |
| `.record-modal-label` | `color: rgb(var(--slate-9))` |
| `.record-modal-input` | `bg: --slate-2`, `border: --slate-5`, `color: --slate-12` |
| `.record-modal-preview` | `background: rgb(var(--slate-3))`, `border: rgb(var(--slate-4))` |
| `.record-modal-muted` | `color: rgb(var(--slate-9))` |

```html
<!-- ❌ ANTES — Tailwind dark hardcoded -->
<div class="bg-slate-900 border border-slate-700/60 rounded-2xl">
  <h3 class="text-slate-100">Título</h3>
  <input class="bg-slate-800 border-slate-600 text-slate-200" />
</div>

<!-- ✅ DEPOIS — dual-theme automático -->
<div class="record-modal-box rounded-2xl">
  <h3 class="record-modal-title">Título</h3>
  <input class="record-modal-input" />
</div>
```

---

## 🔍 Checklist de Auditoria de Light Mode

Ao auditar uma aba/componente verificar **nesta ordem**:

### Fundos e cards

- [ ] Fundo da aba/página usa `rgb(var(--slate-1))`?
- [ ] Cards usam `rgb(var(--slate-2))` com borda `rgb(var(--slate-4))`?
- [ ] Hover de cards usa `rgb(var(--slate-3))`?

### Tipografia

- [ ] Títulos usam `rgb(var(--slate-12))`?
- [ ] Textos secundários usam `rgb(var(--slate-9))`?
- [ ] Nenhum texto usa `#fff`, `white` ou `rgba(255,255,255,X)`?

### Inputs e formulários

- [ ] Todos os inputs têm `bg: --slate-2`, `border: --slate-5`, `color: --slate-12`?
- [ ] Zero `box-shadow` em qualquer input?

### Modais e pop-ups

- [ ] Fundo usa `rgb(var(--slate-1))` (não `bg-slate-900`)?
- [ ] Borda usa `rgb(var(--slate-4))` (não `border-slate-700`)?
- [ ] Nenhum `style=""` inline com variáveis CSS?

### KPIs e badges

- [ ] KPI sucesso: `rgba(22,163,74,0.07)` + `#16a34a`
- [ ] KPI erro: `rgba(220,38,38,0.07)` + `#dc2626`
- [ ] KPI atenção: `rgba(217,119,6,0.07)` + `#d97706`
- [ ] KPI info: `rgba(59,130,246,0.07)` + `#2563eb`

### Empty states

- [ ] Ícone em container `--slate-3` com borda `--slate-4`?
- [ ] Texto principal `--slate-9`, texto auxiliar `--slate-8`?

---

## 🚨 Lições Aprendidas — Auditoria do Prontuário

| Problema Visual | Causa | Solução |
| --- | --- | --- |
| Quadrado cinza em "Retorno Indicado" | `.evo-retorno` com `background` dark | `background: transparent; border: none` |
| Pop-ups de pasta pretos | `bg-slate-900 border-slate-700/60` no template | Classe `.record-modal-box` com `--slate-1` |
| Inputs do modal de Lock pretos | `class="bg-slate-800 border-slate-600"` inline | `body:not(.dark) input.bg-slate-800` override |
| Preview de PDF escuro | `.exams-thumb-pdf` sem variáveis CSS | `linear-gradient(rgba(220,38,38,0.06))` |
| Modal de documentos preto | Fundo hardcoded `#111318` via template | `.docs-modal { background: rgb(var(--slate-1)) }` |
| Upload de arquivos escuro | `border-slate-600.border-dashed` | `body:not(.dark)` override |
| Financeiro/Auditoria quebrados | `.fin-*` e `.aud-*` sem light mode | Classes criadas integralmente no `record.css` |
| `style=""` rejeitado pelo ESLint | ESLint proíbe inline style em Vue | Criadas classes `.record-modal-*` em `record.css` |
# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: Manage Ruby via `rbenv` and install the version listed in `.ruby-version` (e.g., `rbenv install $(cat .ruby-version)`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- MVP focus: Least code change, happy-path only
- No unnecessary defensive programming
- Ship the happy path first: limit guards/fallbacks to what production has proven necessary, then iterate
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## Project-Specific

- **Translations**:
  - Only update `en.yml` and `en.json`
  - Other languages are handled by the community
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.
