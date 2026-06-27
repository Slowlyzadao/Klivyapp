<script setup>
/**
 * ClinicalRecordTimeline — sub-aba "Ficha Clínica".
 *
 * Cards verticais cronológicos em formato accordion:
 *   - Por padrão TODOS os cards começam recolhidos.
 *   - Header sempre visível: data, procedimento, profissional, badge status,
 *     chevron de toggle.
 *   - Click expande para mostrar campos clínicos completos + ações.
 *   - Botões "Expandir todos" / "Recolher todos" no topo.
 *   - Em modo de impressão, todos abrem automaticamente.
 */
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';

const props = defineProps({
  sessions: { type: Array, required: true },
  isLoading: { type: Boolean, default: false },
  canSign: { type: Boolean, default: false },
  canDelete: { type: Boolean, default: false },
});

const emit = defineEmits([
  'new-session',
  'print',
  'edit',
  'sign',
  'mark-erratum',
  'delete',
  'request-signature',
]);

const { t } = useI18n();

const expandedIds = ref(new Set());

const isExpanded = id => expandedIds.value.has(id);

const toggle = id => {
  const next = new Set(expandedIds.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  expandedIds.value = next;
};

const expandAll = () => {
  expandedIds.value = new Set(props.sessions.map(s => s.id));
};

const collapseAll = () => {
  expandedIds.value = new Set();
};

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

const sortedSessions = computed(() =>
  [...props.sessions].sort(
    (a, b) => new Date(b.performed_at) - new Date(a.performed_at)
  )
);

const allExpanded = computed(
  () =>
    sortedSessions.value.length > 0 &&
    sortedSessions.value.every(s => expandedIds.value.has(s.id))
);

const statusLabel = session => {
  if (session.erratum_at) return t('PATIENT_EVOLUTION.STATUS.ERRATUM');
  if (session.status === 'signed') return t('PATIENT_EVOLUTION.STATUS.SIGNED');
  return t('PATIENT_EVOLUTION.STATUS.DRAFT');
};

const statusIntent = session => {
  if (session.erratum_at) return 'danger';
  if (session.status === 'signed') return 'info';
  return 'warning';
};

const statusIcon = session => {
  if (session.erratum_at) return 'i-lucide-alert-triangle';
  if (session.status === 'signed') return 'i-lucide-check-circle-2';
  return 'i-lucide-pencil';
};

/* Copia o nome do procedimento para o clipboard. Solicitado pelo cliente
   pois o click no título do card abre/fecha o accordion (não permite
   selecionar texto). Usa Navigator API moderna; fallback silencioso em
   browsers muito antigos. */
const copyProcedureName = async (text) => {
  if (!text) return;
  try {
    await navigator.clipboard.writeText(text);
    useNotification.success(t('PATIENT_EVOLUTION.CLINICAL_RECORD.COPIED'));
  } catch {
    // Fallback antigo (deprecated mas funciona em browsers sem Clipboard API)
    try {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.setAttribute('readonly', '');
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
      useNotification.success(t('PATIENT_EVOLUTION.CLINICAL_RECORD.COPIED'));
    } catch {
      useNotification.error(t('PATIENT_EVOLUTION.CLINICAL_RECORD.COPY_ERROR'));
    }
  }
};

const handlePrint = () => {
  // O modal de impressão usa um iframe com HTML auto-contido (template já
  // mostra todos os campos), então não precisamos mais expandir a UI antes.
  emit('print');
};
</script>

<template>
  <div class="evo-subtab-pane">
    <header class="evo-subtab-header">
      <div>
        <h3 class="evo-subtab-title">
          {{ t('PATIENT_EVOLUTION.CLINICAL_RECORD.TITLE') }}
        </h3>
        <p class="evo-subtab-subtitle">
          {{ t('PATIENT_EVOLUTION.CLINICAL_RECORD.SUBTITLE') }}
        </p>
      </div>
      <div class="evo-subtab-actions hide-on-print">
        <!-- Tamanho `md` (default) pra alinhar a altura com o botão primário
             "+ Novo" abaixo. Ter tamanhos misturados na mesma linha de
             ações fica visualmente estranho. -->
        <BeclinicButton
          v-if="sortedSessions.length"
          variant="outline"
          color="slate"
          :icon="allExpanded ? 'i-lucide-chevrons-down-up' : 'i-lucide-chevrons-up-down'"
          :label="allExpanded ? 'Recolher todos' : 'Expandir todos'"
          @click="allExpanded ? collapseAll() : expandAll()"
        />
        <BeclinicButton
          variant="outline"
          color="slate"
          icon="i-lucide-printer"
          :label="t('PATIENT_EVOLUTION.CLINICAL_RECORD.PRINT')"
          @click="handlePrint"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-plus"
          :label="t('PATIENT_EVOLUTION.CLINICAL_RECORD.NEW')"
          @click="emit('new-session')"
        />
      </div>
    </header>

    <div v-if="isLoading" class="evo-loading">
      <i class="i-lucide-loader-2 w-5 h-5 animate-spin" />
    </div>

    <div
      v-else-if="!sortedSessions.length"
      class="evo-empty-state"
    >
      <i class="i-lucide-clipboard w-8 h-8 mb-2 text-slate-500" />
      <h4>{{ t('PATIENT_EVOLUTION.CLINICAL_RECORD.EMPTY_TITLE') }}</h4>
      <p>{{ t('PATIENT_EVOLUTION.CLINICAL_RECORD.EMPTY_HINT') }}</p>
    </div>

    <div v-else class="evo-timeline print-section">
      <article
        v-for="session in sortedSessions"
        :key="session.id"
        class="evo-timeline-card print-card"
        :class="{
          'is-erratum': session.erratum_at,
          'is-signed': !session.erratum_at && session.status === 'signed',
          'is-draft': !session.erratum_at && session.status !== 'signed',
          'is-expanded': isExpanded(session.id),
        }"
      >
        <button
          type="button"
          class="evo-timeline-card-header"
          :aria-expanded="isExpanded(session.id)"
          @click="toggle(session.id)"
        >
          <i
            class="evo-timeline-chevron w-4 h-4 hide-on-print"
            :class="
              isExpanded(session.id)
                ? 'i-lucide-chevron-down'
                : 'i-lucide-chevron-right'
            "
          />
          <div class="evo-timeline-summary">
            <div class="evo-timeline-summary-top">
              <span class="evo-timeline-date">
                <i class="i-lucide-calendar w-3.5 h-3.5" />
                {{ formatDate(session.performed_at) }}
              </span>
              <ProfessionalChip
                size="xs"
                :name="session.professional_name || '—'"
                :avatar-url="session.professional_avatar_url || ''"
              />
            </div>
            <h4 class="evo-timeline-procedure">
              {{ session.procedure_name || '—' }}
              <Tooltip
                v-if="session.procedure_name"
                :label="t('PATIENT_EVOLUTION.CLINICAL_RECORD.COPY_TOOLTIP')"
                position="top"
              >
                <!-- `role="button"` em span (não <button>) porque
                     este elemento está dentro de outro <button> de
                     toggle do accordion — button aninhado é HTML
                     inválido. `@click.stop` impede que o click
                     dispare o toggle do card. -->
                <span
                  class="evo-procedure-copy hide-on-print"
                  role="button"
                  tabindex="0"
                  :aria-label="t('PATIENT_EVOLUTION.CLINICAL_RECORD.COPY_TOOLTIP')"
                  @click.stop="copyProcedureName(session.procedure_name)"
                  @keydown.enter.stop.prevent="copyProcedureName(session.procedure_name)"
                  @keydown.space.stop.prevent="copyProcedureName(session.procedure_name)"
                >
                  <i class="i-lucide-copy w-3.5 h-3.5" />
                </span>
              </Tooltip>
            </h4>
          </div>
          <Badge
            :label="statusLabel(session)"
            :intent="statusIntent(session)"
            :icon="statusIcon(session)"
          />
        </button>

        <div
          v-if="isExpanded(session.id)"
          class="evo-timeline-card-body"
        >
          <dl class="evo-timeline-fields">
            <template v-if="session.complaint_of_day">
              <dt>Queixa do dia</dt>
              <dd>{{ session.complaint_of_day }}</dd>
            </template>
            <template v-if="session.assessment">
              <dt>Avaliação</dt>
              <dd>{{ session.assessment }}</dd>
            </template>
            <template v-if="session.complications">
              <dt>Intercorrências</dt>
              <dd>{{ session.complications }}</dd>
            </template>
            <template v-if="session.result_observed">
              <dt>Resultado imediato</dt>
              <dd>{{ session.result_observed }}</dd>
            </template>
            <template v-if="session.next_consultation_details">
              <dt>Próxima consulta</dt>
              <dd>{{ session.next_consultation_details }}</dd>
            </template>
            <template v-if="session.observation">
              <dt>Observação</dt>
              <dd>{{ session.observation }}</dd>
            </template>
            <template v-if="session.return_in_days">
              <dt>Retorno</dt>
              <dd>em {{ session.return_in_days }} dias</dd>
            </template>
          </dl>

          <div
            v-if="session.erratum_at && session.erratum_reason"
            class="evo-erratum-banner"
          >
            <i class="i-lucide-alert-triangle w-4 h-4" />
            <div>
              <strong>Errata:</strong>
              <span>{{ session.erratum_reason }}</span>
            </div>
          </div>
        </div>

        <footer
          v-if="isExpanded(session.id)"
          class="evo-timeline-card-actions hide-on-print"
        >
          <!-- 1. Editar (mudar conteúdo, ainda em rascunho) -->
          <BeclinicButton
            v-if="session.editable"
            size="xs"
            variant="ghost"
            color="slate"
            icon="i-lucide-edit"
            label="Editar"
            @click="emit('edit', session)"
          />
          <!-- 2. Assinar (profissional — ação primária quando rascunho) -->
          <Tooltip
            v-if="canSign && session.status === 'draft' && !session.erratum_at"
            :label="t('PATIENT_EVOLUTION.CLINICAL_RECORD.SIGN_TOOLTIP')"
          >
            <BeclinicButton
              size="xs"
              variant="solid"
              color="blue"
              icon="i-lucide-check"
              label="Assinar"
              @click="emit('sign', session.id)"
            />
          </Tooltip>
          <!-- 3. Solicitar assinatura do paciente -->
          <Tooltip
            v-if="!session.patient_signed && !session.erratum_at"
            :label="t('PATIENT_EVOLUTION.CLINICAL_RECORD.REQUEST_SIGNATURE_TOOLTIP')"
          >
            <BeclinicButton
              size="xs"
              variant="faded"
              color="amber"
              icon="i-lucide-pen-tool"
              label="Solicitar assinatura"
              @click="emit('request-signature', session)"
            />
          </Tooltip>
          <!-- Separator visual antes das ações destrutivas (errata + excluir).
               Só aparece se houver pelo menos uma destrutiva visível. -->
          <span
            v-if="(canSign && session.status === 'signed' && !session.erratum_at)
              || (canDelete && session.status === 'draft')"
            class="evo-timeline-card-actions__separator"
            aria-hidden="true"
          />
          <!-- 4. Marcar errata (sessão signed, único caminho de "desfazer") -->
          <Tooltip
            v-if="canSign && session.status === 'signed' && !session.erratum_at"
            :label="t('PATIENT_EVOLUTION.CLINICAL_RECORD.MARK_ERRATUM_TOOLTIP')"
          >
            <BeclinicButton
              size="xs"
              variant="ghost"
              color="ruby"
              icon="i-lucide-alert-triangle"
              :label="t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.MARK_ERRATUM')"
              @click="emit('mark-erratum', session)"
            />
          </Tooltip>
          <!-- 5. Excluir (apenas rascunho — signed só vira errata) -->
          <BeclinicButton
            v-if="canDelete && session.status === 'draft'"
            size="xs"
            variant="ghost"
            color="ruby"
            icon="i-lucide-trash-2"
            :label="t('PATIENT_EVOLUTION.EVOLUTION_HISTORY.DELETE')"
            @click="emit('delete', session.id)"
          />
        </footer>
      </article>
    </div>
  </div>
</template>
