<script setup>
/**
 * Tab "Profissionais" — wireframe 2026-05-23.
 *
 * Lista TODOS os Users da conta (core Klivy) + perfil financeiro 1-to-1
 * (Financial::AgentProfile). Users sem profile aparecem destacados ("Sem
 * configuração financeira") — comissões/folha não disponíveis até configurar.
 *
 * Colunas:
 *   NOME (+ badge REAL) | CATEGORIA | VÍNCULO | PRODUÇÃO REAL | ORÇAMENTOS |
 *   PACIENTES | COMISSIONADO | STATUS | AÇÕES
 *
 * Stats agregados em batch (sem N+1) via Budget aprovados/concluídos.
 *
 * Endpoints (Fase 2A + stats Fase 2B-profissionais):
 *   GET    /financial/v2/agent_profiles?include_stats=true → [{ user, profile, stats }]
 *   PUT    /financial/v2/agent_profiles/:user_id  (upsert)
 *   DELETE /financial/v2/agent_profiles/:user_id  (deactivate)
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Toggle from '@plugins/beclinic_core/frontend/components/Toggle.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import FinancialV2 from '../../api/financialV2';
import AgentProfileFormModalV2 from './AgentProfileFormModalV2.vue';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const rows = ref([]); // [{ user, profile, stats }]
const loading = ref(false);
const errorState = ref(null);

const showModal = ref(false);
const modalUser = ref(null);
const modalProfile = ref(null);
const modalIsNewUser = ref(false);

async function load() {
  loading.value = true;
  errorState.value = null;
  try {
    const res = await FinancialV2.agentProfiles.index({ include_stats: 'true' });
    rows.value = res?.data?.data || [];
  } catch (err) {
    errorState.value = err?.response?.data?.message || 'Erro ao carregar profissionais';
    notifyError(errorState.value);
  } finally {
    loading.value = false;
  }
}

onMounted(load);

// ── Stats agregadas pro subtitle ─────────────────────────────────────
const configuredCount = computed(() => rows.value.filter(r => r.profile).length);
const totalCount = computed(() => rows.value.length);

// ── Formatadores ─────────────────────────────────────────────────────
function formatBRL(cents) {
  if (cents == null || cents === 0) return '—';
  const v = cents / 100;
  if (Number.isInteger(v)) return 'R$ ' + v.toLocaleString('pt-BR');
  return 'R$ ' + v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatNumber(n) {
  if (!n || n === 0) return '—';
  return n.toLocaleString('pt-BR');
}

// Display amigável de categoria/vínculo
const CATEGORY_LABELS = {
  profissional: 'Profissional',
  operacional: 'Operacional',
  comercial: 'Comercial',
  administrador: 'Administrador',
};

const BOND_LABELS = {
  PJ: 'PJ',
  PF: 'PF',
  CLT: 'CLT',
  Socio: 'Sócio',
};

const BOND_CLASSES = {
  PJ: 'bond--pj',
  PF: 'bond--pf',
  CLT: 'bond--clt',
  Socio: 'bond--socio',
};

function categoryLabel(category) {
  return CATEGORY_LABELS[category] || category || '—';
}

function bondLabel(bond) {
  return BOND_LABELS[bond] || bond || '—';
}

function bondClass(bond) {
  return BOND_CLASSES[bond] || '';
}

// ── Ações ─────────────────────────────────────────────────────────────
function openModalForNew() {
  modalUser.value = null;
  modalProfile.value = null;
  modalIsNewUser.value = false; // o modal escolhe entre "linkar" e "criar"
  showModal.value = true;
}

function openModalForRow(row) {
  modalUser.value = row.user;
  modalProfile.value = row.profile;
  modalIsNewUser.value = false;
  showModal.value = true;
}

// Toggle inline ativa/inativa (PATCH update via upsert) — mesma metáfora
// visual de Bank Accounts / Payment Methods. Otimista: atualiza UI já,
// reverte em caso de erro. Backend aceita PUT parcial (assign_attributes
// só sobrescreve `status`, demais campos do profile permanecem intactos).
async function onToggleStatus(row, isActive) {
  if (!row.profile) return;
  const previous = row.profile.status;
  const next = isActive ? 'active' : 'inactive';
  row.profile.status = next; // otimista
  try {
    await FinancialV2.agentProfiles.upsert(row.user.id, {
      agent_profile: { status: next },
    });
    notifySuccess(isActive ? 'Profissional ativado.' : 'Profissional inativado.');
    await load();
  } catch (err) {
    row.profile.status = previous; // rollback
    notifyError(
      err?.response?.data?.errors?.join('; ') ||
      err?.response?.data?.message ||
      'Erro ao alterar status'
    );
  }
}

function onProfileSaved() {
  showModal.value = false;
  load();
}

async function onProfileDeactivate(userId) {
  // Sem confirm() inline — modal vai cuidar disso na próxima iteração
  // (regra do user: substituir window.confirm por modais dedicados).
  try {
    await FinancialV2.agentProfiles.deactivate(userId);
    notifySuccess('Perfil financeiro inativado. User core permanece intacto.');
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao inativar');
  }
}

// ── Linhas separadas: configurados primeiro, sem-configuração depois ─
const sortedRows = computed(() => {
  const configured = rows.value.filter(r => r.profile);
  const unconfigured = rows.value.filter(r => !r.profile);
  return [...configured, ...unconfigured];
});
</script>

<template>
  <div class="agtab">
    <header class="agtab-header">
      <div>
        <h2 class="agtab-title">Profissionais</h2>
        <p class="agtab-subtitle">
          Setup #1 · Base de tudo. Identidade vem do User core (gerenciado em
          <strong>Configurações &gt; Agentes</strong>). Aqui ficam dados específicos do
          financeiro: vínculo, categoria, CRO, dados bancários, comissionamento.
          <span v-if="totalCount > 0" class="agtab-subtitle-count">
            · {{ configuredCount }}/{{ totalCount }} configurados
          </span>
        </p>
      </div>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Adicionar"
        class="finv2-btn-icon-only-mobile"
        @click="openModalForNew"
      />
    </header>

    <!-- Loading -->
    <div v-if="loading && rows.length === 0" class="agtab-loading">
      <div class="agtab-spinner" />
      <span>Carregando profissionais...</span>
    </div>

    <!-- Error -->
    <div v-else-if="errorState" class="agtab-error">
      <i class="i-lucide-alert-circle" />
      <div>
        <strong>Não foi possível carregar.</strong>
        <p>{{ errorState }}</p>
      </div>
      <BeclinicButton variant="ghost" color="slate" label="Tentar de novo" @click="load" />
    </div>

    <!-- Empty -->
    <div v-else-if="rows.length === 0" class="agtab-empty">
      <i class="i-lucide-users" />
      <h3>Nenhum usuário cadastrado</h3>
      <p>Crie usuários em <strong>Configurações &gt; Agentes</strong> ou clique em <strong>Adicionar</strong> aqui.</p>
    </div>

    <!-- Conteúdo -->
    <div v-else class="agtab-content">
      <div class="agtab-table-wrap">
        <table class="agtab-table">
          <thead>
            <tr>
              <th class="agtab-th-name">NOME</th>
              <th class="agtab-th-category">CATEGORIA</th>
              <th class="agtab-th-bond">VÍNCULO</th>
              <th class="agtab-th-prod">PRODUÇÃO REAL</th>
              <th class="agtab-th-orc">ORÇAMENTOS</th>
              <th class="agtab-th-pac">PACIENTES</th>
              <th class="agtab-th-comm">COMISSIONADO</th>
              <th class="agtab-th-status">STATUS</th>
              <th class="agtab-th-actions"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in sortedRows" :key="row.user.id"
                class="agtab-row"
                :class="{ 'agtab-row--unconfigured': !row.profile }">
              <td class="agtab-td-name">
                <Avatar
                  :src="row.user.avatar_url || ''"
                  :name="row.user.name"
                  :size="28"
                  rounded-full
                />
                <span class="agtab-name-text">{{ row.user.name }}</span>
                <!-- Badge REAL só pra perfis configurados — comunica "este usuário
                     tem perfil financeiro ativo". Usuários sem perfil já são sinalizados
                     pela categoria "não configurada", status âmbar e botão verde de
                     configurar; um badge adicional aqui seria ruído. -->
                <span v-if="row.profile" class="agtab-badge agtab-badge--real">REAL</span>
              </td>
              <td class="agtab-td-category">
                <template v-if="row.profile">{{ categoryLabel(row.profile.agent_category) }}</template>
                <span v-else class="agtab-missing">não configurada</span>
              </td>
              <td class="agtab-td-bond">
                <span v-if="row.profile" class="agtab-bond-badge" :class="bondClass(row.profile.bond_type)">
                  {{ bondLabel(row.profile.bond_type) }}
                </span>
                <span v-else>—</span>
              </td>
              <td class="agtab-td-prod">{{ formatBRL(row.stats?.producao_real_cents) }}</td>
              <td class="agtab-td-orc">{{ formatNumber(row.stats?.orcamentos_count) }}</td>
              <td class="agtab-td-pac">{{ formatNumber(row.stats?.pacientes_count) }}</td>
              <td class="agtab-td-comm">
                <template v-if="row.profile">
                  <span v-if="row.profile.commissionable" class="agtab-comm-yes">✓ SIM</span>
                  <span v-else class="agtab-comm-no">NÃO</span>
                </template>
                <span v-else>—</span>
              </td>
              <td class="agtab-td-status">
                <!-- Toggle inline (mesma régua de Bank Accounts/Payment Methods).
                     Azul = ativo, cinza = inativo. Sem badge texto. -->
                <Toggle
                  v-if="row.profile"
                  :model-value="row.profile.status === 'active'"
                  @update:model-value="(v) => onToggleStatus(row, v)"
                />
                <span v-else class="agtab-status agtab-status--warn">⚠ Pendente</span>
              </td>
              <td class="agtab-td-actions">
                <BeclinicButton
                  v-if="!row.profile"
                  variant="solid"
                  color="blue"
                  size="sm"
                  icon="i-lucide-plus"
                  label="Configurar"
                  @click="openModalForRow(row)"
                />
                <div v-else class="agtab-actions-group">
                  <Tooltip label="Editar profissional">
                    <button
                      type="button"
                      class="agtab-icon-btn"
                      @click="openModalForRow(row)"
                    >
                      <i class="i-lucide-pencil" />
                    </button>
                  </Tooltip>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Modal -->
    <AgentProfileFormModalV2
      v-if="showModal"
      :show="showModal"
      :user="modalUser"
      :existing-profile="modalProfile"
      :existing-users="rows.map(r => r.user)"
      :users-with-profile="new Set(rows.filter(r => r.profile).map(r => r.user.id))"
      @close="showModal = false"
      @confirm="onProfileSaved"
      @deactivate="onProfileDeactivate"
    />
  </div>
</template>

<style scoped lang="scss">
.agtab {
  /* Padding agora vem do `.finset__main` do parent (SettingsV2). */
  color: rgb(var(--slate-12));
}

