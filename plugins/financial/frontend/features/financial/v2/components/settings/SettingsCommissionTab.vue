<script setup>
/**
 * Aba Comissões — listagem + CRUD (canon §4.3).
 *
 * UI suporta os 4 tipos do canon:
 *   • percentual_geral — % sobre toda receita
 *   • percentual_por_procedimento — % específico por procedimento
 *   • percentual_por_especialidade — % por especialidade
 *   • valor_fixo — R$ fixo por atendimento
 *
 * "Apenas ADMIN cria/edita" — backend retorna 403 se não for ADMIN.
 */
import { ref, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import CommissionRuleFormModalV2 from './CommissionRuleFormModalV2.vue';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL } from '../../composables/useMoney';
import '@plugins/financial/frontend/styles/financial.scss';

const rules = ref([]);
const loading = ref(false);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Modal de criar/editar
const showFormModal = ref(false);
const formMode = ref('create');
const formInitial = ref(null);

// Modal de exclusão
const showDeleteModal = ref(false);
const ruleToDelete = ref(null);
const deleting = ref(false);

async function load() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.commissionRules.index();
    rules.value = data?.data || [];
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao carregar comissões');
  } finally {
    loading.value = false;
  }
}

function fmtPercent(bp) {
  if (bp == null) return '—';
  return `${(bp / 100).toFixed(bp % 100 === 0 ? 0 : 2)}%`;
}

