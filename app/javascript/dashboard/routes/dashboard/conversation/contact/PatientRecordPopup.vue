<script setup>
/* eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template */
import { ref, watch, computed } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';

const props = defineProps({
  contactId: {
    type: [Number, String],
    default: null,
  },
});

const emit = defineEmits(['close']);
const router = useRouter();
const route = useRoute();

const loading = ref(false);
const patient = ref(null);
const notFound = ref(false);

const fetchPatient = async () => {
  if (!props.contactId) return;
  loading.value = true;
  notFound.value = false;
  patient.value = null;
  try {
    const res = await PatientsAPI.byContact(props.contactId);
    patient.value = res.data?.payload || null;
  } catch {
    notFound.value = true;
  } finally {
    loading.value = false;
  }
};

watch(() => props.contactId, fetchPatient, { immediate: true });

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    timeZone: 'America/Sao_Paulo',
  });
};

const formatDateTime = dateStr => {
  if (!dateStr) return null;
  const d = new Date(dateStr);
  return {
    date: d.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      timeZone: 'America/Sao_Paulo',
    }),
    time: d.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'America/Sao_Paulo',
    }),
  };
};

const formatCurrency = val => {
  if (!val && val !== 0) return '—';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(val);
};

const getInitials = name => (name ? name.charAt(0).toUpperCase() : '?');

const hasValidSex = sex => {
  if (!sex) return false;
  return !['', 'nao_informado', 'não_informado', 'null'].includes(
    sex.toLowerCase().trim()
  );
};

const formatSex = sex => {
  if (!sex) return '';
  const m = { masculino: 'Masculino', feminino: 'Feminino' };
  return m[sex.toLowerCase()] || sex;
};

const parseInsurance = ins => {
  if (!ins) return null;
  let p = ins;
  if (typeof p === 'string') {
    try {
      p = JSON.parse(p);
    } catch {
      return null;
    }
  }
  if (p && typeof p === 'object' && p.name) return p;
  return null;
};

const STATUS_LABELS = {
  novo: 'Novo',
  ativo: 'Ativo',
  inativo: 'Inativo',
  faltoso: 'Faltoso',
  alta: 'Alta',
  arquivado: 'Arquivado',
};

const CONDITIONS_LABELS = {
  diabetes: 'Diabético(a)',
  hypertension: 'Hipertenso(a)',
  oncology: 'Oncológico(a)',
  hepatitis: 'Hepatite',
  has_implants: 'Implantes',
  bleeding_disorder: 'Distúrbio de coagulação',
  pregnant: 'Gestante',
};

const lastAppt = computed(() =>
  formatDateTime(patient.value?.last_appointment?.start_time)
);
const nextAppt = computed(() =>
  formatDateTime(patient.value?.next_appointment?.start_time)
);

const activeConditions = computed(() => {
  const conditions = patient.value?.clinical_summary?.conditions || {};
  return Object.entries(CONDITIONS_LABELS)
    .filter(([key]) => conditions[key] === true)
    .map(([, label]) => label);
});

const insurance = computed(() => parseInsurance(patient.value?.insurance));

const financial = computed(() => patient.value?.financial_status || null);

const hasAnyClinicalData = computed(() => {
  const cs = patient.value?.clinical_summary;
  if (!cs) return false;
  return (
    (cs.allergies || []).length > 0 ||
    (cs.current_medications || []).length > 0 ||
    activeConditions.value.length > 0 ||
    (cs.contraindications || []).length > 0
  );
});

const goToRecord = () => {
  if (!patient.value?.id) return;
  router.push({
    name: 'patients_dashboard_record',
    params: {
      accountId: route.params.accountId,
      patientId: patient.value.id,
    },
  });
  emit('close');
};
</script>