.agtab-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 20px;
  padding-bottom: 16px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.agtab-title {
  margin: 0 0 6px;
  font-size: 22px;
  font-weight: 700;
}
.agtab-subtitle {
  margin: 0;
  font-size: 13px;
  color: rgb(var(--slate-10));
  line-height: 1.5;
  max-width: 760px;
}
.agtab-subtitle-count {
  color: rgb(var(--emerald-11));
  font-weight: 600;
}

.agtab-loading, .agtab-empty, .agtab-error {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 80px 24px;
  text-align: center;
  color: rgb(var(--slate-9));
  font-size: 14px;
  gap: 12px;
}
.agtab-loading { flex-direction: row; }
.agtab-empty, .agtab-error {
  flex-direction: column;
  i { width: 32px; height: 32px; color: rgb(var(--slate-7)); }
  h3 { margin: 0; font-size: 16px; color: rgb(var(--slate-11)); }
  p { margin: 4px 0 0; max-width: 480px; font-size: 13px; }
}
.agtab-error { color: rgb(var(--ruby-10)); }

.agtab-spinner {
  width: 18px;
  height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.agtab-content {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.agtab-table-wrap {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-1));
  overflow-x: auto;
}

.agtab-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  min-width: 1000px;

  thead {
    background: rgb(var(--slate-2));
    th {
      padding: 10px 12px;
      text-align: left;
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: rgb(var(--slate-10));
      border-bottom: 1px solid rgb(var(--slate-4));
      white-space: nowrap;
    }
  }

  tbody {
    tr {
      border-bottom: 1px solid rgb(var(--slate-3));
      transition: background-color .12s ease;
      &:last-child { border-bottom: 0; }
      &:hover { background: rgba(255, 255, 255, 0.02); }

      &.agtab-row--unconfigured {
        background: rgba(245, 158, 11, 0.04);
        &:hover { background: rgba(245, 158, 11, 0.08); }
      }
    }

    td {
      padding: 10px 12px;
      vertical-align: middle;
    }
  }
}

