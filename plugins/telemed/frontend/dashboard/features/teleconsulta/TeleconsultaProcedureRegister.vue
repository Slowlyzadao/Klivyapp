<script setup>
// Audit 2026-05-26 — Bloco full-width abaixo da transcrição com o
// "Registro de Procedimento" (14 campos editáveis). Substitui os cards
// SOAP que viviam na lateral direita. A IA preenche o que conseguir da
// transcrição; campos que ela não souber (lote, produto em teleconsulta
// genérica) ficam vazios pro dentista preencher antes de assinar.
//
// Badge "IA" aparece em cada campo pre-preenchido pela IA. Quando o
// dentista edita o campo, o badge some daquele input (sinaliza que a
// origem do dado mudou). Ao salvar (rascunho ou assinatura), o backend
// persiste em `procedure_fields` (jsonb).
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { proposedEvolutionsApi } from '../../api/teleconsultas';
import { formatFullDateTimeLabel } from './utils/formatters.js';

const props = defineProps({
  detail:    { type: Object, required: true },
  evolution: { type: Object, required: true },
});
const emit = defineEmits(['saved', 'approved', 'rejected']);

// 14 chaves obrigatórias — mesma ordem do PROCEDURE_KEYS no backend
// (`evolution_provider/claude.rb`) pra evitar drift. Cada campo declara
// label, placeholder e o tipo de input.
const FIELDS = [
  { key: 'queixa_do_dia',             label: 'Queixa do Dia',                       type: 'textarea', rows: 3, section: 'avaliacao',  placeholder: 'Qual o principal relato do paciente hoje?' },
  { key: 'avaliacao_clinica',         label: 'Avaliação Clínica',                   type: 'textarea', rows: 3, section: 'avaliacao',  placeholder: 'Achados clínicos, exame físico, observações relevantes…' },
  { key: 'procedimento_realizado',    label: 'Procedimento Realizado',              type: 'text',                section: 'procedimento', required: true, placeholder: 'Ex: Aplicação de Toxina Botulínica' },
  { key: 'area_tratada',              label: 'Área Tratada',                        type: 'text',                section: 'procedimento', placeholder: 'Ex: Terço superior da face' },
  { key: 'produto_utilizado',         label: 'Produto Utilizado',                   type: 'text',                section: 'procedimento', placeholder: 'Ex: Botox (Allergan)' },
  { key: 'quantidade_dose',           label: 'Quantidade / Dose',                   type: 'text',                section: 'procedimento', placeholder: 'Ex: 50' },
  { key: 'unidade',                   label: 'Unidade',                             type: 'text',                section: 'procedimento', placeholder: 'un' },
  { key: 'lote',                      label: 'Lote',                                type: 'text',                section: 'procedimento', placeholder: 'Ex: ABC1234' },
  { key: 'validade',                  label: 'Validade',                            type: 'date',                section: 'procedimento' },
  { key: 'intercorrencias',           label: 'Intercorrências no Procedimento',     type: 'textarea', rows: 3, section: 'procedimento', placeholder: 'Hematomas, dor além do esperado, etc…' },
  { key: 'resultado_imediato',        label: 'Resultado Imediato Observado',        type: 'textarea', rows: 3, section: 'procedimento', placeholder: 'Paciente tolerou bem, assimetria corrigida…' },
  { key: 'detalhes_proxima_consulta', label: 'Detalhes Próxima Consulta e Orientação', type: 'textarea', rows: 3, section: 'acompanhamento', placeholder: 'Cuidados, retornos esperados, orientações ao paciente…' },
  { key: 'retorno_em_dias',           label: 'Retorno em (dias)',                   type: 'number',              section: 'acompanhamento', placeholder: 'Ex: 15' },
  { key: 'observacao',                label: 'Observação',                          type: 'textarea', rows: 3, section: 'acompanhamento', placeholder: 'Anotações livres…' },
];

