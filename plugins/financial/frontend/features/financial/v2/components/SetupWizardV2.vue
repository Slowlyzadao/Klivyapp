<script setup>
/**
 * Wizard de Configuração Financeira — canon Setup #1..#8 (2026-05-23).
 *
 * 8 etapas em 3 grupos visuais:
 *   - 3 OBRIGATÓRIAS — bloqueiam acesso ao módulo (Dashboard/A Pagar/etc)
 *     1. Plano de Contas (≥1 receita + ≥1 despesa)
 *     2. Contas Bancárias (≥1 ativa)
 *     3. Formas de Pagamento (≥1 ativa)
 *
 *   - 2 RECOMENDADAS — não bloqueiam mas avisam
 *     4. Profissionais (≥1 perfil financeiro)
 *     5. Procedimentos e Serviços (≥1 pricing)
 *
 *   - 3 OPCIONAIS — informativas
 *     6. Regras de Comissão
 *     7. Despesas Fixas
 *     8. Metas
 *
 * Cada card é clicável → navega pra `/financial/v2/settings/<tab>`.
 * Ao voltar, o componente recarrega o status via `refresh!` no backend.
 */
import { ref, computed, onMounted, onActivated } from 'vue';
import { useRouter } from 'vue-router';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FinancialV2 from '../api/financialV2';
import '@plugins/financial/frontend/styles/financial.scss';

const router = useRouter();
const notifyError = msg => useNotification.error(msg);

const setup = ref(null);
const loading = ref(false);

// Mapeia step.key (backend) → metadata visual + tab destino em /settings/<tab>
const STEPS_META = [
  {
    key: 'categories',         group: 'required',
    title: 'Plano de Contas',  icon: 'i-lucide-folder-tree',
    desc: 'Categorias de receita e despesa pra organizar o DRE.',
    tab: 'categories',
  },
  {
    key: 'bank_accounts',      group: 'required',
    title: 'Contas Bancárias', icon: 'i-lucide-landmark',
    desc: 'Onde o dinheiro entra e sai (corrente, poupança, caixa físico).',
    tab: 'bank-accounts',
  },
  {
    key: 'payment_methods',    group: 'required',
    title: 'Formas de Pagamento', icon: 'i-lucide-credit-card',
    desc: 'Dinheiro, PIX, cartão, boleto — métodos aceitos pela clínica.',
    tab: 'payment-methods',
  },
  {
    key: 'agent_profiles',     group: 'recommended',
    title: 'Profissionais',    icon: 'i-lucide-users',
    desc: 'Perfil financeiro de cada colaborador (vínculo, CRO, comissão).',
    tab: 'agents',
  },
  {
    key: 'services',           group: 'recommended',
    title: 'Procedimentos e Serviços', icon: 'i-lucide-scissors',
    desc: 'Preço e categoria DRE dos serviços cadastrados na agenda.',
    tab: 'services',
  },
  {
    key: 'commission_rules',   group: 'optional',
    title: 'Regras de Comissão', icon: 'i-lucide-percent',
    desc: 'Como cada profissional recebe comissão (% / valor fixo).',
    tab: 'commission',
  },
  {
    key: 'recurring_expenses', group: 'optional',
    title: 'Despesas Fixas',   icon: 'i-lucide-repeat',
    desc: 'Aluguel, sistema, internet — geração automática mensal.',
    tab: 'recurring',
  },
  {
    key: 'revenue_goal',       group: 'optional',
    title: 'Metas',            icon: 'i-lucide-target',
    desc: 'Metas de receita com 3 tiers (Mínima/Principal/Desafio).',
    tab: 'goals',
  },
];

const GROUP_META = {
  required:    { label: 'Obrigatório', badge: 'OBRIGATÓRIO', tone: 'danger' },
  recommended: { label: 'Recomendado', badge: 'RECOMENDADO', tone: 'warn' },
  optional:    { label: 'Opcional',    badge: 'OPCIONAL',    tone: 'neutral' },
};

async function load() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.setup.show();
    setup.value = data;
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao carregar setup');
  } finally {
    loading.value = false;
  }
}

onMounted(load);
onActivated(load); // recarrega quando volta de /settings/<tab>

