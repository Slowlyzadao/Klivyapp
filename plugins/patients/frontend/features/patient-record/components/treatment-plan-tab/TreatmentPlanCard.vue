<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import {
  itemStatusConfig,
  itemSessionProgress,
  itemSubtotal,
  planTotal,
} from '@plugins/patients/frontend/constants/treatmentPlan';

const props = defineProps({
  plan: { type: Object, required: true },
  isEditing: { type: Boolean, default: false },
  isPdfLoading: { type: Boolean, default: false },
});

const emit = defineEmits([
  'edit-plan',
  'save-plan',
  'approve-plan',
  'delete-plan',
  'add-item',
  'edit-item',
  'delete-item',
  'open-pdf',
]);

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const STATUS_LABEL_KEYS = {
  proposto: 'PATIENT_TREATMENT_PLAN.STATUS.PROPOSTO',
  aprovado: 'PATIENT_TREATMENT_PLAN.STATUS.APROVADO',
  approved: 'PATIENT_TREATMENT_PLAN.STATUS.APROVADO',
  em_execucao: 'PATIENT_TREATMENT_PLAN.STATUS.EM_EXECUCAO',
  concluido: 'PATIENT_TREATMENT_PLAN.STATUS.CONCLUIDO',
  cancelado: 'PATIENT_TREATMENT_PLAN.STATUS.CANCELADO',
};

const itemStatusLabel = item => {
  const cfg = itemStatusConfig(item);
  const key = STATUS_LABEL_KEYS[item.status];
  return key ? t(key) : cfg.label;
};

// Título dinâmico: usa o procedimento principal (primeiro item) como
// identificador do plano. Plano vazio cai no label genérico.
const planHeadline = computed(() => {
  const items = props.plan?.treatment_items || [];
  if (items.length === 0) {
    return t('PATIENT_TREATMENT_PLAN.PLAN.EMPTY_HEADLINE');
  }
  if (items.length === 1) {
    return items[0].procedure_name || t('PATIENT_TREATMENT_PLAN.PLAN.TITLE');
  }
  return t('PATIENT_TREATMENT_PLAN.PLAN.MULTI_HEADLINE', {
    name: items[0].procedure_name,
    rest: items.length - 1,
  });
});

const planSubtitle = computed(() => {
  const items = props.plan?.treatment_items || [];
  const total = formatCurrency(planTotal(props.plan));
  const sessions = items.reduce(
    (sum, it) => sum + (Number(it.sessions_planned) || 0),
    0
  );
  if (items.length === 0) return t('PATIENT_TREATMENT_PLAN.PLAN.EMPTY_HINT');
  return t('PATIENT_TREATMENT_PLAN.PLAN.HEADER_META', {
    sessions,
    total,
  });
});

// Lista de observações dos items (somente os que têm `notes` preenchido).
const itemNotes = computed(() =>
  (props.plan?.treatment_items || [])
    .filter(it => (it.notes || '').trim())
    .map(it => ({
      id: it.id,
      procedure_name: it.procedure_name,
      notes: it.notes,
    }))
);

const professionalInitials = computed(() => {
  const name = props.plan?.professional_name || '';
  const parts = name.trim().split(/\s+/);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return (parts[0][0] || '').toUpperCase();
  return ((parts[0][0] || '') + (parts[parts.length - 1][0] || '')).toUpperCase();
});

// Accordion: planos aprovados/concluídos/cancelados começam recolhidos
// (para evitar uma parede de cards expandidos quando há histórico). Plano
// `proposto` começa expandido — é o estado ativo de edição.
const isCollapsed = ref(false);

const isFinalStatus = status =>
  ['aprovado', 'approved', 'em_execucao', 'concluido', 'cancelado'].includes(
    status
  );

watch(
  () => props.plan?.status,
  status => {
    isCollapsed.value = isFinalStatus(status);
  },
  { immediate: true }
);

// Em modo de edição, força expandido (não faz sentido editar com tudo recolhido).
const effectiveCollapsed = computed(() =>
  props.isEditing ? false : isCollapsed.value
);