const SECTIONS = [
  { id: 'avaliacao',      title: 'Avaliação Clínica' },
  { id: 'procedimento',   title: 'Procedimento e Produto' },
  { id: 'acompanhamento', title: 'Acompanhamento' },
];

const fieldsBySection = computed(() =>
  SECTIONS.map(s => ({ ...s, fields: FIELDS.filter(f => f.section === s.id) }))
);

// Source-of-truth IA: o que veio do backend na geração inicial. Quando
// `local[key] !== aiOriginal[key]` (ou local difere do default vazio),
// consideramos que o dentista editou aquele campo — badge "IA" some.
const aiOriginal = ref({});
const local = ref({});

const initFromEvolution = () => {
  const incoming = props.evolution.procedure_fields || {};
  const next = {};
  const orig = {};
  FIELDS.forEach(f => {
    const raw = incoming[f.key];
    const value = raw === null || raw === undefined ? '' : raw;
    next[f.key] = value;
    orig[f.key] = value;
  });
  local.value = next;
  aiOriginal.value = orig;
};

watch(() => props.evolution.id, () => initFromEvolution(), { immediate: true });

const isFieldAi = key => {
  const orig = aiOriginal.value[key];
  const cur  = local.value[key];
  if (orig === undefined || orig === null || orig === '') return false;
  return String(orig) === String(cur ?? '');
};

const isSaving = ref(false);
const isApproving = ref(false);
const isRejecting = ref(false);
const showRejectModal = ref(false);
const rejectReason = ref('');
const error = ref(null);

// 2026-05-26 — Checkbox de responsabilidade clínica. Conteúdo gerado
// por IA exige confirmação explícita do profissional antes de virar
// ClinicalNote no prontuário. Trilha CFM/LGPD: o `apply_edit!` e
// `approve!` no backend já gravam reviewed_by + reviewed_at, mas a
// intenção é eliminar ambiguidade ("li, revisei, assumo a autoria").
// Reseta quando o id da evolução muda (nova proposta = nova revisão).
const confirmationChecked = ref(false);
watch(() => props.evolution.id, () => { confirmationChecked.value = false; });

const isApproved = computed(() => props.evolution.status === 'approved');
const isRejected = computed(() => props.evolution.status === 'rejected');
const isFinalized = computed(() => isApproved.value || isRejected.value);

const statusLabel = computed(() => ({
  pending_review: 'Aguarda revisão',
  edited: 'Editada',
  approved: 'Aprovada',
  rejected: 'Recusada',
}[props.evolution.status] || props.evolution.status));

const provider = computed(() => props.evolution.provider || '');
const dateLabel = computed(() => props.detail?.starts_at ? formatFullDateTimeLabel(props.detail.starts_at) : '—');
const professionalLabel = computed(() => props.detail?.professional?.name || '—');

// hasUnsavedChanges: qualquer campo do local difere da última versão
// recebida do backend. Reseta após save bem-sucedido (initFromEvolution
// reinicia ambos os refs).
const hasUnsavedChanges = computed(() => {
  return FIELDS.some(f => {
    const cur = local.value[f.key];
    const orig = aiOriginal.value[f.key];
    return String(cur ?? '') !== String(orig ?? '');
  });
});

const onBeforeUnload = event => {
  if (!hasUnsavedChanges.value) return undefined;
  event.preventDefault();
  event.returnValue = '';
  return '';
};
watch(hasUnsavedChanges, dirty => {
  if (typeof window === 'undefined') return;
  if (dirty) window.addEventListener('beforeunload', onBeforeUnload);
  else window.removeEventListener('beforeunload', onBeforeUnload);
});
onBeforeUnmount(() => {
  if (typeof window !== 'undefined') {
    window.removeEventListener('beforeunload', onBeforeUnload);
  }
});

defineExpose({ hasUnsavedChanges });