<template>
  <div class="prp-overlay" @click.self="$emit('close')">
    <div class="prp-panel" role="dialog" aria-modal="true">
      <!-- Header -->
      <div class="prp-header">
        <div class="prp-header-left">
          <i class="i-lucide-stethoscope prp-header-icon" />
          <span class="prp-header-title">Prontuário</span>
        </div>
        <button class="prp-close" @click="$emit('close')">
          <i class="i-lucide-x" />
        </button>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="prp-state">
        <div class="prp-spinner" />
        <span>Carregando prontuário…</span>
      </div>

      <!-- Não encontrado -->
      <div v-else-if="notFound || !patient" class="prp-state">
        <i class="prp-state-icon i-lucide-user-x" />
        <span class="prp-state-text">
          Nenhum prontuário vinculado a este contato.
        </span>
      </div>

      <!-- Conteúdo -->
      <div v-else class="prp-body">
        <!-- ── Identidade ── -->
        <div class="prp-identity">
          <div class="prp-avatar">
            <img
              v-if="patient.avatar_url"
              :src="patient.avatar_url"
              alt="avatar"
              class="prp-avatar-img"
            />
            <div v-else class="prp-avatar-placeholder">
              {{ getInitials(patient.name) }}
            </div>
            <span
              class="prp-status-dot"
              :class="`prp-dot-${patient.patient_status || 'novo'}`"
            />
          </div>
          <div class="prp-identity-info">
            <h3 class="prp-name">{{ patient.name }}</h3>
            <div class="prp-meta">
              <span v-if="patient.age">{{ patient.age }} anos</span>
              <span
                v-if="patient.age && hasValidSex(patient.sex)"
                class="prp-sep"
                >·</span>
              <span v-if="hasValidSex(patient.sex)">
                {{ formatSex(patient.sex) }}
              </span>
              <span class="prp-sep">·</span>
              <span
                class="prp-status-pill"
                :class="`prp-pill-${patient.patient_status || 'novo'}`"
              >
                {{
                  STATUS_LABELS[patient.patient_status] ||
                  patient.patient_status
                }}
              </span>
            </div>
            <div v-if="patient.birthdate" class="prp-chip-small">
              <i class="i-lucide-cake" />
              {{ formatDate(patient.birthdate) }}
            </div>
          </div>
        </div>

        <div class="prp-divider" />

        <!-- ── Layout de 2 colunas ── -->
        <div class="prp-two-col">
          <!-- COLUNA ESQUERDA -->
          <div class="prp-col">
            <!-- Alertas críticos -->
            <div
              v-if="
                patient.critical_alerts && patient.critical_alerts.length > 0
              "
              class="prp-section prp-section--danger"
            >
              <div class="prp-section-title">
                <i class="i-lucide-alert-triangle" />
                Alertas Críticos
              </div>
              <ul class="prp-list prp-list--danger">
                <li v-for="a in patient.critical_alerts" :key="a.id">
                  {{ a.message || a.title }}
                </li>
              </ul>
            </div>

            <!-- Consultas -->
            <div class="prp-section">
              <div class="prp-section-title">
                <i class="i-lucide-calendar-heart" />
                Consultas
              </div>
              <div class="prp-appt-row">
                <div class="prp-appt-block">
                  <span class="prp-appt-label">Última</span>
                  <template v-if="lastAppt">
                    <span class="prp-appt-date">{{ lastAppt.date }}</span>
                    <span class="prp-appt-time">{{ lastAppt.time }}</span>
                  </template>
                  <span v-else class="prp-empty">—</span>
                </div>
                <div class="prp-appt-sep" />
                <div class="prp-appt-block">
                  <span class="prp-appt-label prp-label-next">Próxima</span>
                  <template v-if="nextAppt">
                    <span class="prp-appt-date prp-date-next">{{
                      nextAppt.date
                    }}</span>
                    <span class="prp-appt-time">{{ nextAppt.time }}</span>
                  </template>
                  <span v-else class="prp-empty">—</span>
                </div>
              </div>
            </div>

            <!-- Contato -->
            <div class="prp-section">
              <div class="prp-section-title">
                <i class="i-lucide-contact" />
                Contato
              </div>
              <div class="prp-info-list">
                <div v-if="patient.phone" class="prp-info-row">
                  <i class="i-lucide-smartphone prp-info-icon" />
                  {{ patient.phone }}
                </div>
                <div v-if="patient.email" class="prp-info-row">
                  <i class="i-lucide-mail prp-info-icon" />
                  {{ patient.email }}
                </div>
                <div v-if="patient.cpf" class="prp-info-row">
                  <i class="i-lucide-credit-card prp-info-icon" />
                  {{ patient.cpf }}
                </div>
                <span
                  v-if="!patient.phone && !patient.email && !patient.cpf"
                  class="prp-empty"
                  >—</span>
              </div>
            </div>

            <!-- Convênio -->
            <div v-if="insurance" class="prp-section">
              <div class="prp-section-title">
                <i class="i-lucide-shield-plus" />
                Convênio
              </div>
              <div class="prp-kv-list">
                <div v-if="insurance.name" class="prp-kv-row">
                  <span class="prp-kv-label">Operadora</span>
                  <span class="prp-kv-value">{{ insurance.name }}</span>
                </div>
                <div v-if="insurance.plan" class="prp-kv-row">
                  <span class="prp-kv-label">Plano</span>
                  <span class="prp-kv-value">{{ insurance.plan }}</span>
                </div>
                <div v-if="insurance.number" class="prp-kv-row">
                  <span class="prp-kv-label">Carteirinha</span>
                  <span class="prp-kv-value">{{ insurance.number }}</span>
                </div>
                <div v-if="insurance.validity" class="prp-kv-row">
                  <span class="prp-kv-label">Validade</span>
                  <span class="prp-kv-value">{{ insurance.validity }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- COLUNA DIREITA -->
          <div class="prp-col">
            <!-- Nota fixada -->
            <div
              v-if="patient.pinned_note"
              class="prp-section prp-section--note"
            >
              <div class="prp-section-title">
                <i class="i-lucide-pin" />
                Nota Fixada
              </div>
              <p class="prp-pinned-text">{{ patient.pinned_note }}</p>
            </div>

            <!-- Clínico -->
            <div v-if="hasAnyClinicalData" class="prp-section">
              <div class="prp-section-title">
                <i class="i-lucide-heart-pulse" />
                Dados Clínicos
              </div>

              <!-- Condições -->
              <div
                v-if="activeConditions.length > 0"
                class="prp-clinical-block"
              >
                <span class="prp-clinical-label">Condições</span>
                <div class="prp-tags">
                  <span
                    v-for="cond in activeConditions"
                    :key="cond"
                    class="prp-tag prp-tag--condition"
                    >{{ cond }}</span>
                </div>
              </div>

              <!-- Alergias -->
              <div
                v-if="patient.clinical_summary.allergies.length > 0"
                class="prp-clinical-block"
              >
                <span class="prp-clinical-label">Alergias</span>
                <div class="prp-tags">
                  <span
                    v-for="a in patient.clinical_summary.allergies"
                    :key="a"
                    class="prp-tag prp-tag--allergy"
                    >{{ a }}</span>
                </div>
              </div>

              <!-- Medicamentos -->
              <div
                v-if="patient.clinical_summary.current_medications.length > 0"
                class="prp-clinical-block"
              >
                <span class="prp-clinical-label">Medicamentos</span>
                <div class="prp-tags">
                  <span
                    v-for="m in patient.clinical_summary.current_medications"
                    :key="m"
                    class="prp-tag prp-tag--med"
                    >{{ m }}</span>
                </div>
              </div>

              <!-- Contraindicações -->
              <div
                v-if="
                  (patient.clinical_summary.contraindications || []).length > 0
                "
                class="prp-clinical-block"
              >
                <span class="prp-clinical-label">Contraindicações</span>
                <div class="prp-tags">
                  <span
                    v-for="c in patient.clinical_summary.contraindications"
                    :key="c"
                    class="prp-tag prp-tag--contra"
                    >{{ c }}</span>
                </div>
              </div>
            </div>

            <!-- Financeiro minimalista -->
            <div v-if="financial" class="prp-section">
              <div class="prp-section-title">
                <i class="i-lucide-circle-dollar-sign" />
                Financeiro
              </div>
              <div class="prp-fin-list">
                <div class="prp-fin-row">
                  <span class="prp-fin-label">Total aprovado</span>
                  <span class="prp-fin-value">{{
                    formatCurrency(financial.total_approved)
                  }}</span>
                </div>
                <div class="prp-fin-row">
                  <span class="prp-fin-label">Pago / Recebido</span>
                  <span class="prp-fin-value prp-fin-paid">{{
                    formatCurrency(financial.total_paid)
                  }}</span>
                </div>
                <div class="prp-fin-row">
                  <span class="prp-fin-label">Em aberto</span>
                  <span
                    class="prp-fin-value"
                    :class="financial.total_open > 0 ? 'prp-fin-open' : ''"
                    >{{ formatCurrency(financial.total_open) }}</span>
                </div>
                <div class="prp-fin-row">
                  <span class="prp-fin-label">Devedor (vencido)</span>
                  <span
                    class="prp-fin-value"
                    :class="
                      financial.total_overdue > 0 ? 'prp-fin-overdue' : ''
                    "
                    >{{ formatCurrency(financial.total_overdue) }}</span>
                </div>
                <div v-if="financial.credit_balance > 0" class="prp-fin-row">
                  <span class="prp-fin-label">Crédito</span>
                  <span class="prp-fin-value prp-fin-credit">{{
                    formatCurrency(financial.credit_balance)
                  }}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- ── Footer ── -->
        <div class="prp-footer">
          <button class="prp-btn-record" @click="goToRecord">
            <i class="i-lucide-clipboard-list" />
            <span>Ver prontuário completo</span>
            <i class="i-lucide-arrow-right prp-btn-arrow" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ── Overlay ── */
.prp-overlay {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(0, 0, 0, 0.3);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 8px;
}

/* ── Panel: lateral direita ── */
.prp-panel {
  width: 460px;
  max-height: calc(100vh - 16px);
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  /* PROIBIDO box-shadow: 0 24px 64px rgba(0, 0, 0, 0.7) no light, maybe use a soft one or none. STYLE.md states:
     Modais: color rgb(var(--slate-1))
     Box-shadow: ❌ PROIBIDO in cards, but for overlays a small one maybe? It says "zero sombra, zero glow" */
  box-shadow: none;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  animation: prpSlideIn 0.22s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes prpSlideIn {
  from {
    opacity: 0;
    transform: translateX(16px) scale(0.98);
  }
  to {
    opacity: 1;
    transform: translateX(0) scale(1);
  }
}

/* ── Header ── */
.prp-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 18px;
  border-bottom: 1px solid rgb(var(--slate-4));
  flex-shrink: 0;
}

.prp-header-left {
  display: flex;
  align-items: center;
  gap: 8px;
  color: #3b82f6;
}

.prp-header-icon {
  font-size: 15px;
}

.prp-header-title {
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.prp-close {
  width: 28px;
  height: 28px;
  border: none;
  background: transparent;
  border-radius: 6px;
  cursor: pointer;
  color: rgb(var(--slate-9));
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 14px;
  transition:
    background 0.15s,
    color 0.15s;
}

.prp-close:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

/* ── States ── */
.prp-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 56px 24px;
  gap: 12px;
  color: rgb(var(--slate-9));
  font-size: 13px;
}

.prp-spinner {
  width: 24px;
  height: 24px;
  border: 2px solid rgb(var(--slate-4));
  border-top-color: #3b82f6;
  border-radius: 50%;
  animation: spin 0.7s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.prp-state-icon {
  font-size: 32px;
  opacity: 0.4;
}

.prp-state-text {
  text-align: center;
  max-width: 220px;
}

/* ── Body ── */
.prp-body {
  display: flex;
  flex-direction: column;
  overflow-y: auto;
  flex: 1;
}

.prp-body::-webkit-scrollbar {
  width: 4px;
}

.prp-body::-webkit-scrollbar-thumb {
  background: rgb(var(--slate-4));
  border-radius: 4px;
}

/* ── Identity ── */
.prp-identity {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px 18px 14px;
}

.prp-avatar {
  position: relative;
  flex-shrink: 0;
}

.prp-avatar-img,
.prp-avatar-placeholder {
  width: 52px;
  height: 52px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  font-weight: 700;
}

.prp-avatar-img {
  object-fit: cover;
  border: 1px solid rgb(var(--slate-4));
}

.prp-avatar-placeholder {
  background: rgba(59, 130, 246, 0.12);
  border: 1px solid rgba(59, 130, 246, 0.2);
  color: #2563eb;
}

.prp-status-dot {
  position: absolute;
  bottom: -2px;
  right: -2px;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  border: 2px solid rgb(var(--slate-1));
}

.prp-dot-novo {
  background: #3b82f6;
}
.prp-dot-ativo {
  background: #16a34a;
}
.prp-dot-inativo {
  background: #94a3b8;
}
.prp-dot-faltoso {
  background: #d97706;
}
.prp-dot-alta {
  background: #9333ea;
}
.prp-dot-arquivado {
  background: #64748b;
}

.prp-identity-info {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
}

.prp-name {
  margin: 0;
  font-size: 17px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.prp-meta {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  color: rgb(var(--slate-9));
}

.prp-sep {
  color: rgb(var(--slate-6));
}

.prp-status-pill {
  padding: 1px 7px;
  border-radius: 99px;
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border: 1px solid transparent;
}

.prp-pill-novo {
  background: rgba(59, 130, 246, 0.12);
  color: #2563eb;
  border-color: rgba(59, 130, 246, 0.2);
}
.prp-pill-ativo {
  background: rgba(22, 163, 74, 0.12);
  color: #16a34a;
  border-color: rgba(22, 163, 74, 0.2);
}
.prp-pill-inativo {
  background: rgba(100, 116, 139, 0.12);
  color: #475569;
  border-color: rgba(100, 116, 139, 0.2);
}
.prp-pill-faltoso {
  background: rgba(217, 119, 6, 0.12);
  color: #d97706;
  border-color: rgba(217, 119, 6, 0.2);
}
.prp-pill-alta {
  background: rgba(147, 51, 234, 0.12);
  color: #9333ea;
  border-color: rgba(147, 51, 234, 0.2);
}
.prp-pill-arquivado {
  background: rgba(100, 116, 139, 0.12);
  color: #475569;
  border-color: rgba(100, 116, 139, 0.2);
}

.prp-chip-small {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* ── Divider ── */
.prp-divider {
  height: 1px;
  background: rgb(var(--slate-4));
  margin: 0 18px;
}

/* ── Two col layout ── */
.prp-two-col {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0;
  padding: 12px 8px;
}

.prp-col {
  display: flex;
  flex-direction: column;
  padding: 0 6px;
}

/* ── Section ── */
.prp-section {
  padding: 10px 6px;
  border-bottom: 1px solid rgb(var(--slate-4));
}

.prp-section:last-child {
  border-bottom: none;
}

.prp-section--danger {
  background: rgba(220, 38, 38, 0.04);
  border-radius: 8px;
  border: 1px solid rgba(220, 38, 38, 0.15);
  margin-bottom: 8px;
  padding: 8px 10px;
}

.prp-section--note {
  background: rgba(217, 119, 6, 0.04);
  border-radius: 8px;
  border: 1px solid rgba(217, 119, 6, 0.15);
  margin-bottom: 8px;
  padding: 8px 10px;
}

.prp-section-title {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: rgb(var(--slate-9));
  margin-bottom: 8px;
}

.prp-section--danger .prp-section-title {
  color: #dc2626;
}

.prp-section--note .prp-section-title {
  color: #d97706;
}

/* ── Lists ── */
.prp-list {
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 3px;
}

.prp-list--danger li {
  font-size: 12px;
  color: #dc2626;
}

/* ── Appointments ── */
.prp-appt-row {
  display: flex;
  align-items: flex-start;
}

.prp-appt-block {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.prp-appt-sep {
  width: 1px;
  background: rgb(var(--slate-4));
  margin: 0 10px;
  align-self: stretch;
}

.prp-appt-label {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-11));
  margin-bottom: 2px;
}

.prp-label-next {
  color: #2563eb;
}

.prp-appt-date {
  font-size: 12px;
  font-weight: 500;
  color: rgb(var(--slate-11));
}

.prp-date-next {
  color: #16a34a;
}

.prp-appt-time {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* ── Info list ── */
.prp-info-list {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.prp-info-row {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: rgb(var(--slate-11));
}

.prp-info-icon {
  color: rgb(var(--slate-9));
  flex-shrink: 0;
  font-size: 12px;
}

/* ── KV list (convênio) ── */
.prp-kv-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.prp-kv-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.prp-kv-label {
  font-size: 11px;
  color: rgb(var(--slate-9));
  white-space: nowrap;
}

.prp-kv-value {
  font-size: 12px;
  color: rgb(var(--slate-11));
  text-align: right;
}

/* ── Clinical ── */
.prp-clinical-block {
  margin-bottom: 8px;
}

.prp-clinical-label {
  font-size: 10px;
  font-weight: 600;
  color: rgb(var(--slate-11));
  text-transform: uppercase;
  letter-spacing: 0.05em;
  display: block;
  margin-bottom: 4px;
}

.prp-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}

.prp-tag {
  font-size: 11px;
  font-weight: 500;
  padding: 2px 8px;
  border-radius: 6px;
  border: 1px solid transparent;
}

.prp-tag--condition {
  background: rgba(37, 99, 235, 0.12);
  color: #2563eb;
  border-color: transparent;
}

.prp-tag--allergy {
  background: rgba(220, 38, 38, 0.12);
  color: #dc2626;
  border-color: transparent;
}

.prp-tag--med {
  background: rgba(147, 51, 234, 0.12);
  color: #9333ea;
  border-color: transparent;
}

.prp-tag--contra {
  background: rgba(217, 119, 6, 0.12);
  color: #d97706;
  border-color: transparent;
}

.prp-pinned-text {
  margin: 0;
  font-size: 12px;
  color: rgb(var(--slate-11));
  line-height: 1.5;
}

/* ── Financeiro minimalista ── */
.prp-fin-list {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.prp-fin-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.prp-fin-label {
  font-size: 12px;
  color: rgb(var(--slate-9));
}

.prp-fin-value {
  font-size: 12px;
  font-weight: 500;
  color: rgb(var(--slate-11));
  font-variant-numeric: tabular-nums;
}

.prp-fin-paid {
  color: #16a34a;
}

.prp-fin-open {
  color: #d97706;
}

.prp-fin-overdue {
  color: #dc2626;
}

.prp-fin-credit {
  color: #2563eb;
}

/* ── Empty ── */
.prp-empty {
  font-size: 12px;
  color: rgb(var(--slate-9));
}

/* ── Footer ── */
.prp-footer {
  padding: 10px 14px 14px;
  border-top: 1px solid rgb(var(--slate-4));
  flex-shrink: 0;
}

.prp-btn-record {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 0 16px;
  height: 38px;
  background: rgba(59, 130, 246, 0.08);
  border: 1px solid rgba(59, 130, 246, 0.15);
  border-radius: 8px;
  color: #2563eb;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition:
    background 0.15s,
    border-color 0.15s;
}

.prp-btn-record:hover {
  background: rgba(59, 130, 246, 0.12);
  border-color: rgba(59, 130, 246, 0.25);
}

.prp-btn-arrow {
  margin-left: auto;
  opacity: 0.55;
}
</style>
