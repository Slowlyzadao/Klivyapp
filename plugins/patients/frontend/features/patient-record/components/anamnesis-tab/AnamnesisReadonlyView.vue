<script setup>
/**
 * AnamnesisReadonlyView — visualização tipo "documento" para anamnese assinada.
 *
 * Substitui os 5 sub-componentes de form quando `anamnesis.status === 'finalized'`.
 * Não reusa os componentes do form em modo disabled porque esse caminho gera
 * a sensação de "form quebrado" em vez de "documento finalizado". Aqui é UX
 * de leitura: banner verde de assinatura, valores em texto/badges/chips,
 * comorbidades positivas em destaque com resumo "sem comorbidades" quando
 * tudo for negativo (médico lê rápido, quer saber o que TEM).
 *
 * Estrutura espelha as 5 seções do form pra manter familiaridade visual:
 * mesmo `reg-section` + `reg-icon-*` que cada `*Section.vue` usa, mas com
 * conteúdo legível em vez de inputs.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';

const props = defineProps({
  anamnesis: { type: Object, required: true },
});

const { t } = useI18n();

const formatSignedAt = dateStr => {
  if (!dateStr) return '—';
  const d = new Date(dateStr);
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Sao_Paulo',
  });
};

const MEDICAL_HISTORY_LABELS = {
  hypertension: 'Hipertensão ou problemas cardiovasculares',
  diabetes: 'Diabetes',
  bleeding_disorder: 'Distúrbios de coagulação / hemorragia',
  pregnant: 'Gestante / Lactante',
  oncology: 'Tratamento oncológico',
  hepatitis: 'Hepatite / Doenças hepáticas',
};

const SURGICAL_FLAGS_LABELS = {
  has_recent_surgeries: 'Realizou cirurgias nos últimos 6 meses',
  has_implants: 'Possui implantes, próteses ou marcapasso',
  has_anesthesia_complications: 'Teve complicações ou reações com anestesia',
};

// Hábitos: mostra como Badge com intent semântico — "não/sedentário" = neutral,
// "atividade moderada/atleta" = success, "fumante regular/álcool frequente" = warning.
const HABIT_INTENT = {
  smoker: {
    Não: 'neutral',
    'Ex-fumante': 'info',
    'Sim, socialmente': 'warning',
    'Sim, regular': 'danger',
  },
  alcohol: {
    'Não consome': 'neutral',
    Ocasionalmente: 'info',
    Frequentemente: 'warning',
  },
  sports: {
    Sedentário: 'warning',
    'Atividade moderada': 'success',
    'Atleta / Alta intensidade': 'success',
  },
};

const positiveMedicalHistory = computed(() => {
  const mh = props.anamnesis.medical_history || {};
  return Object.keys(MEDICAL_HISTORY_LABELS)
    .filter(k => mh[k])
    .map(k => MEDICAL_HISTORY_LABELS[k]);
});

const positiveSurgicalFlags = computed(() => {
  const mh = props.anamnesis.medical_history || {};
  return Object.keys(SURGICAL_FLAGS_LABELS)
    .filter(k => mh[k])
    .map(k => SURGICAL_FLAGS_LABELS[k]);
});

const allergiesList = computed(() =>
  (props.anamnesis.allergies || []).filter(a => a && a.name)
);

const medicationsList = computed(() =>
  (props.anamnesis.current_medications || []).filter(m => m && m.name)
);

const habits = computed(() => {
  const h = props.anamnesis.relevant_habits || {};
  return [
    {
      label: 'Fumante',
      value: h.smoker || '—',
      intent: HABIT_INTENT.smoker[h.smoker] || 'neutral',
    },
    {
      label: 'Consumo de Álcool',
      value: h.alcohol || '—',
      intent: HABIT_INTENT.alcohol[h.alcohol] || 'neutral',
    },
    {
      label: 'Atividade Física',
      value: h.sports || '—',
      intent: HABIT_INTENT.sports[h.sports] || 'neutral',
    },
  ];
});

const signedAt = computed(() =>
  formatSignedAt(props.anamnesis.finalized_at || props.anamnesis.updated_at)
);
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="anr-root">
    <!-- Banner verde — selo de assinatura. Protagonista do topo. -->
    <header class="anr-banner">
      <div class="anr-banner-icon">
        <i class="i-lucide-shield-check w-5 h-5" />
      </div>
      <div class="anr-banner-text">
        <p class="anr-banner-title">Anamnese Assinada</p>
        <p class="anr-banner-meta">
          <i class="i-lucide-calendar w-3.5 h-3.5" />
          <span>{{ signedAt }}</span>
          <span v-if="anamnesis.version_number" class="anr-banner-sep">·</span>
          <span v-if="anamnesis.version_number">v{{ anamnesis.version_number }}</span>
        </p>
      </div>
      <span class="anr-banner-pill">FINALIZADA</span>
    </header>

    <div class="reg-form-grid">
      <!-- Motivo da Consulta -->
      <section class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-cyan">
              <i class="i-lucide-stethoscope w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.CHIEF_COMPLAINT.TITLE') }}
              </span>
              <span class="reg-section-subtitle">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.CHIEF_COMPLAINT.SUBTITLE') }}
              </span>
            </div>
          </div>
        </div>
        <div class="reg-section-body anr-body">
          <div class="anr-row">
            <span class="anr-label">Especialidade / Foco Principal</span>
            <span class="anr-value">{{ anamnesis.specialty || '—' }}</span>
          </div>
          <div class="anr-block">
            <span class="anr-label">Queixa Principal</span>
            <p class="anr-text">{{ anamnesis.chief_complaint || '—' }}</p>
          </div>
        </div>
      </section>

      <!-- Histórico de Saúde -->
      <section class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-blue">
              <i class="i-lucide-activity w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.TITLE') }}
              </span>
              <span class="reg-section-subtitle">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.MEDICAL_HISTORY.SUBTITLE') }}
              </span>
            </div>
          </div>
        </div>
        <div class="reg-section-body anr-body">
          <div v-if="positiveMedicalHistory.length === 0" class="anr-empty">
            <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
            Sem comorbidades relatadas.
          </div>
          <div v-else class="anr-chips">
            <span
              v-for="label in positiveMedicalHistory"
              :key="label"
              class="anr-chip anr-chip--alert"
            >
              <i class="i-lucide-alert-triangle w-3 h-3" />
              {{ label }}
            </span>
          </div>
          <div
            v-if="anamnesis.medical_history?.other"
            class="anr-block anr-mt"
          >
            <span class="anr-label">Outras Doenças ou Condições</span>
            <p class="anr-text">{{ anamnesis.medical_history.other }}</p>
          </div>
        </div>
      </section>

      <!-- Alergias e Medicamentos -->
      <section class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-red">
              <i class="i-lucide-pill w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.TITLE') }}
              </span>
              <span class="reg-section-subtitle">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.ALLERGIES.SUBTITLE') }}
              </span>
            </div>
          </div>
        </div>
        <div class="reg-section-body anr-body">
          <div class="anr-grid-2">
            <div>
              <span class="anr-label">Alergias Conhecidas</span>
              <div v-if="allergiesList.length === 0" class="anr-empty anr-mt-sm">
                <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
                Nenhuma alergia conhecida.
              </div>
              <div v-else class="anr-chips anr-mt-sm">
                <span
                  v-for="(a, i) in allergiesList"
                  :key="i"
                  class="anr-chip anr-chip--alert"
                >
                  {{ a.name }}
                </span>
              </div>
            </div>
            <div>
              <span class="anr-label">Medicamentos de Uso Contínuo</span>
              <div v-if="medicationsList.length === 0" class="anr-empty anr-mt-sm">
                <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
                Nenhuma medicação contínua.
              </div>
              <div v-else class="anr-chips anr-mt-sm">
                <span
                  v-for="(m, i) in medicationsList"
                  :key="i"
                  class="anr-chip anr-chip--info"
                >
                  {{ m.name }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Histórico Cirúrgico e Implantes -->
      <section class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-orange">
              <i class="i-lucide-scissors w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.SURGICAL.TITLE') }}
              </span>
              <span class="reg-section-subtitle">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.SURGICAL.SUBTITLE') }}
              </span>
            </div>
          </div>
        </div>
        <div class="reg-section-body anr-body">
          <div
            v-if="positiveSurgicalFlags.length === 0 && !anamnesis.surgical_history"
            class="anr-empty"
          >
            <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
            Nega cirurgias prévias e sem implantes ou reações a anestesia.
          </div>
          <template v-else>
            <div v-if="positiveSurgicalFlags.length > 0" class="anr-chips">
              <span
                v-for="label in positiveSurgicalFlags"
                :key="label"
                class="anr-chip anr-chip--alert"
              >
                <i class="i-lucide-alert-triangle w-3 h-3" />
                {{ label }}
              </span>
            </div>
            <div v-if="anamnesis.surgical_history" class="anr-block anr-mt">
              <span class="anr-label">Detalhes das Intervenções Recentes</span>
              <p class="anr-text">{{ anamnesis.surgical_history }}</p>
            </div>
          </template>
        </div>
      </section>

      <!-- Hábitos e Estilo de Vida -->
      <section class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-green">
              <i class="i-lucide-leaf w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.HABITS.TITLE') }}
              </span>
              <span class="reg-section-subtitle">
                {{ t('PATIENT_ANAMNESIS.SECTIONS.HABITS.SUBTITLE') }}
              </span>
            </div>
          </div>
        </div>
        <div class="reg-section-body anr-body">
          <div class="anr-grid-3">
            <div v-for="h in habits" :key="h.label" class="anr-habit-card">
              <span class="anr-habit-label">{{ h.label }}</span>
              <Badge :label="h.value" :intent="h.intent" size="sm" />
            </div>
          </div>
          <div v-if="anamnesis.additional_notes" class="anr-confidential">
            <div class="anr-confidential-header">
              <i class="i-lucide-shield w-4 h-4" />
              OBSERVAÇÕES CONFIDENCIAIS
            </div>
            <p>{{ anamnesis.additional_notes }}</p>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped lang="scss">
.anr-root {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

/* ── Banner verde de assinatura ─────────────────────────────────────── */
.anr-banner {
  display: flex;
  align-items: center;
  gap: 14px;
  background: linear-gradient(135deg, rgba(16, 185, 129, 0.12), rgba(16, 185, 129, 0.06));
  border: 1px solid rgba(16, 185, 129, 0.28);
  border-left: 4px solid #10b981;
  border-radius: 12px;
  padding: 14px 18px;
}