// retorno_em_dias é integer; demais são strings. Normaliza antes de enviar.
const buildPayload = () => {
  const payload = {};
  FIELDS.forEach(f => {
    let v = local.value[f.key];
    if (f.key === 'retorno_em_dias') {
      v = v === '' || v === null ? null : Number(v);
      if (Number.isNaN(v)) v = null;
    } else {
      v = (v ?? '').toString();
    }
    payload[f.key] = v;
  });
  return payload;
};

const save = async () => {
  isSaving.value = true;
  error.value = null;
  try {
    const { data } = await proposedEvolutionsApi.update(props.evolution.id, {
      procedure_fields: buildPayload(),
    });
    emit('saved', data.data);
    // Re-sincroniza orig com o que voltou do backend — badges "IA" agora
    // refletem o estado pós-edição (campo editado deixa de ser "IA").
    initFromEvolution();
  } catch (e) {
    error.value = e?.response?.data?.error || e.message;
  } finally {
    isSaving.value = false;
  }
};

const approve = async () => {
  // 'Salvar e Assinar': se há mudanças, salva ANTES de aprovar pra não
  // perder edições locais. Senão (form intocado), só aprova.
  if (!window.confirm('Aplicar esta evolução ao prontuário do paciente?')) return;
  isApproving.value = true;
  error.value = null;
  try {
    if (hasUnsavedChanges.value) {
      await proposedEvolutionsApi.update(props.evolution.id, {
        procedure_fields: buildPayload(),
      });
    }
    // Backend (proposed_evolutions_controller#approve) retorna
    // `{ data: <evolution>, clinical_note: { id, status } }`. O handler
    // do parent espera `{ evolution, clinical_note }` — normaliza aqui
    // pra não vazar a forma do envelope HTTP pro DetailPage.
    const { data } = await proposedEvolutionsApi.approve(props.evolution.id);
    emit('approved', {
      evolution: data.data,
      clinical_note: data.clinical_note,
    });
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
  if (!window.confirm('Recusar esta evolução? A proposta da IA será descartada (ação irreversível).')) {
    return;
  }
  isRejecting.value = true;
  error.value = null;
  try {
    const { data } = await proposedEvolutionsApi.reject(props.evolution.id, rejectReason.value);
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
  <section class="tcd-procedure" aria-label="Registro de procedimento">
    <header class="tcd-procedure__head">
      <h3 class="tcd-procedure__title">
        <i class="i-lucide-edit-3 w-5 h-5 tcd-procedure__title-icon" />
        <span>Registrar Procedimento</span>
      </h3>
      <div class="tcd-procedure__head-right">
        <span :class="['tcd-procedure__status', `tcd-procedure__status--${evolution.status}`]">
          {{ statusLabel }}
        </span>
        <span v-if="provider" class="tcd-procedure__provider">{{ provider }}</span>
      </div>
    </header>
    <p class="tcd-procedure__subtitle">
      Pré-preenchido pela IA a partir da transcrição. Revise e ajuste antes de assinar.
    </p>

    <div
      v-if="isApproved && evolution.clinical_note_id"
      class="tcd-procedure__banner tcd-procedure__banner--success"
    >
      Aplicada ao prontuário · ClinicalNote #{{ evolution.clinical_note_id }}
    </div>
    <div
      v-else-if="isRejected && evolution.reviewer_notes"
      class="tcd-procedure__banner tcd-procedure__banner--warning"
    >
      Recusada — {{ evolution.reviewer_notes }}
    </div>

    <!-- Seção 1: Informações Básicas (read-only, contexto do evento) -->
    <fieldset class="tcd-procedure__section">
      <legend class="tcd-procedure__section-title">Informações Básicas</legend>
      <div class="tcd-procedure__grid tcd-procedure__grid--2col">
        <div class="tcd-procedure__field">
          <label class="tcd-procedure__label">Data</label>
          <input
            type="text"
            class="tcd-procedure__input tcd-procedure__input--readonly"
            :value="dateLabel"
            readonly
          />
        </div>
        <div class="tcd-procedure__field">
          <label class="tcd-procedure__label">Profissional</label>
          <input
            type="text"
            class="tcd-procedure__input tcd-procedure__input--readonly"
            :value="professionalLabel"
            readonly
          />
        </div>
      </div>
    </fieldset>

    <!-- Seções 2-4: campos editáveis -->
    <fieldset
      v-for="section in fieldsBySection"
      :key="section.id"
      class="tcd-procedure__section"
    >
      <legend class="tcd-procedure__section-title">{{ section.title }}</legend>
      <div :class="['tcd-procedure__grid', section.id === 'procedimento' ? 'tcd-procedure__grid--3col' : 'tcd-procedure__grid--2col']">
        <div
          v-for="f in section.fields"
          :key="f.key"
          :class="['tcd-procedure__field', { 'tcd-procedure__field--full': f.type === 'textarea' }]"
        >
          <label class="tcd-procedure__label">
            {{ f.label }}
            <span v-if="f.required" class="tcd-procedure__label-req">*</span>
            <span v-if="isFieldAi(f.key)" class="tcd-procedure__ia-badge" title="Pré-preenchido pela BIA">
              <i class="i-lucide-sparkles w-3 h-3" />
              <span>BIA</span>
            </span>
          </label>
          <textarea
            v-if="f.type === 'textarea'"
            v-model="local[f.key]"
            class="tcd-procedure__input tcd-procedure__textarea"
            :rows="f.rows || 3"
            :placeholder="f.placeholder"
            :disabled="isFinalized"
          />
          <input
            v-else
            v-model="local[f.key]"
            :type="f.type"
            class="tcd-procedure__input"
            :placeholder="f.placeholder"
            :disabled="isFinalized"
          />
        </div>
      </div>
    </fieldset>

    <p v-if="error" class="tcd-procedure__error">{{ error }}</p>

    <!-- Audit 2026-05-26 — Termo de responsabilidade clínica. Conteúdo
         gerado por IA não pode virar prontuário sem confirmação explícita
         do profissional. Bloqueia o botão "Salvar e Assinar" até marcar. -->
    <label v-if="!isFinalized" class="tcd-procedure__confirm">
      <input
        v-model="confirmationChecked"
        type="checkbox"
        class="tcd-procedure__confirm-checkbox"
      />
      <span class="tcd-procedure__confirm-text">
        Confirmo que <strong>li integralmente</strong> esta evolução, fiz as
        modificações clínicas necessárias e <strong>concordo</strong> com o
        conteúdo que será aplicado ao prontuário do paciente. Assumo a
        autoria e responsabilidade clínica pelo registro.
      </span>
    </label>

    <footer v-if="!isFinalized" class="tcd-procedure__actions">
      <button
        type="button"
        class="tcd-btn tcd-btn--danger"
        :disabled="isApproving"
        @click="openReject"
      >
        Recusar
      </button>
      <div class="tcd-procedure__actions-right">
        <button
          type="button"
          class="tcd-btn tcd-btn--secondary"
          :disabled="isSaving || isApproving"
          @click="save"
        >
          <i class="i-lucide-save w-4 h-4" />
          <span>{{ isSaving ? 'Salvando…' : 'Salvar Rascunho' }}</span>
        </button>
        <button
          type="button"
          class="tcd-btn tcd-btn--primary"
          :disabled="isApproving || isSaving || !confirmationChecked"
          :title="!confirmationChecked ? 'Marque a confirmação acima para assinar' : ''"
          @click="approve"
        >
          <i class="i-lucide-check w-4 h-4" />
          <span>{{ isApproving ? 'Aplicando…' : 'Salvar e Assinar' }}</span>
        </button>
      </div>
    </footer>

    <!-- Modal de recusa -->
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
        <p v-if="error" class="tcd-procedure__error">{{ error }}</p>
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
