<script setup>
/**
 * Exportação para Contador — v2 (canon F-33 §parte 1).
 *
 * 4 CSVs separados por tipo (Receitas, Despesas, Comissões, Caixa)
 * cobrindo um período. Format BR-friendly (UTF-8 com BOM, separador `;`,
 * decimais com vírgula) — abre direto no Excel BR.
 *
 * Workflow:
 *   1. Usuário escolhe período (default: mês anterior, mais comum pro
 *      fechamento contábil).
 *   2. Preview mostra contagem de registros em cada CSV.
 *   3. Botões individuais "Baixar Receitas" / "Despesas" / etc.
 *
 * Permissão: ADMIN/AUDITOR (controller valida).
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import FinancialV2 from '../api/financialV2';
import '@plugins/financial/frontend/styles/financial.scss';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Default: mês ANTERIOR (caso de uso típico — fecha o mês anterior pro
// contador). Calcula 1º ao último dia do mês passado.
function previousMonthRange() {
  const now = new Date();
  const firstThis = new Date(now.getFullYear(), now.getMonth(), 1);
  const lastPrev = new Date(firstThis);
  lastPrev.setDate(0); // último dia do mês anterior
  const firstPrev = new Date(lastPrev.getFullYear(), lastPrev.getMonth(), 1);
  return {
    from: firstPrev.toISOString().slice(0, 10),
    to:   lastPrev.toISOString().slice(0, 10),
  };
}

const filters = ref({ ...previousMonthRange() });

const counts = ref({});
const previewLoading = ref(false);
const downloadingType = ref(null);

// Tipos exportáveis. `endpoint` = valor enviado no parâmetro `type`.
// `accent` = cor do badge de count.
const TYPES = [
  { key: 'receitas',  label: 'Receitas',           hint: 'Recibos pagos no período (received_at)',     icon: 'i-lucide-trending-up',   color: 'emerald' },
  { key: 'despesas',  label: 'Despesas',           hint: 'Despesas com competência no período',         icon: 'i-lucide-trending-down', color: 'ruby' },
  { key: 'comissoes', label: 'Comissões',          hint: 'Comissões de profissionais (devida/paga/estornada)', icon: 'i-lucide-percent', color: 'violet' },
  { key: 'caixa',     label: 'Movimentos do Caixa', hint: 'Todos lançamentos do fluxo (cash_date)',     icon: 'i-lucide-wallet',        color: 'blue' },
];

async function loadPreview() {
  if (!filters.value.from || !filters.value.to) return;
  previewLoading.value = true;
  try {
    const { data } = await FinancialV2.reports.accountantExportPreview({
      from: filters.value.from,
      to: filters.value.to,
    });
    counts.value = data?.counts || {};
  } catch (err) {
    notifyError(err?.response?.data?.error === 'forbidden'
      ? 'Acesso negado. Apenas ADMIN/AUDITOR podem exportar.'
      : 'Falha ao carregar preview.');
  } finally {
    previewLoading.value = false;
  }
}

async function downloadCsv(type) {
  downloadingType.value = type;
  try {
    const { data } = await FinancialV2.reports.accountantExport({
      from: filters.value.from,
      to: filters.value.to,
      type,
    });
    const fromTag = filters.value.from.replace(/-/g, '');
    const toTag = filters.value.to.replace(/-/g, '');
    const filename = `${type}_${fromTag}_a_${toTag}.csv`;

    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    notifySuccess(`${filename} baixado.`);
  } catch (err) {
    notifyError(err?.response?.data?.error || `Falha ao baixar ${type}.`);
  } finally {
    downloadingType.value = null;
  }
}

async function downloadAll() {
  // Baixa os 4 sequencialmente (browser geralmente bloqueia múltiplos
  // downloads simultâneos sem prompt).
  for (const t of TYPES) {
    if ((counts.value[t.key] || 0) > 0) {
      await downloadCsv(t.key);
    }
  }
}

watch(filters, loadPreview, { deep: true });
onMounted(loadPreview);

const totalRecords = computed(() =>
  TYPES.reduce((acc, t) => acc + (counts.value[t.key] || 0), 0),
);
const hasData = computed(() => totalRecords.value > 0);
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Exportação para Contador</h1>
        <p class="finv2-page__subtitle">
          Gera CSVs por tipo (Receitas, Despesas, Comissões, Caixa) num período,
          formatados pra abrir direto no Excel/Sheets em pt-BR
          (UTF-8 BOM, separador <code>;</code>, decimal vírgula).
        </p>
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- Período -->
      <div class="acc-v2__period">
        <div class="acc-v2__period-field">
          <span class="acc-v2__period-label">Data inicial</span>
          <DatePickerBR v-model="filters.from" placeholder="dd/mm/aaaa" />
        </div>
        <div class="acc-v2__period-field">
          <span class="acc-v2__period-label">Data final</span>
          <DatePickerBR v-model="filters.to" placeholder="dd/mm/aaaa" :min="filters.from || null" />
        </div>
        <BeclinicButton
          v-if="hasData"
          variant="solid"
          color="blue"
          icon="i-lucide-archive"
          label="Baixar todos"
          size="sm"
          :is-loading="!!downloadingType"
          @click="downloadAll"
        />
      </div>

      <!-- 4 cards, um por tipo -->
      <div class="acc-v2__grid">
        <article
          v-for="t in TYPES"
          :key="t.key"
          class="acc-v2__card"
        >
          <header class="acc-v2__card-header">
            <div class="acc-v2__card-icon" :class="`acc-v2__card-icon--${t.color}`">
              <i :class="t.icon" class="w-5 h-5" />
            </div>
            <div>
              <h3 class="acc-v2__card-title">{{ t.label }}</h3>
              <p class="acc-v2__card-hint">{{ t.hint }}</p>
            </div>
          </header>

          <div class="acc-v2__card-count">
            <span class="acc-v2__count-label">Registros no período</span>
            <strong v-if="!previewLoading" class="acc-v2__count-value">
              {{ counts[t.key] ?? 0 }}
            </strong>
            <span v-else class="acc-v2__count-loading">…</span>
          </div>

          <footer class="acc-v2__card-footer">
            <BeclinicButton
              variant="faded"
              :color="t.color === 'violet' || t.color === 'emerald' ? 'blue' : t.color"
              icon="i-lucide-download"
              :label="`Baixar CSV`"
              size="sm"
              :is-loading="downloadingType === t.key"
              :disabled="(counts[t.key] || 0) === 0 || previewLoading"
              @click="downloadCsv(t.key)"
            />
            <Badge
              v-if="(counts[t.key] || 0) === 0 && !previewLoading"
              label="Sem dados"
              color="slate"
              size="xs"
            />
          </footer>
        </article>
      </div>

      <!-- Nota -->
      <div class="acc-v2__note">
        <i class="i-lucide-info w-3.5 h-3.5" />
        <span>
          Os arquivos seguem o padrão pedido pelo contador: 1 linha por registro,
          colunas com data, valor, descrição, categoria, paciente e profissional.
          Decimais com vírgula (ex.: <code>1234,56</code>).
          <br>
          <strong>Período recomendado pra fechamento:</strong> 1º ao último dia do
          mês anterior (preenchido por default).
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
.acc-v2__period {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: 12px;
}
.acc-v2__period-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 140px;
  flex: 0 0 160px;
}
.acc-v2__period-label {
  font-size: 11.5px;
  color: rgb(var(--slate-9));
  font-weight: 500;
}
@media (max-width: 640px) {
  .acc-v2__period-field { flex: 1 1 100%; }
}

.acc-v2__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}
@media (max-width: 800px) {
  .acc-v2__grid { grid-template-columns: 1fr; }
}

.acc-v2__card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 18px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}

.acc-v2__card-header {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}
.acc-v2__card-icon {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  &--emerald { background: rgba(16, 185, 129, 0.12); color: #047857; }
  &--ruby    { background: rgba(220, 38, 38, 0.12);  color: #b91c1c; }
  &--violet  { background: rgba(139, 92, 246, 0.12); color: #7c3aed; }
  &--blue    { background: rgba(37, 99, 235, 0.12);  color: #2563eb; }
}
:root.dark .acc-v2__card-icon--emerald { color: #6ee7b7; background: rgba(16, 185, 129, 0.18); }
:root.dark .acc-v2__card-icon--ruby    { color: #fca5a5; background: rgba(220, 38, 38, 0.18); }
:root.dark .acc-v2__card-icon--violet  { color: #c4b5fd; background: rgba(139, 92, 246, 0.18); }
:root.dark .acc-v2__card-icon--blue    { color: #93c5fd; background: rgba(37, 99, 235, 0.18); }

.acc-v2__card-title {
  margin: 0 0 2px;
  font-size: 15px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.acc-v2__card-hint {
  margin: 0;
  font-size: 12px;
  color: rgb(var(--slate-9));
  line-height: 1.4;
}

.acc-v2__card-count {
  display: flex;
  flex-direction: column;
  gap: 2px;
  padding: 12px;
  background: rgb(var(--slate-2));
  border-radius: 8px;
}
.acc-v2__count-label {
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: rgb(var(--slate-9));
  font-weight: 600;
}
.acc-v2__count-value {
  font-size: 22px;
  font-weight: 700;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
}
.acc-v2__count-loading {
  font-size: 22px;
  color: rgb(var(--slate-9));
}

.acc-v2__card-footer {
  display: flex;
  align-items: center;
  gap: 10px;
}

.acc-v2__note {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  padding: 12px 14px;
  border-radius: 8px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  font-size: 12.5px;
  color: rgb(var(--slate-9));
  line-height: 1.5;
  i { margin-top: 2px; flex-shrink: 0; }
  strong { color: rgb(var(--slate-12)); }
  code {
    background: rgb(var(--slate-3));
    padding: 1px 5px;
    border-radius: 4px;
    font-family: 'SF Mono', Menlo, monospace;
    font-size: 11.5px;
  }
}
</style>