function formatDateBR(iso) {
  if (!iso) return null;
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

// Labels alinhados com o KINDS do model Financial::CommissionRule.
const KIND_BADGE = {
  percentual_geral:             { color: 'blue',    label: '% geral' },
  percentual_por_procedimento:  { color: 'violet',  label: '% por procedimento' },
  percentual_por_especialidade: { color: 'cyan',    label: '% por especialidade' },
  valor_fixo:                   { color: 'amber',   label: 'Valor fixo' },
};
function kindBadge(kind) {
  return KIND_BADGE[kind] || { color: 'slate', label: kind || '—' };
}

const BASE_LABELS = {
  bruto:               'Bruto',
  recebido:            'Recebido',
  recebido_menos_mdr:  'Recebido − MDR',
  recebido_menos_lab:  'Recebido − Lab',
};
function baseLabel(b) { return BASE_LABELS[b] || b || '—'; }

function startCreate() {
  formMode.value = 'create';
  formInitial.value = null;
  showFormModal.value = true;
}

function startEdit(rule) {
  formMode.value = 'edit';
  formInitial.value = rule;
  showFormModal.value = true;
}

function onRuleSaved() {
  load();
}

function askDelete(rule) {
  ruleToDelete.value = rule;
  showDeleteModal.value = true;
}

async function confirmDelete() {
  const rule = ruleToDelete.value;
  if (!rule) return;
  deleting.value = true;
  try {
    await FinancialV2.commissionRules.destroy(rule.id);
    notifySuccess('Regra removida.');
    showDeleteModal.value = false;
    ruleToDelete.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao remover regra');
  } finally {
    deleting.value = false;
  }
}

function ruleAmountLabel(r) {
  if (r.kind === 'valor_fixo') return centsToBRL(r.fixed_amount_cents || 0);
  return fmtPercent(r.percent_basis_points);
}

function ruleSpecificity(r) {
  if (r.kind === 'percentual_por_procedimento') return r.procedure_name;
  if (r.kind === 'percentual_por_especialidade') return r.specialty;
  return null;
}

onMounted(load);
</script>

<template>
  <div class="set-comm">
    <header class="set-comm__header">
      <div>
        <h2 class="set-comm__title">Regras de comissão</h2>
        <p class="set-comm__subtitle">
          Por profissional, define como a comissão é calculada (canon §4.3).
          <strong>Canon:</strong> sempre sobre RECEBIDO (não sobre orçado), descontando
          MDR e laboratório quando aplicável. <em>Apenas ADMIN cria/edita.</em>
        </p>
      </div>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Nova regra"
        size="sm"
        @click="startCreate"
      />
    </header>

    <div v-if="loading" class="finv2-state">
      <div class="finv2-spinner" />
      <span>Carregando regras…</span>
    </div>

    <div v-else-if="rules.length" class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Profissional</th>
            <th>Tipo</th>
            <th class="finv2-table__th-num">Valor</th>
            <th>Base</th>
            <th>Vigência</th>
            <th>Status</th>
            <th class="set-comm__th-actions">Ações</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in rules" :key="r.id">
            <td>
              <ProfessionalChip
                :name="r.professional?.name || `Usuário #${r.professional_id}`"
                :avatar-url="r.professional?.avatar_url || ''"
                size="sm"
              />
            </td>
            <td>
              <div class="set-comm__type-cell">
                <Badge
                  :label="kindBadge(r.kind).label"
                  :color="kindBadge(r.kind).color"
                  size="xs"
                />
                <span v-if="ruleSpecificity(r)" class="set-comm__specificity">
                  {{ ruleSpecificity(r) }}
                </span>
              </div>
            </td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">
              {{ ruleAmountLabel(r) }}
            </td>
            <td class="finv2-table__td-muted">
              <div class="set-comm__base-cell">
                <span>{{ baseLabel(r.base) }}</span>
                <span v-if="r.deduct_mdr || r.deduct_lab" class="set-comm__deductions">
                  <span v-if="r.deduct_mdr">− MDR</span>
                  <span v-if="r.deduct_lab">− Lab</span>
                </span>
              </div>
            </td>
            <td class="finv2-table__td-muted">
              {{ formatDateBR(r.valid_from) || '—' }}
              <template v-if="r.valid_until"> → {{ formatDateBR(r.valid_until) }}</template>
              <template v-else> → indeterminada</template>
            </td>
            <td>
              <Badge
                :label="r.active ? 'Ativa' : 'Inativa'"
                :color="r.active ? 'emerald' : 'slate'"
                size="xs"
              />
            </td>
            <td class="set-comm__td-actions">
              <Tooltip label="Editar">
                <BeclinicButton
                  size="xs"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-pencil"
                  @click="startEdit(r)"
                />
              </Tooltip>
              <Tooltip label="Excluir">
                <BeclinicButton
                  size="xs"
                  variant="ghost"
                  color="ruby"
                  icon="i-lucide-trash-2"
                  @click="askDelete(r)"
                />
              </Tooltip>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div v-else class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-percent w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhuma regra cadastrada</p>
      <p class="finv2-state__hint">
        Comece criando uma regra com o botão "Nova regra" no topo. Sem regras,
        a tela <strong>v2 · Comissões</strong> ficará vazia mesmo após receber pagamentos.
      </p>
    </div>

    <!-- Modal criar/editar -->
    <CommissionRuleFormModalV2
      :show="showFormModal"
      :mode="formMode"
      :initial="formInitial"
      @close="showFormModal = false"
      @confirm="onRuleSaved"
    />

    <!-- Confirmação de exclusão -->
    <ConfirmDangerModal
      v-model:show="showDeleteModal"
      title="Excluir regra de comissão?"
      :message="ruleToDelete
        ? `A regra de ${ruleToDelete.professional?.name || 'profissional'} (${kindBadge(ruleToDelete.kind).label}, ${ruleAmountLabel(ruleToDelete)}) será removida. Comissões já calculadas com essa regra continuam preservadas (snapshot mantido).`
        : ''"
      confirm-label="Excluir regra"
      :loading="deleting"
      @confirm="confirmDelete"
    />
  </div>
</template>

<style scoped lang="scss">
.set-comm__header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 18px;
}
.set-comm__title { margin: 0 0 4px; font-size: 17px; font-weight: 600; color: rgb(var(--slate-12)); }
.set-comm__subtitle {
  margin: 0; color: rgb(var(--slate-9)); font-size: 13px; line-height: 1.5;
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
  em { color: rgb(var(--slate-11)); font-style: italic; }
}

.set-comm__type-cell {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.set-comm__specificity {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

.set-comm__base-cell {
  display: flex;
  flex-direction: column;
  gap: 1px;
}
.set-comm__deductions {
  display: inline-flex;
  gap: 6px;
  font-size: 11px;
  color: rgb(var(--amber-11));
}

.set-comm__th-actions { width: 96px; text-align: right; }
.set-comm__td-actions {
  text-align: right;
  white-space: nowrap;
  display: flex;
  justify-content: flex-end;
  gap: 4px;
}
</style>