/* Larguras */
.agtab-th-name, .agtab-td-name { min-width: 220px; }
.agtab-th-category, .agtab-td-category { min-width: 130px; }
.agtab-th-bond, .agtab-td-bond { width: 90px; }
.agtab-th-prod, .agtab-td-prod {
  width: 140px;
  text-align: right;
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.agtab-th-orc, .agtab-td-orc,
.agtab-th-pac, .agtab-td-pac {
  width: 100px;
  text-align: right;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-11));
}
.agtab-th-comm, .agtab-td-comm { width: 120px; }
.agtab-th-status, .agtab-td-status { width: 110px; white-space: nowrap; }
.agtab-th-actions, .agtab-td-actions { width: 1%; white-space: nowrap; text-align: right; }

.agtab-td-name {
  display: flex;
  align-items: center;
  gap: 10px;
}

.agtab-name-text {
  font-weight: 500;
  color: rgb(var(--slate-12));
}

.agtab-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;

  &--real {
    background: rgba(16, 185, 129, 0.15);
    color: rgb(var(--emerald-11));
  }
}

.agtab-bond-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.05em;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));

  &.bond--pj    { background: rgba(59, 130, 246, 0.15);  color: rgb(var(--blue-11)); }
  &.bond--pf    { background: rgba(245, 158, 11, 0.15);  color: rgb(var(--amber-11)); }
  &.bond--clt   { background: rgba(139, 92, 246, 0.15);  color: rgb(var(--violet-11)); }
  &.bond--socio { background: rgba(16, 185, 129, 0.15);  color: rgb(var(--emerald-11)); }
}

