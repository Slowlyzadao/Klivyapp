<script setup>
/**
 * ClinicalGuardModal — Aviso forte exibido quando um procedimento ou produto
 * cruza com alergias / contraindicações / medicações registradas na anamnese.
 *
 * Diferente do ConfirmDangerModal:
 *   - cor âmbar (atenção) ao invés de ruby (destrutivo)
 *   - lista visual das contraindicações detectadas
 *   - exige justificativa textual (>= 10 chars) para liberar o "Continuar mesmo assim"
 *   - emit `confirm(reason)` carrega a justificativa para o caller logar
 *
 * Roadmap #16 — não bloqueia o procedimento, mas força registro consciente.
 */
import { computed, ref, watch } from 'vue';
import BeclinicButton from './Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  conflicts: { type: Array, default: () => [] },
  procedureName: { type: String, default: '' },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['update:show', 'confirm', 'cancel']);

const reason = ref('');

// Reset textarea sempre que o modal reabre — evita carregar justificativa
// de um override anterior em outro paciente/procedimento.
watch(
  () => props.show,
  shown => {
    if (shown) reason.value = '';
  }
);

const trimmedReason = computed(() => reason.value.trim());
const reasonValid = computed(() => trimmedReason.value.length >= 10);

const SEVERITY_LABELS = {
  high: 'Alta',
  medium: 'Média',
  low: 'Baixa',
  unknown: '—',
};

const KIND_ICONS = {
  allergy: 'i-lucide-zap',
  contraindication: 'i-lucide-ban',
  medication: 'i-lucide-pill',
};

const close = () => {
  if (props.loading) return;
  emit('update:show', false);
  emit('cancel');
};

const onConfirm = () => {
  if (props.loading || !reasonValid.value) return;
  emit('confirm', trimmedReason.value);
};
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <Teleport to="body">
    <div
      v-if="show"
      class="cgm-overlay"
      role="dialog"
      aria-modal="true"
      @click.self="close"
    >
      <div class="cgm-card">
        <div class="cgm-header">
          <div class="cgm-icon-wrap">
            <i class="i-lucide-shield-alert cgm-icon" />
          </div>
          <div class="cgm-text">
            <h3 class="cgm-title">Atenção clínica — conflito detectado</h3>
            <p class="cgm-subtitle">
              A anamnese do paciente registra itens que conflitam com este
              procedimento{{ procedureName ? ` (${procedureName})` : '' }}.
              Confirme que está ciente antes de prosseguir.
            </p>
          </div>
        </div>

        <ul class="cgm-conflicts">
          <li v-for="(c, idx) in conflicts" :key="idx" class="cgm-conflict">
            <i :class="['cgm-conflict-icon', KIND_ICONS[c.kind] || 'i-lucide-alert-triangle']" />
            <div class="cgm-conflict-body">
              <strong>{{ c.label }}</strong>
              <span v-if="c.severity && c.severity !== 'unknown'" class="cgm-badge">
                Severidade: {{ SEVERITY_LABELS[c.severity] || c.severity }}
              </span>
              <p v-if="c.details" class="cgm-conflict-details">{{ c.details }}</p>
            </div>
          </li>
        </ul>

        <div class="cgm-reason">
          <label for="cgm-reason-input" class="cgm-reason-label">
            Justificativa clínica (mín. 10 caracteres)
          </label>
          <textarea
            id="cgm-reason-input"
            v-model="reason"
            class="cgm-reason-input"
            rows="3"
            placeholder="Ex.: Paciente confirmou que tolera o produto em dose reduzida; teste prévio realizado em consulta anterior."
            :disabled="loading"
          />
          <p v-if="reason && !reasonValid" class="cgm-reason-error">
            Descreva a justificativa clínica com pelo menos 10 caracteres.
          </p>
        </div>

        <div class="cgm-footer">
          <BeclinicButton
            type="button"
            variant="ghost"
            color="slate"
            label="Cancelar"
            :disabled="loading"
            @click="close"
          />
          <BeclinicButton
            type="button"
            variant="solid"
            color="amber"
            label="Continuar mesmo assim"
            :is-loading="loading"
            :disabled="loading || !reasonValid"
            @click="onConfirm"
          />
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.cgm-overlay {
  position: fixed;
  inset: 0;
  z-index: 99999;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.6);
  backdrop-filter: blur(4px);
}

.cgm-card {
  width: 100%;
  max-width: 520px;
  background: linear-gradient(145deg, #1e293b, #0f172a);
  border: 1px solid rgba(245, 158, 11, 0.2); /* amber-500/20 */
  border-radius: 16px;
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
  overflow: hidden;
  max-height: 90vh;
  display: flex;
  flex-direction: column;
}

.cgm-header {
  padding: 24px 24px 16px;
  display: flex;
  align-items: flex-start;
  gap: 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
}

.cgm-icon-wrap {
  flex-shrink: 0;
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: rgba(245, 158, 11, 0.12);
  display: flex;
  align-items: center;
  justify-content: center;
}

.cgm-icon {
  width: 22px;
  height: 22px;
  color: #f59e0b; /* amber-500 */
}

.cgm-text {
  flex: 1;
  min-width: 0;
}

.cgm-title {
  margin: 0 0 6px;
  font-weight: 600;
  font-size: 1.0625rem;
  color: #fbbf24; /* amber-400 */
}

.cgm-subtitle {
  margin: 0;
  font-size: 0.875rem;
  line-height: 1.5;
  color: #cbd5e1; /* slate-300 */
}

.cgm-conflicts {
  list-style: none;
  margin: 0;
  padding: 16px 24px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  overflow-y: auto;
  max-height: 240px;
}

.cgm-conflict {
  display: flex;
  gap: 12px;
  padding: 10px 12px;
  background: rgba(245, 158, 11, 0.05);
  border: 1px solid rgba(245, 158, 11, 0.15);
  border-radius: 8px;
}

.cgm-conflict-icon {
  flex-shrink: 0;
  width: 18px;
  height: 18px;
  color: #f59e0b;
  margin-top: 2px;
}

.cgm-conflict-body {
  flex: 1;
  min-width: 0;
  font-size: 0.875rem;
  color: #f1f5f9;
}

.cgm-conflict-body strong {
  display: block;
  font-weight: 600;
  margin-bottom: 2px;
}

.cgm-badge {
  display: inline-block;
  margin-top: 4px;
  padding: 2px 8px;
  background: rgba(245, 158, 11, 0.15);
  color: #fbbf24;
  border-radius: 999px;
  font-size: 0.75rem;
  font-weight: 500;
}

.cgm-conflict-details {
  margin: 6px 0 0;
  font-size: 0.8125rem;
  color: #94a3b8;
}

.cgm-reason {
  padding: 16px 24px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}

.cgm-reason-label {
  display: block;
  margin-bottom: 8px;
  font-size: 0.8125rem;
  font-weight: 500;
  color: #cbd5e1;
}

.cgm-reason-input {
  width: 100%;
  background: rgba(15, 23, 42, 0.6);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 8px;
  padding: 10px 12px;
  color: #f1f5f9;
  font-size: 0.875rem;
  font-family: inherit;
  resize: vertical;
  min-height: 72px;
}

.cgm-reason-input:focus {
  outline: none;
  border-color: rgba(245, 158, 11, 0.4);
}

.cgm-reason-input:disabled {
  opacity: 0.5;
}

.cgm-reason-error {
  margin: 6px 0 0;
  font-size: 0.75rem;
  color: #f87171;
}

.cgm-footer {
  padding: 16px 24px;
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}
</style>