.anr-banner-icon {
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: rgba(16, 185, 129, 0.18);
  color: #047857;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.anr-banner-text {
  flex: 1;
  min-width: 0;
}

.anr-banner-title {
  font-size: 15px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0;
}

.anr-banner-meta {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: rgb(var(--slate-10));
  margin: 4px 0 0;
}

.anr-banner-sep {
  opacity: 0.4;
}

.anr-banner-pill {
  background: #10b981;
  color: #fff;
  padding: 4px 10px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.06em;
  flex-shrink: 0;
}

:root.dark .anr-banner-icon {
  color: #6ee7b7;
}

/* ── Body de cada seção em modo readonly ────────────────────────────── */
.anr-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.anr-row {
  display: grid;
  grid-template-columns: max-content 1fr;
  align-items: baseline;
  gap: 12px;
}

.anr-block {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.anr-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: rgb(var(--slate-9));
}

.anr-value {
  font-size: 14px;
  font-weight: 500;
  color: rgb(var(--slate-12));
}

.anr-text {
  font-size: 14px;
  line-height: 1.5;
  color: rgb(var(--slate-12));
  white-space: pre-wrap;
  margin: 0;
  padding: 0;
  background: transparent;
}

/* ── Chips ───────────────────────────────────────────────────────────── */
.anr-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.anr-chip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 4px 10px;
  border-radius: 99px;
  font-size: 12px;
  font-weight: 500;
  border: 1px solid transparent;
}