const toggleCollapsed = event => {
  // Não toggle se o click veio de um botão dentro do header (Editar, Aprovar,
  // Excluir, etc.). O próprio header tem role="button" — filtramos só os
  // <button> reais dentro dele.
  if (event?.target?.closest?.('button')) return;
  if (props.isEditing) return;
  isCollapsed.value = !isCollapsed.value;
};

// Garante que o card abra automaticamente em modo de impressão (o conteúdo
// está em v-if, então sem isso o navegador imprime só o cabeçalho).
const wasCollapsedBeforePrint = ref(false);

const handleBeforePrint = () => {
  wasCollapsedBeforePrint.value = isCollapsed.value;
  isCollapsed.value = false;
};

const handleAfterPrint = () => {
  isCollapsed.value = wasCollapsedBeforePrint.value;
};

onMounted(() => {
  window.addEventListener('beforeprint', handleBeforePrint);
  window.addEventListener('afterprint', handleAfterPrint);
});

onBeforeUnmount(() => {
  window.removeEventListener('beforeprint', handleBeforePrint);
  window.removeEventListener('afterprint', handleAfterPrint);
});
</script>

<template>
  <div
    class="rp-plan page-break-inside-avoid print-card"
    :class="{
      'is-collapsed': effectiveCollapsed,
      'is-clickable': !isEditing,
    }"
  >
    <!-- Cabeçalho -->
    <div
      class="rp-plan-head"
      :role="isEditing ? null : 'button'"
      :aria-expanded="!effectiveCollapsed"
      @click="toggleCollapsed"
    >
      <div class="rp-plan-head-left">
        <i
          v-if="!isEditing"
          class="rp-plan-chevron hide-on-print w-4 h-4"
          :class="
            effectiveCollapsed
              ? 'i-lucide-chevron-right'
              : 'i-lucide-chevron-down'
          "
        />
        <div class="rp-plan-head-icon">
          <i class="i-lucide-list-checks" />
        </div>
        <div class="rp-plan-head-text">
          <span class="rp-plan-name">{{ planHeadline }}</span>
          <span class="rp-plan-cid">{{ planSubtitle }}</span>
        </div>
      </div>
      <div class="rp-plan-actions hide-on-print">
        <Badge
          v-if="plan.status === 'aprovado' || plan.status === 'approved'"
          :label="t('PATIENT_TREATMENT_PLAN.PLAN.STATUS_APPROVED')"
          intent="success"
          icon="i-lucide-check-circle-2"
        />
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          :icon="isEditing ? 'i-lucide-save' : 'i-lucide-pencil'"
          :label="
            isEditing
              ? t('PATIENT_TREATMENT_PLAN.PLAN.ACTION_SAVE')
              : t('PATIENT_TREATMENT_PLAN.PLAN.ACTION_EDIT')
          "
          @click="
            isEditing ? emit('save-plan', plan) : emit('edit-plan', plan)
          "
        />
        <BeclinicButton
          v-if="plan.status === 'proposto'"
          v-can="['patients', 'manage_treatment_plans']"
          size="sm"
          variant="faded"
          color="teal"
          icon="i-lucide-check-circle"
          :label="t('PATIENT_TREATMENT_PLAN.PLAN.ACTION_APPROVE')"
          @click="emit('approve-plan', plan.id)"
        />
        <BeclinicButton
          v-can="['patients', 'manage_treatment_plans']"
          size="sm"
          variant="ghost"
          color="ruby"
          icon="i-lucide-trash-2"
          @click="emit('delete-plan', plan.id)"
        />
      </div>
    </div>

    <template v-if="!effectiveCollapsed">
    <!-- Procedimentos -->
    <div class="rp-section">
      <div class="rp-section-label">
        <i class="i-lucide-clipboard-list rp-section-icon rp-section-icon--amber" />
        {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.TITLE') }}
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="blue"
          icon="i-lucide-plus"
          :label="t('PATIENT_TREATMENT_PLAN.PROCEDURES.ADD')"
          class="hide-on-print"
          @click="emit('add-item', plan)"
        />
      </div>

      <div class="rp-section-body rp-table-wrap">
        <table class="rp-table">
          <thead class="rp-table-head">
            <tr>
              <th class="rp-th">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.PROCEDURE') }}
              </th>
              <th class="rp-th">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.REGION') }}
              </th>
              <th class="rp-th rp-th--center">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.SESSIONS') }}
              </th>
              <th class="rp-th rp-th--right">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.UNIT_PRICE') }}
              </th>
              <th class="rp-th rp-th--right">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.DISCOUNT') }}
              </th>
              <th class="rp-th rp-th--right">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.SUBTOTAL') }}
              </th>
              <th class="rp-th rp-th--center hide-on-print">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.STATUS') }}
              </th>
              <th class="rp-th rp-th--right hide-on-print">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.ACTION') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="!plan.treatment_items || plan.treatment_items.length === 0">
              <td colspan="8" class="rp-td-empty">
                {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.EMPTY') }}
              </td>
            </tr>
            <tr
              v-for="item in plan.treatment_items"
              :key="item.id"
              class="rp-tr"
            >
              <td class="rp-td rp-td--name">
                {{ item.procedure_name || item.procedure_code }}
              </td>
              <td class="rp-td rp-td--muted">
                {{ item.region || item.tooth_number || '-' }}
              </td>
              <td class="rp-td rp-td--muted rp-td--center">
                <div class="rp-sessions-cell">
                  <span class="rp-sessions-count">
                    {{ item.sessions_done || 0 }} / {{ item.sessions_planned }}
                  </span>
                  <div
                    class="rp-progress-track"
                    :title="
                      t('PATIENT_TREATMENT_PLAN.PROCEDURES.PROGRESS_TITLE', {
                        percent: itemSessionProgress(item),
                      })
                    "
                  >
                    <div
                      class="rp-progress-bar"
                      :class="{
                        'rp-progress-bar--done': item.status === 'concluido',
                        'rp-progress-bar--exec': item.status === 'em_execucao',
                      }"
                      :style="{ width: `${itemSessionProgress(item)}%` }"
                    />
                  </div>
                </div>
              </td>
              <td class="rp-td rp-td--muted rp-td--right">
                {{ formatCurrency(item.unit_price) }}
              </td>
              <td class="rp-td rp-td--muted rp-td--right">
                <span v-if="Number(item.discount_value) > 0 && item.discount_type">
                  <template v-if="item.discount_type === 'percentual'">
                    {{ Number(item.discount_value) }}%
                  </template>
                  <template v-else>
                    − {{ formatCurrency(item.discount_value) }}
                  </template>
                </span>
                <span v-else class="rp-td--muted">—</span>
              </td>
              <td class="rp-td rp-td--strong rp-td--right">
                {{ formatCurrency(itemSubtotal(item)) }}
              </td>
              <td class="rp-td rp-td--center hide-on-print">
                <span class="rp-status" :class="itemStatusConfig(item).cls">
                  {{ itemStatusLabel(item) }}
                </span>
              </td>
              <td class="rp-td rp-td--right hide-on-print">
                <div class="rp-row-actions">
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="slate"
                    icon="i-lucide-pencil"
                    :title="t('PATIENT_TREATMENT_PLAN.PROCEDURES.EDIT_TITLE')"
                    @click="emit('edit-item', plan, item)"
                  />
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-trash"
                    :title="t('PATIENT_TREATMENT_PLAN.PROCEDURES.REMOVE_TITLE')"
                    @click="emit('delete-item', plan.id, item.id)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>

        <div
          v-if="plan.treatment_items && plan.treatment_items.length > 0"
          class="rp-total"
        >
          <span class="rp-total-label">
            {{ t('PATIENT_TREATMENT_PLAN.PROCEDURES.TOTAL_LABEL') }}
          </span>
          <span class="rp-total-value">
            {{ formatCurrency(planTotal(plan)) }}
          </span>
        </div>
      </div>
    </div>

    <!-- Observações e Previsão -->
    <div class="rp-section">
      <div class="rp-section-label">
        <i class="i-lucide-calendar-clock rp-section-icon rp-section-icon--purple" />
        {{ t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.TITLE') }}
      </div>
      <div class="rp-section-body rp-diag-grid">
        <div class="rp-diag-item">
          <span class="rp-diag-label">
            {{ t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.DURATION_LABEL') }}
          </span>
          <template v-if="isEditing">
            <input
              v-model="plan.estimated_duration"
              type="text"
              class="rp-field-input rp-field-input--sm"
              :placeholder="
                t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.DURATION_PLACEHOLDER')
              "
            />
          </template>
          <p v-else class="rp-diag-value">
            {{
              plan.estimated_duration ||
              t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.DURATION_FALLBACK')
            }}
          </p>
        </div>
        <div class="rp-diag-item">
          <span class="rp-diag-label">
            {{ t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.PROFESSIONAL_LABEL') }}
          </span>
          <div class="rp-professional">
            <img
              v-if="plan.professional_avatar_url"
              :src="plan.professional_avatar_url"
              :alt="plan.professional_name || ''"
              class="rp-professional-avatar"
            />
            <span v-else class="rp-professional-avatar rp-professional-avatar--initials">
              {{ professionalInitials }}
            </span>
            <span class="rp-professional-name">
              {{
                plan.professional_name ||
                t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.PROFESSIONAL_FALLBACK')
              }}
            </span>
          </div>
        </div>
      </div>

      <!-- Observações dos procedimentos (notes preenchidas no modal de item) -->
      <div v-if="itemNotes.length > 0" class="rp-section-body rp-notes-list">
        <span class="rp-diag-label">
          {{ t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.NOTES_LABEL') }}
        </span>
        <ul class="rp-notes-items">
          <li
            v-for="note in itemNotes"
            :key="note.id"
            class="rp-notes-item"
          >
            <strong class="rp-notes-procedure">{{ note.procedure_name }}:</strong>
            <span class="rp-notes-text">{{ note.notes }}</span>
          </li>
        </ul>
      </div>

      <div class="rp-plan-footer">
        <div class="rp-approval-info">
          <i
            class="i-lucide-shield-check rp-approval-icon"
            :class="
              plan.status === 'aprovado' || plan.status === 'approved'
                ? 'rp-approval-icon--green'
                : 'rp-approval-icon--muted'
            "
          />
          <span>
            {{
              plan.status === 'aprovado' || plan.status === 'approved'
                ? t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.APPROVED_AT', {
                    date: formatDate(plan.approved_at || new Date()),
                  })
                : t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.PENDING_APPROVAL')
            }}
          </span>
        </div>
        <div v-if="plan.pdf_url" class="hide-on-print">
          <BeclinicButton
            size="sm"
            variant="faded"
            color="slate"
            :icon="isPdfLoading ? 'i-lucide-loader-circle' : 'i-lucide-file-text'"
            :label="
              isPdfLoading
                ? t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.LOADING_PDF')
                : t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.VIEW_PDF')
            "
            :is-loading="isPdfLoading"
            :disabled="isPdfLoading"
            @click="!isPdfLoading && emit('open-pdf', plan)"
          />
        </div>
      </div>
    </div>
    </template>

    <!-- Resumo curto quando recolhido (só no card aprovado/concluído) -->
    <div
      v-if="effectiveCollapsed"
      class="rp-plan-collapsed-summary hide-on-print"
    >
      <span class="rp-plan-collapsed-meta">
        <i class="i-lucide-clipboard-list w-3.5 h-3.5" />
        {{ (plan.treatment_items || []).length }}
        {{
          (plan.treatment_items || []).length === 1
            ? 'procedimento'
            : 'procedimentos'
        }}
      </span>
      <span class="rp-plan-collapsed-meta">
        <i class="i-lucide-dollar-sign w-3.5 h-3.5" />
        {{ formatCurrency(planTotal(plan)) }}
      </span>
      <span
        v-if="plan.approved_at"
        class="rp-plan-collapsed-meta"
      >
        <i class="i-lucide-shield-check w-3.5 h-3.5" />
        {{
          t('PATIENT_TREATMENT_PLAN.OBSERVATIONS.APPROVED_AT', {
            date: formatDate(plan.approved_at),
          })
        }}
      </span>
    </div>
  </div>
</template>