.agtab-missing {
  color: rgb(var(--amber-10));
  font-size: 11px;
  font-style: italic;
}

.agtab-comm-yes {
  color: rgb(var(--emerald-11));
  font-weight: 600;
  font-size: 12px;
}
.agtab-comm-no {
  color: rgb(var(--slate-9));
  font-size: 12px;
}

/* Status pill — preservado apenas para o estado "Pendente" (profile null).
   Ativos/inativos passaram a usar Toggle inline (paridade visual com
   SettingsBankAccountsTab e SettingsPaymentMethodsTab). */
.agtab-status {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.05em;

  &--warn {
    background: rgba(245, 158, 11, 0.15);
    color: rgb(var(--amber-11));
  }
}

/* Ações em ícones — mesma régua de .bank-tab__icon-btn em Bank Accounts.
   Hoje só "Editar". Inativar virou o Toggle inline ao lado. */
.agtab-actions-group {
  display: inline-flex;
  gap: 4px;
  align-items: center;
  justify-content: flex-end;
}
.agtab-icon-btn {
  width: 28px; height: 28px;
  padding: 0;
  margin: 0;
  display: inline-flex; align-items: center; justify-content: center;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;
  i { width: 14px; height: 14px; }

  &:hover {
    background: rgb(var(--slate-3));
    color: rgb(var(--blue-11));
    border-color: rgb(var(--slate-4));
  }
}
</style>