.anr-chip--alert {
  background: rgba(220, 38, 38, 0.10);
  color: #b91c1c;
  border-color: rgba(220, 38, 38, 0.28);
}

.anr-chip--info {
  background: rgba(37, 99, 235, 0.10);
  color: #1d4ed8;
  border-color: rgba(37, 99, 235, 0.28);
}

:root.dark .anr-chip--alert {
  background: rgba(220, 38, 38, 0.18);
  color: #fca5a5;
  border-color: rgba(220, 38, 38, 0.4);
}

:root.dark .anr-chip--info {
  background: rgba(59, 130, 246, 0.18);
  color: #93c5fd;
  border-color: rgba(59, 130, 246, 0.4);
}

/* ── Estado vazio (sem comorbidades / sem alergias / etc.) ──────────── */
.anr-empty {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: #047857;
  font-style: italic;
  padding: 8px 12px;
  background: rgba(16, 185, 129, 0.08);
  border: 1px solid rgba(16, 185, 129, 0.22);
  border-radius: 8px;
}

:root.dark .anr-empty {
  color: #6ee7b7;
  background: rgba(16, 185, 129, 0.14);
  border-color: rgba(16, 185, 129, 0.32);
}

/* ── Grids ──────────────────────────────────────────────────────────── */
.anr-grid-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 18px;
}

.anr-grid-3 {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
}

@media (max-width: 768px) {
  .anr-grid-2,
  .anr-grid-3 {
    grid-template-columns: 1fr;
  }
}

/* ── Hábitos: card pequeno com label + Badge ─────────────────────────── */
.anr-habit-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 12px 14px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  align-items: flex-start;
}

.anr-habit-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: rgb(var(--slate-9));
}

/* ── Bloco de observações confidenciais ──────────────────────────────── */
.anr-confidential {
  background: rgba(245, 158, 11, 0.08);
  border: 1px solid rgba(245, 158, 11, 0.25);
  border-left: 3px solid #f59e0b;
  border-radius: 8px;
  padding: 12px 14px;
}

.anr-confidential-header {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #b45309;
  margin-bottom: 8px;
}

.anr-confidential p {
  font-size: 13px;
  line-height: 1.5;
  color: rgb(var(--slate-12));
  margin: 0;
  white-space: pre-wrap;
}

:root.dark .anr-confidential-header {
  color: #fcd34d;
}

/* ── Spacing helpers ─────────────────────────────────────────────────── */
.anr-mt {
  margin-top: 8px;
}

.anr-mt-sm {
  margin-top: 6px;
}
</style>