const stepsByGroup = computed(() => {
  if (!setup.value) return { required: [], recommended: [], optional: [] };
  const groups = { required: [], recommended: [], optional: [] };
  STEPS_META.forEach(meta => {
    const done = !!setup.value.steps?.[meta.key];
    groups[meta.group].push({ ...meta, done });
  });
  return groups;
});

const requiredDone = computed(() => setup.value?.required_steps_done || false);
const progressPct  = computed(() => setup.value?.progress_percent || 0);

function goToTab(step) {
  router.push({ name: 'financial_v2_settings_tab', params: { tab: step.tab } });
}

function goToDashboard() {
  router.push({ name: 'financial_v2_dashboard' });
}
</script>

<template>
  <div class="finv2-page finv2-page--setup">
    <header class="finv2-page__header">
      <div>
        <h1 class="finv2-page__title">Configurar Módulo Financeiro</h1>
        <p class="finv2-page__subtitle">
          Conclua os passos abaixo para liberar o uso. Sem os
          <strong>obrigatórios</strong>, lançamentos caem em "Sem categoria" e
          o DRE fica incompleto.
        </p>
      </div>
    </header>

    <div class="finv2-page__body setup-v2">
      <!-- Progresso -->
      <section v-if="setup" class="setup-v2__progress">
        <div class="setup-v2__progress-bar">
          <div class="setup-v2__progress-fill" :style="{ width: progressPct + '%' }" />
        </div>
        <div class="setup-v2__progress-meta">
          <strong>{{ progressPct }}%</strong> concluído ·
          <span v-if="requiredDone" class="setup-v2__progress-ok">
            ✓ Obrigatórios prontos — você já pode usar o módulo
          </span>
          <span v-else class="setup-v2__progress-warn">
            ⚠ Complete os obrigatórios para liberar o módulo
          </span>
        </div>
        <BeclinicButton
          v-if="requiredDone"
          variant="solid"
          color="blue"
          icon="i-lucide-arrow-right"
          label="Ir para Dashboard"
          @click="goToDashboard"
        />
        <p v-if="requiredDone" class="setup-v2__progress-hint">
          Os passos <strong>recomendados</strong> e <strong>opcionais</strong>
          abaixo não bloqueiam o módulo — configure agora ou volte quando quiser
          por <strong>Configurações › Assistente de configuração</strong>.
        </p>
      </section>

      <!-- Loading -->
      <div v-if="loading && !setup" class="setup-v2__state">
        <div class="setup-v2__spinner" />
        <span>Carregando configuração...</span>
      </div>

      <!-- Grupos -->
      <template v-for="groupKey in ['required', 'recommended', 'optional']" v-else :key="groupKey">
        <section v-if="stepsByGroup[groupKey].length" class="setup-v2__group">
          <header class="setup-v2__group-header">
            <h2 class="setup-v2__group-title">{{ GROUP_META[groupKey].label }}</h2>
            <span class="setup-v2__group-badge" :class="`setup-v2__group-badge--${GROUP_META[groupKey].tone}`">
              {{ GROUP_META[groupKey].badge }}
            </span>
          </header>
          <div class="setup-v2__cards">
            <button
              v-for="step in stepsByGroup[groupKey]"
              :key="step.key"
              type="button"
              class="setup-v2__card"
              :class="{ 'setup-v2__card--done': step.done }"
              @click="goToTab(step)"
            >
              <div class="setup-v2__card-icon">
                <i :class="step.icon" />
              </div>
              <div class="setup-v2__card-content">
                <div class="setup-v2__card-head">
                  <h3 class="setup-v2__card-title">{{ step.title }}</h3>
                  <span v-if="step.done" class="setup-v2__card-status setup-v2__card-status--done">
                    <i class="i-lucide-check" /> Feito
                  </span>
                  <span v-else class="setup-v2__card-status setup-v2__card-status--pending">
                    Pendente
                  </span>
                </div>
                <p class="setup-v2__card-desc">{{ step.desc }}</p>
              </div>
              <i class="i-lucide-chevron-right setup-v2__card-arrow" />
            </button>
          </div>
        </section>
      </template>
    </div>
  </div>
