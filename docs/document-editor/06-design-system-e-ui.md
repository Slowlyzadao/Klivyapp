# 06 — Design System & UI

> Toda UI segue o padrão atual do Klivy. Cores e tokens semânticos vêm de [`plugins/patients/frontend/styles/_variables.scss`](../../plugins/patients/frontend/styles/_variables.scss) (que estende o tema base `rgb(var(--slate-N))` dual-mode).

## 6.1 Princípios de UX

1. **3 cliques regra**: do menu até um template editável em no máximo 3 cliques.
2. **Tela vazia ≠ tela morta**: estado vazio sempre tem CTA + atalho pros modelos Klivy.
3. **Salvamento autopilot**: debounce silencioso, sem botão "Salvar" gigante.
4. **Variável visível**: chips sempre distinguíveis visualmente (cor secundária, ícone).
5. **Mobile não bloqueia**: tela funciona em mobile (read-only), edição é desktop.

## 6.2 Tela 1 — Biblioteca de Templates (DocumentsIndex.vue)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ [☰] Klivy Dev                                                          [user ▼] │
├─────────┬───────────────────────────────────────────────────────────────────────┤
│         │                                                                       │
│ Sidebar │  Documentos                                                           │
│         │  ┌─────────────────────────────────────────────────────────────────┐ │
│ ▸ Caixa │  │ [🔍 Buscar template...]    [Tipo: Todos ▼]   [+ Novo Template] │ │
│ ▸ Conv. │  └─────────────────────────────────────────────────────────────────┘ │
│ ▸ BEA   │                                                                       │
│ ▸ Agenda│  ┌──────────────┬────────────────────────────────────────────────────┐│
│ ▸ Telec.│  │ 📁 PASTAS    │  📚 Modelos Klivy        [Ver biblioteca completa →]│
│ ▸ Pacie.│  │              │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐               │
│ ▸ Docs ●│  │ 📂 Todos     │  │ 📄   │ │ 📄   │ │ 📄   │ │ 📄   │               │
│ ▸ Finan.│  │ 📂 Clínicos  │  │Atest.│ │Receit│ │Cont. │ │Cons. │               │
│ ▸ Relat.│  │ 📂 Estética  │  │Padrão│ │Padrão│ │Trat. │ │ LGPD │               │
│ ▸ Campa.│  │ 📂 Consent.  │  └──────┘ └──────┘ └──────┘ └──────┘               │
│ ▸ Confi.│  │ 📂 Contratos │                                                     │
│ ▸ Ajuda │  │              │  📂 Pasta atual: Estética                           │
│         │  │ [+ Nova past]│  ┌────────────────────────────────────────────────┐ │
│         │  │              │  │ Nome           Tipo         Atualizado   ⋮    │ │
│         │  │              │  ├────────────────────────────────────────────────┤ │
│         │  │              │  │ 📄 Consent...  Toxina Bot.  há 2 dias    ⋮    │ │
│         │  │              │  │ 📄 Contrato... Contrato     há 1 sem.    ⋮    │ │
│         │  │              │  │ 📄 Termo Im... Cons. Imagem há 1 mês     ⋮    │ │
│         │  │              │  └────────────────────────────────────────────────┘ │
│         │  └──────────────┴────────────────────────────────────────────────────┘│
└─────────┴───────────────────────────────────────────────────────────────────────┘
```

**Elementos:**
- **Header**: busca textual + filtro por tipo + CTA "Novo Template"
- **Sidebar esquerda interna**: lista de pastas da clínica + "+ Nova pasta"
- **Seção horizontal "Modelos Klivy"**: 4-6 cards horizontalmente roláveis. Click → drawer com biblioteca completa
- **Grid/Lista principal**: templates da pasta selecionada. Toggle entre grid (cards) e lista (tabela)
- **Card de template**: thumbnail (1ª página do PDF preview), nome, tipo, badge se Klivy/cloned, menu ⋮ (editar, duplicar, mover, arquivar)
- **Estado vazio**: ilustração + "Comece com um modelo Klivy" + botão

**Tokens visuais (SCSS):**

```scss
// styles/index/_template-card.scss
@use '../variables' as *;

