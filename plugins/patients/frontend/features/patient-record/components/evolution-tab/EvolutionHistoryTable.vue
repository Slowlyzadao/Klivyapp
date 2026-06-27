<script setup>
/**
 * EvolutionHistoryTable — sub-aba "Histórico de Evolução".
 *
 * Tabela colunada (Data | Área | Procedimento | Profissional | Próxima Consulta
 * | OBS | Retorno | Assinatura Paciente | Ações). Cada linha é um accordion:
 * clicar expande para mostrar todos os campos clínicos detalhados.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';

const props = defineProps({
  sessions: { type: Array, required: true },
  isLoading: { type: Boolean, default: false },
  canSign: { type: Boolean, default: false },
});

const emit = defineEmits([
  'edit',
  'mark-erratum',
  'request-signature',
  'view-signature',
]);

const { t } = useI18n();

const expandedIds = ref(new Set());

const toggleRow = id => {
  if (expandedIds.value.has(id)) expandedIds.value.delete(id);
  else expandedIds.value.add(id);
  // trigger reactivity
  expandedIds.value = new Set(expandedIds.value);
};

const isExpanded = id => expandedIds.value.has(id);

const formatDate = isoString => {
  if (!isoString) return '—';
  const d = new Date(isoString);
  return d.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: 'America/Sao_Paulo',
  });
};

// Formato com hora — usado no tooltip do badge "Assinada" pra mostrar
// quando exatamente o paciente assinou.
const formatDateTime = isoString => {
  if (!isoString) return '';
  const d = new Date(isoString);
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Sao_Paulo',
  });
};

const sortedSessions = computed(() =>
  [...props.sessions].sort(
    (a, b) => new Date(b.performed_at) - new Date(a.performed_at)
  )
);

const areaLabel = session => {
  const areas = session.areas_treated || [];
  if (!areas.length) return '—';
  return areas
    .map(a => a.region || a.description)
    .filter(Boolean)
    .join(', ') || '—';
};

const productLabel = session => {
  const products = session.products_used || [];
  if (!products.length) return null;
  return products
    .map(p => {
      const parts = [p.name];
      if (p.quantity) parts.push(`${p.quantity}${p.unit || ''}`);
      if (p.batch) parts.push(`Lote ${p.batch}`);
      if (p.expires_at) parts.push(`Val. ${p.expires_at}`);
      return parts.filter(Boolean).join(' · ');
    })
    .join(' | ');
};

const truncate = (text, max = 60) => {
  if (!text) return '—';
  return text.length > max ? `${text.slice(0, max)}…` : text;
};
</script>

<template>
  <div class="evo-subtab-pane">
    <header class="evo-subtab-header">
      <div>
        <h3 class="evo-subtab-title">
          {{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.TITLE') }}
        </h3>
        <p class="evo-subtab-subtitle">
          {{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.SUBTITLE') }}
        </p>
      </div>
    </header>

    <div v-if="isLoading" class="evo-loading">
      <i class="i-lucide-loader-2 w-5 h-5 animate-spin" />
    </div>

    <div v-else-if="!sortedSessions.length" class="evo-empty-state">
      <i class="i-lucide-table w-8 h-8 mb-2 text-slate-500" />
      <p>{{ t('PATIENT_EVOLUTION.CLINICAL_RECORD.EMPTY_TITLE') }}</p>
    </div>

    <div v-else class="evo-table-wrap">
      <table class="evo-history-table">
        <thead>
          <tr>
            <th class="evo-col-toggle"></th>
            <th>{{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_DATE') }}</th>
            <th>{{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_AREA') }}</th>
            <th>{{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_PROCEDURE') }}</th>
            <th>{{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_PROFESSIONAL') }}</th>
            <th>{{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_NEXT_CONSULT') }}</th>
            <th>{{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_OBSERVATION') }}</th>
            <th>{{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_RETURN') }}</th>
            <th>{{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_PATIENT_SIGNATURE') }}</th>
            <th class="text-right">
              {{ t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.COL_ACTIONS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <template v-for="session in sortedSessions" :key="session.id">
            <tr
              class="evo-row"
              :class="{
                'is-erratum': session.erratum_at,
                'is-expanded': isExpanded(session.id),
              }"
              @click="toggleRow(session.id)"
            >
              <td class="evo-col-toggle">
                <button
                  type="button"
                  class="evo-toggle-btn"
                  :aria-expanded="isExpanded(session.id)"
                  @click.stop="toggleRow(session.id)"
                >
                  <i
                    class="w-4 h-4 transition-transform"
                    :class="
                      isExpanded(session.id)
                        ? 'i-lucide-chevron-down'
                        : 'i-lucide-chevron-right'
                    "
                  />
                </button>
              </td>
              <td>{{ formatDate(session.performed_at) }}</td>
              <td>{{ areaLabel(session) }}</td>
              <td class="evo-cell-truncate">
                {{ truncate(session.procedure_name, 50) }}
              </td>
              <td>
                <ProfessionalChip
                  v-if="session.professional_name"
                  size="sm"
                  :name="session.professional_name"
                  :avatar-url="session.professional_avatar_url || ''"
                />
                <span v-else>—</span>
              </td>
              <td class="evo-cell-truncate">
                {{ truncate(session.next_consultation_details, 40) }}
              </td>
              <td class="evo-cell-truncate">
                {{ truncate(session.observation, 40) }}
              </td>
              <td>
                <span v-if="session.return_in_days">
                  {{
                    t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.RETURN_DAYS', {
                      days: session.return_in_days,
                    })
                  }}
                </span>
                <span v-else>—</span>
              </td>
              <td @click.stop>
                <Tooltip
                  v-if="session.patient_signed"
                  :label="t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.SIGNED_TOOLTIP', { date: formatDateTime(session.patient_signed_at) })"
                >
                  <Badge
                    :label="t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.SIGNED')"
                    intent="success"
                    icon="i-lucide-check-circle-2"
                    class="cursor-pointer"
                    @click="emit('view-signature', session)"
                  />
                </Tooltip>
                <Badge
                  v-else
                  :label="t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.NOT_SIGNED')"
                  intent="neutral"
                  icon="i-lucide-circle-dashed"
                />
              </td>
              <td class="text-right" @click.stop>
                <div class="evo-row-actions">
                  <Tooltip
                    v-if="!session.patient_signed && !session.erratum_at"
                    :label="t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.REQUEST_SIGNATURE')"
                  >
                    <BeclinicButton
                      size="xs"
                      variant="ghost"
                      color="amber"
                      icon="i-lucide-pen-tool"
                      @click="emit('request-signature', session)"
                    />
                  </Tooltip>
                  <Tooltip
                    v-if="session.editable"
                    :label="t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.EDIT')"
                  >
                    <BeclinicButton
                      size="xs"
                      variant="ghost"
                      color="slate"
                      icon="i-lucide-edit"
                      @click="emit('edit', session)"
                    />
                  </Tooltip>
                  <Tooltip
                    v-if="canSign && session.status === 'signed' && !session.erratum_at"
                    :label="t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.MARK_ERRATUM')"
                  >
                    <BeclinicButton
                      size="xs"
                      variant="ghost"
                      color="ruby"
                      icon="i-lucide-alert-triangle"
                      @click="emit('mark-erratum', session)"
                    />
                  </Tooltip>
                </div>
              </td>
            </tr>

            <tr
              v-if="isExpanded(session.id)"
              class="evo-row-detail"
              :class="{ 'is-erratum': session.erratum_at }"
            >
              <td></td>
              <td colspan="9">
                <div class="evo-detail-grid">
                  <div v-if="session.complaint_of_day" class="evo-detail-field">
                    <dt>Queixa do dia</dt>
                    <dd>{{ session.complaint_of_day }}</dd>
                  </div>
                  <div v-if="session.assessment" class="evo-detail-field">
                    <dt>Avaliação clínica</dt>
                    <dd>{{ session.assessment }}</dd>
                  </div>
                  <div v-if="session.procedure_name" class="evo-detail-field">
                    <dt>Procedimento realizado</dt>
                    <dd>{{ session.procedure_name }}</dd>
                  </div>
                  <div v-if="productLabel(session)" class="evo-detail-field">
                    <dt>Produto utilizado</dt>
                    <dd>{{ productLabel(session) }}</dd>
                  </div>
                  <div v-if="session.complications" class="evo-detail-field">
                    <dt>Intercorrências</dt>
                    <dd>{{ session.complications }}</dd>
                  </div>
                  <div v-if="session.result_observed" class="evo-detail-field">
                    <dt>Resultado imediato</dt>
                    <dd>{{ session.result_observed }}</dd>
                  </div>
                  <div v-if="session.next_consultation_details" class="evo-detail-field">
                    <dt>Próxima consulta e orientação</dt>
                    <dd>{{ session.next_consultation_details }}</dd>
                  </div>
                  <div v-if="session.observation" class="evo-detail-field">
                    <dt>Observação</dt>
                    <dd>{{ session.observation }}</dd>
                  </div>
                  <div
                    v-if="session.erratum_at && session.erratum_reason"
                    class="evo-detail-field evo-detail-erratum"
                  >
                    <dt>Errata</dt>
                    <dd>{{ session.erratum_reason }}</dd>
                  </div>
                </div>
              </td>
            </tr>
          </template>
        </tbody>
      </table>
    </div>
  </div>
</template>