</template>

<style scoped lang="scss">
.finv2-page--setup {
  overflow-y: auto;
}

.setup-v2 {
  max-width: 880px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 28px;
}

/* ── Barra de progresso ────────────────────────────────────── */
.setup-v2__progress {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 18px 20px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  position: relative;
}
.setup-v2__progress-bar {
  width: 100%;
  height: 8px;
  background: rgb(var(--slate-4));
  border-radius: 999px;
  overflow: hidden;
}
.setup-v2__progress-fill {
  height: 100%;
  background: linear-gradient(90deg, rgb(var(--blue-9)), rgb(var(--teal-9)));
  transition: width 0.3s ease;
}
.setup-v2__progress-meta {
  font-size: 13px;
  color: rgb(var(--slate-10));
  strong { color: rgb(var(--slate-12)); }
}
.setup-v2__progress-ok   { color: rgb(var(--teal-11)); }
.setup-v2__progress-warn { color: rgb(var(--amber-11)); }
.setup-v2__progress-hint {
  margin: 2px 0 0;
  font-size: 12px;
  line-height: 1.5;
  color: rgb(var(--slate-10));
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}

/* ── Loading state ─────────────────────────────────────────── */
.setup-v2__state {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 60px 24px;
  gap: 12px;
  color: rgb(var(--slate-9));
}
.setup-v2__spinner {
  width: 18px; height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ── Grupo de passos ───────────────────────────────────────── */
.setup-v2__group {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.setup-v2__group-header {
  display: flex;
  align-items: center;
  gap: 10px;
}
.setup-v2__group-title {
  margin: 0;
  font-size: 14px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-11));
}
.setup-v2__group-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 5px;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.06em;

  &--danger  { background: rgba(244, 63, 94, 0.15);   color: rgb(var(--ruby-11)); }
  &--warn    { background: rgba(245, 158, 11, 0.15);  color: rgb(var(--amber-11)); }
  &--neutral { background: rgba(100, 116, 139, 0.15); color: rgb(var(--slate-10)); }
}

/* ── Cards de passo ────────────────────────────────────────── */
/* Cores via RGBA com alpha (não via tokens --emerald-2/--ruby-2 que ficam
   quase pretos em dark mode — ver CHANGELOG hotfix 2026-04). Alphas baixos
   funcionam em ambos modos sem precisar de override `:root.dark`. */
.setup-v2__cards {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.setup-v2__card {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 16px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 12px;
  text-align: left;
  cursor: pointer;
  transition: background 0.12s ease, border-color 0.12s ease, transform 0.06s ease;

  &:hover {
    background: rgb(var(--slate-3));
    border-color: rgb(var(--blue-8));
  }
  &:active { transform: translateY(1px); }

  &--done {
    background: rgba(16, 185, 129, 0.07);
    border-color: rgba(16, 185, 129, 0.45);

    &:hover {
      background: rgba(16, 185, 129, 0.10);
      border-color: rgba(16, 185, 129, 0.6);
    }
  }
}
.setup-v2__card-icon {
  width: 44px;
  height: 44px;
  border-radius: 10px;
  background: rgb(var(--slate-3));
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;

  i {
    width: 22px;
    height: 22px;
    color: rgb(var(--blue-9));
  }

  .setup-v2__card--done & {
    background: rgba(16, 185, 129, 0.18);
    i { color: rgb(var(--teal-10)); }
  }
}
.setup-v2__card-content {
  flex: 1;
  min-width: 0;
}
.setup-v2__card-head {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 4px;
}
.setup-v2__card-title {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.setup-v2__card-status {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.05em;
  i { width: 12px; height: 12px; }

  &--done    { background: rgba(16, 185, 129, 0.18); color: rgb(var(--teal-11)); }
  &--pending { background: rgba(100, 116, 139, 0.15); color: rgb(var(--slate-10)); }
}
.setup-v2__card-desc {
  margin: 0;
  font-size: 13px;
  color: rgb(var(--slate-9));
  line-height: 1.45;
}
.setup-v2__card-arrow {
  width: 18px;
  height: 18px;
  color: rgb(var(--slate-9));
  flex-shrink: 0;
}
</style>
