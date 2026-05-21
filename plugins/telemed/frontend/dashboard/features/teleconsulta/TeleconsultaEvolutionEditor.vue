<script setup>
// Painel da evolução clínica proposta pela IA (SOAP + pontos de atenção).
// Modo padrão = leitura (visão do mockup); botão "Editar" abre textareas.
// Ações: Aplicar ao Prontuário (approve) / Editar (toggle) / Recusar (reject).
// Estilos vivem em ../../../styles/teleconsulta-detail.scss.
import { ref, watch, computed } from 'vue';
import { proposedEvolutionsApi } from '../../api/teleconsultas';
import { formatFullDateTimeLabel } from './utils/formatters.js';

const props = defineProps({
  evolution: { type: Object, required: true },
});
const emit = defineEmits(['saved', 'approved', 'rejected']);

// Cópia local pra editar sem mutar o parent. Reseta quando a proposta
// é substituída (ex.: reprocessamento) ou o usuário sai do modo edição.
const localSoap = ref({ ...(props.evolution.soap_structure || {}) });
const localMarkdown = ref(props.evolution.raw_markdown || '');
const isEditing = ref(false);
const isSaving = ref(false);
const isApproving = ref(false);
const isRejecting = ref(false);
const showRejectModal = ref(false);
const rejectReason = ref('');
const error = ref(null);

watch(
  () => props.evolution.id,
  () => {
    localSoap.value = { ...(props.evolution.soap_structure || {}) };
    localMarkdown.value = props.evolution.raw_markdown || '';
    isEditing.value = false;
  }
);

const isApproved = computed(() => props.evolution.status === 'approved');
const isRejected = computed(() => props.evolution.status === 'rejected');
const isFinalized = computed(() => isApproved.value || isRejected.value);

const statusLabel = computed(() => {
  return {
    pending_review: 'Aguarda revisão',
    edited: 'Editada',
    approved: 'Aprovada',
    rejected: 'Recusada',
  }[props.evolution.status] || props.evolution.status;
});

const subtitle = computed(() => {
  const who = props.evolution.reviewed_by;
  const when = props.evolution.reviewed_at
    ? formatFullDateTimeLabel(props.evolution.reviewed_at)
    : null;
  if (isApproved.value && who && when) return `Aprovada por ${who} em ${when}`;
  if (isRejected.value && who && when) return `Recusada por ${who} em ${when}`;
  return 'Gerada automaticamente pela IA — revise antes de aplicar.';
});

const provider = computed(() => props.evolution.provider || '');

// Pontos de atenção (array de { type, text, severity? }).
// Tag por categoria: comportamento → default, técnico → warn, crítico → danger.
const TAG_VARIANT = {
  high: 'tcd-attention-tag--danger',
  medium: 'tcd-attention-tag--warn',
  low: 'tcd-attention-tag--default',
};
const ICON_VARIANT = {
  high: { cls: 'i-lucide-alert-triangle', color: 'tcd-attention-card__icon-danger' },
  medium: { cls: 'i-lucide-alert-circle', color: 'tcd-attention-card__icon-warn' },
  low: { cls: 'i-lucide-info', color: 'tcd-attention-card__icon-info' },
};
const tagClass = pt => TAG_VARIANT[pt.severity] || 'tcd-attention-tag--default';
const iconFor = pt => ICON_VARIANT[pt.severity] || ICON_VARIANT.low;

const attentionPoints = computed(() =>
  Array.isArray(props.evolution.attention_points) ? props.evolution.attention_points : []
);

const soapFields = computed(() => [
  { key: 'subjetivo', label: 'S — Subjetivo' },
  { key: 'objetivo',  label: 'O — Objetivo'  },
  { key: 'avaliacao', label: 'A — Avaliação' },
  { key: 'plano',     label: 'P — Plano'     },
]);

const soapValue = key => {
  const value = props.evolution.soap_structure?.[key];
  return typeof value === 'string' ? value.trim() : '';
};

const startEditing = () => {
  localSoap.value = { ...(props.evolution.soap_structure || {}) };
  localMarkdown.value = props.evolution.raw_markdown || '';
  isEditing.value = true;
  error.value = null;
};

const cancelEditing = () => {
  isEditing.value = false;
  error.value = null;
};

const save = async () => {
  isSaving.value = true;
  error.value = null;
  try {
    const { data } = await proposedEvolutionsApi.update(props.evolution.id, {
      soap_structure: localSoap.value,
      raw_markdown: localMarkdown.value,
    });
    emit('saved', data.data);
    isEditing.value = false;
  } catch (e) {
    error.value = e?.response?.data?.error || e.message;
  } finally {
    isSaving.value = false;
  }
};

const approve = async () => {
  if (!window.confirm('Aplicar esta evolução ao prontuário do paciente?')) return;
  isApproving.value = true;
  error.value = null;
  try {
    const { data } = await proposedEvolutionsApi.approve(props.evolution.id);
    emit('approved', data);
  } catch (e) {
    error.value = e?.response?.data?.error || e.message;
  } finally {
    isApproving.value = false;
  }
};

const openReject = () => {
  rejectReason.value = '';
  error.value = null;
  showRejectModal.value = true;
};

const reject = async () => {
  if (!rejectReason.value.trim()) {
    error.value = 'Justificativa obrigatória';
    return;
  }
  isRejecting.value = true;
  error.value = null;
  try {
    const { data } = await proposedEvolutionsApi.reject(
      props.evolution.id,
      rejectReason.value
    );
    emit('rejected', data.data);
    showRejectModal.value = false;
    rejectReason.value = '';
  } catch (e) {
    error.value = e?.response?.data?.error || e.message;
  } finally {
    isRejecting.value = false;
  }
};
</script>