.template-card {
  display: flex;
  flex-direction: column;
  background: rgb(var(--white));
  border: 1px solid rgb(var(--slate-3));
  border-radius: 12px;
  padding: 16px;
  transition: border-color 120ms, transform 120ms, box-shadow 120ms;
  cursor: pointer;

  &:hover {
    border-color: rgb(var(--slate-5));
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.06);
  }

  &__thumbnail {
    aspect-ratio: 8.5 / 11;     // proporção A4
    background: rgb(var(--slate-1));
    border-radius: 8px;
    margin-bottom: 12px;
    overflow: hidden;
  }

  &__title {
    font-size: 0.9375rem;
    font-weight: 600;
    color: rgb(var(--slate-12));
    margin: 0;
  }

  &__badges {
    display: flex; gap: 6px; margin-top: 8px;
  }

  &__badge {
    font-size: 0.75rem;
    padding: 2px 8px;
    border-radius: 999px;
    font-weight: 500;

    &--klivy   { background: rgba($brand-purple-bright, 0.12); color: $brand-purple; }
    &--cloned  { background: rgba($brand-info-bright, 0.12);   color: $brand-info; }
    &--clinic  { background: rgba($brand-success-bright, 0.12); color: $brand-success; }
  }

  &__menu { /* botão ⋮ */ }
}
```

## 6.3 Tela 2 — Editor de Template (TemplateEditor.vue)

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ ← Voltar  │  📄 Contrato de Tratamento Estético            [v3] [💾 Salvo agora]│
├───────────┴────────────────────────────────────────────────────┬────────────────┤
│ [B] [I] [U]  [H1▼] [📐▼]  [• Lista]  [Tabela]  [/ Variável]   │ ▸ Configurações│
│ [Aa Fonte▼]  [Cor▼]  [Alinhar▼]  [Link]                       │ Nome: ____     │
├────────────────────────────────────────────────────────────────│ Tipo: Contrato │
│                                                                │ Pasta: Estét.  │
│   ┌──────────────────────────────────────────────────────┐    │ Papel: A4      │
│   │ [LOGO DA CLÍNICA — variável imagem]                  │    │ Orient.: Retra │
│   │                                                       │    │                │
│   │ Eu, [Nome do paciente], inscrito(a) no CPF           │    │ ▸ Variáveis    │
│   │ [CPF do paciente], residente em [Endereço completo], │    │ [🔍 Buscar...]│
│   │ DECLARO ter sido informado(a)...                     │    │                │
│   │                                                       │    │ 👤 Paciente    │
│   │ Pelo presente termo, autorizo [Nome da clínica],     │    │ ▢ Nome         │
│   │ CNPJ [CNPJ da clínica], a realizar o procedimento... │    │ ▢ CPF          │
│   │                                                       │    │ ▢ RG           │
│   │ [Cidade, data por extenso]                            │    │ ▢ Data nasc... │
│   │                                                       │    │                │
│   │ _________________________                             │    │ 🏥 Clínica     │
│   │ [Nome do paciente]                                    │    │ ▢ Nome         │
│   │                                                       │    │ ▢ CNPJ         │
│   │ _________________________                             │    │                │
│   │ [Nome do profissional] - [CRM/CRO]                    │    │ 👨‍⚕️ Profissional│
│   │                                                       │    │ 📅 Data        │
│   └──────────────────────────────────────────────────────┘    │                │
│   ─────────────────────────────────────────────────  página 1  │ ▸ Pré-visualizar│
│                                                                │  [Ver com paciente teste ▼]│
└────────────────────────────────────────────────────────────────┴────────────────┘
```

**Elementos:**
- **Header fino**: voltar, nome (editável inline), versão, status de save, atalhos
- **Toolbar TipTap**: agrupada (formatação básica, headings, listas, tabelas, variável, alinhamento, link, cor)
- **Canvas A4 simulado**: borda fina, sombra, padding interno conforme margens (PaperContainer.vue)
- **Variáveis** renderizadas como chips coloridos `[Nome do paciente]`
- **Painel lateral direito**: aba "Configurações" (nome, tipo, pasta, papel, orientação) + aba "Variáveis" (catálogo organizado, clicar insere no editor)
- **Footer flutuante**: indicador de página, contador de caracteres
- **Pré-visualizar com paciente teste**: dropdown que escolhe um paciente fictício pra render preview com valores reais

**Modo focus opcional** (Fase 2): esconder sidebar interna deixando só o canvas.

## 6.4 Tela 3 — Drawer "Biblioteca Klivy completa"

```
┌──────────────────────────────────────────────────────────┐  ← painel deslizando da direita
│ ← Modelos Klivy                                      [X] │
├──────────────────────────────────────────────────────────┤
│ [🔍 Buscar nos modelos...]                               │
│                                                          │
│ Filtrar por categoria:                                   │
│ [Todos] [Clínicos] [Estética] [Cirúrgicos] [Consent.]   │
│                                                          │
│ ┌────────┐ ┌────────┐ ┌────────┐                         │
│ │ 📄     │ │ 📄     │ │ 📄     │                         │
│ │Atest.  │ │Receit. │ │Pedido. │                         │
│ │Padrão  │ │Médica  │ │Exame   │                         │
│ │[Usar]  │ │[Usar]  │ │[Usar]  │                         │
│ └────────┘ └────────┘ └────────┘                         │
│                                                          │
│ ┌────────┐ ┌────────┐ ┌────────┐                         │
│ │ 📄     │ │ 📄     │ │ 📄     │                         │
│ │Termo   │ │Termo   │ │Cons.   │                         │
│ │LGPD    │ │Imagem  │ │Toxina  │                         │
│ │[Usar]  │ │[Usar]  │ │[Usar]  │                         │
│ └────────┘ └────────┘ └────────┘                         │
│                  ...                                     │
└──────────────────────────────────────────────────────────┘
```