<template>
  <section class="tcd-evolution" aria-label="Evolução do paciente">
    <header class="tcd-evolution__head">
      <div>
        <h3 class="tcd-evolution__title">
          <i class="i-lucide-sparkles w-5 h-5 tcd-evolution__title-icon" />
          <span>Evolução do Paciente</span>
        </h3>
        <p class="tcd-evolution__subtitle">{{ subtitle }}</p>
      </div>
      <div class="tcd-evolution__head-right">
        <span :class="['tcd-evolution__status', `tcd-evolution__status--${evolution.status}`]">
          {{ statusLabel }}
        </span>
        <span v-if="provider" class="tcd-evolution__provider">{{ provider }}</span>
      </div>
    </header>

    <div
      v-if="isApproved && evolution.clinical_note_id"
      class="tcd-evolution__banner tcd-evolution__banner--success"
    >
      Aplicada ao prontuário · ClinicalNote #{{ evolution.clinical_note_id }}
    </div>
    <div
      v-else-if="isRejected && evolution.reviewer_notes"
      class="tcd-evolution__banner tcd-evolution__banner--warning"
    >
      Recusada — {{ evolution.reviewer_notes }}
    </div>

    <!-- Pontos de atenção -->
    <div v-if="attentionPoints.length" class="tcd-attention">
      <h4 class="tcd-attention__title">
        <i class="i-lucide-alert-triangle w-4 h-4 tcd-attention__icon" />
        <span>Pontos de Atenção</span>
      </h4>
      <div class="tcd-attention__list">
        <article
          v-for="pt in attentionPoints"
          :key="`${pt.type || ''}-${(pt.text || '').slice(0, 40)}`"
          class="tcd-attention-card"
        >
          <header class="tcd-attention-card__head">
            <span :class="['tcd-attention-tag', tagClass(pt)]">
              {{ pt.type || 'Atenção' }}
            </span>
            <i :class="[iconFor(pt).cls, 'w-4 h-4', iconFor(pt).color]" />
          </header>
          <p class="tcd-attention-card__text">{{ pt.text }}</p>
        </article>
      </div>
    </div>

    <!-- SOAP -->
    <div class="tcd-soap">
      <article
        v-for="field in soapFields"
        :key="field.key"
        class="tcd-soap__card"
      >
        <span class="tcd-soap__label">{{ field.label }}</span>
        <textarea
          v-if="isEditing"
          v-model="localSoap[field.key]"
          class="tcd-soap__textarea"
          rows="4"
        />
        <p
          v-else-if="soapValue(field.key)"
          class="tcd-soap__text"
        >{{ soapValue(field.key) }}</p>
        <p v-else class="tcd-soap__text tcd-soap__text--muted">
          Sem informação suficiente na consulta — verificar presencialmente.
        </p>
      </article>
    </div>

    <p v-if="error" class="tcd-evolution__error">{{ error }}</p>

    <!-- Footer actions -->
    <footer v-if="!isFinalized" class="tcd-evolution__actions">
      <template v-if="isEditing">
        <button
          type="button"
          class="tcd-btn tcd-btn--primary"
          :disabled="isSaving"
          @click="save"
        >
          {{ isSaving ? 'Salvando…' : 'Salvar rascunho' }}
        </button>
        <div class="tcd-evolution__actions-row">
          <button
            type="button"
            class="tcd-btn tcd-btn--ghost"
            :disabled="isSaving"
            @click="cancelEditing"
          >
            Cancelar
          </button>
          <button
            type="button"
            class="tcd-btn tcd-btn--danger"
            @click="openReject"
          >
            Recusar
          </button>
        </div>
      </template>
      <template v-else>
        <button
          type="button"
          class="tcd-btn tcd-btn--primary"
          :disabled="isApproving"
          @click="approve"
        >
          {{ isApproving ? 'Aplicando…' : 'Aplicar ao Prontuário' }}
        </button>
        <div class="tcd-evolution__actions-row">
          <button
            type="button"
            class="tcd-btn tcd-btn--ghost"
            @click="startEditing"
          >
            Editar
          </button>
          <button
            type="button"
            class="tcd-btn tcd-btn--danger"
            @click="openReject"
          >
            Recusar
          </button>
        </div>
      </template>
    </footer>

    <!-- Reject modal -->
    <div
      v-if="showRejectModal"
      class="tcd-modal-backdrop"
      @click.self="showRejectModal = false"
    >
      <div class="tcd-modal" role="dialog" aria-modal="true">
        <h4 class="tcd-modal__title">Recusar evolução</h4>
        <p class="tcd-modal__hint">
          Esta justificativa fica registrada para auditoria CFM.
        </p>
        <textarea
          v-model="rejectReason"
          class="tcd-modal__input"
          rows="4"
          placeholder="Motivo da recusa…"
        />
        <p v-if="error" class="tcd-evolution__error">{{ error }}</p>
        <div class="tcd-modal__actions">
          <button
            type="button"
            class="tcd-btn tcd-btn--ghost tcd-btn--auto"
            @click="showRejectModal = false"
          >
            Cancelar
          </button>
          <button
            type="button"
            class="tcd-btn tcd-btn--danger tcd-btn--auto"
            :disabled="isRejecting"
            @click="reject"
          >
            {{ isRejecting ? 'Recusando…' : 'Confirmar recusa' }}
          </button>
        </div>
      </div>
    </div>
  </section>
</template>