Ao clicar **[Usar]**, abre modal "Onde colocar?" (escolha de pasta) → clona o template Klivy pra conta → abre o editor com a cópia.

## 6.5 Tela 4 — Modal "Gerar Documento" (modificada no plugin patients)

Mostrado na seção [5.11 do frontend](05-frontend.md#511-integração-com-a-tela-atual-de-gerar-documento-do-paciente).

## 6.6 Padrão SCSS modular (reuso do padrão `plugins/patients/`)

### Entry point

```scss
// plugins/document_templates/frontend/styles/document-templates.scss
@use 'variables' as *;

@use 'index/index';
@use 'index/folder-sidebar';
@use 'index/template-grid';
@use 'index/template-card';

@use 'editor/editor';
@use 'editor/toolbar';
@use 'editor/variable-node';
@use 'editor/paper-container';
@use 'editor/picker-menu';

@use 'modals/modals';
```

### Variáveis locais (estende globais)

```scss
// _variables.scss
@forward '../../patients/frontend/styles/variables';  // herda brand colors

// Tokens específicos da feature
$editor-paper-bg: #ffffff;
$editor-paper-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
$editor-paper-margin: 20mm;
$variable-chip-bg-light: rgba($brand-info-bright, 0.12);
$variable-chip-bg-dark:  rgba($brand-info-bright, 0.20);
```

### Padrão de partial BEM

```scss
// editor/_toolbar.scss
@use '../variables' as *;

.editor-toolbar {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 8px 12px;
  border-bottom: 1px solid rgb(var(--slate-3));
  background: rgb(var(--white));
  position: sticky;
  top: 0;
  z-index: 10;

  &__group {
    display: flex; gap: 2px;

    + .editor-toolbar__group {
      border-left: 1px solid rgb(var(--slate-3));
      margin-left: 4px;
      padding-left: 4px;
    }
  }

  &__btn {
    display: inline-flex; align-items: center; justify-content: center;
    height: 32px; min-width: 32px;
    padding: 0 8px;
    border-radius: 6px;
    color: rgb(var(--slate-11));
    cursor: pointer;
    transition: background 80ms ease;

    &:hover    { background: rgb(var(--slate-2)); }
    &--active  { background: rgb(var(--slate-3)); color: rgb(var(--slate-12)); }
    &:disabled { opacity: .4; cursor: not-allowed; }

    &-icon { width: 16px; height: 16px; }
  }
}
```

## 6.7 Componentes reutilizáveis a criar

| Componente | Onde reusa | Estimativa |
|---|---|---|
| `PaperContainer.vue` | Editor (canvas A4) e Preview | 1h |
| `TemplateCard.vue` | Grid e Klivy drawer | 2h |
| `FolderItem.vue` | Sidebar de pastas | 1h |
| `EmptyState.vue` | Várias telas vazias | 1h |
| `VariablePickerMenu.vue` | "/" no editor + painel lateral | 3h |

> Antes de criar do zero, verificar `app/javascript/dashboard/components-next/` — se já houver `EmptyState`, `Card`, `Modal`, etc., reusar.

## 6.8 Acessibilidade (não negociável)

- Toda ação tem `aria-label`.
- Atalhos têm dica no tooltip.
- Foco visível em todos os controles (não escondemos outline).
- Editor TipTap já é ARIA-friendly por padrão.
- Cor não é o único indicador: chips de variável têm ícone também.

## 6.9 Dark mode

Klivy já roda dark mode via custom properties `rgb(var(--slate-N))`. Tudo que usar essas vars já vem grátis. Pra brand colors (`$brand-info`, etc.), usar versões `*-light` em dark mode:

```scss
.tiptap-variable-chip {
  background: rgba($brand-info-bright, 0.12);
  color: $brand-info;

  :where([data-theme='dark']) & {
    background: rgba($brand-info-bright, 0.20);
    color: $brand-info-light;
  }
}
```

## 6.10 Microinterações que valem a pena

- **Insert variável**: animação de "pop" do chip ao inserir (transform scale 0.9 → 1).
- **Salvamento**: ícone passa de relógio → check com fade de 200ms.
- **Drag de template entre pastas**: highlight da pasta de destino.
- **Hover em template Klivy**: mostra "Modelo Klivy — clique pra clonar".

Tudo via CSS transitions, sem libs.
