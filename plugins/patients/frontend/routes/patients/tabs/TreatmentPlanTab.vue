<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * TreatmentPlanTab — Aba "Plano de Tratamento" do prontuário do paciente.
 *
 * Planejamento clínico, orçamentos propostos e status de execução.
 * Permite criar planos com diagnóstico/CID, adicionar procedimentos
 * (com lookup de preço em agendaServices), aprovar planos e gerar PDF.
 *
 * Auto-suficiente: lê patientId da rota e faz seu próprio fetch.
 *
 * Recebe `agenda-services` como prop (necessário para o dropdown de
 * procedimentos no modal — cada serviço tem nome + preço).
 *
 * Componente extraído de Record.vue (Fase 5 do refactor).
 */
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import TreatmentPlansAPI from '@plugins/patients/frontend/api/patients/treatmentPlans';

const props = defineProps({
  agendaServices: { type: Array, default: () => [] },
});

const route = useRoute();

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return formatDateBR(dateStr) || '—';
};
const formatCurrency = value => {
  if (!value) return 'R$ 0,00';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value);
};

// ── State ──────────────────────────────────────────────────
const treatmentPlans = ref([]);
const editingPlanId = ref(null);
const showItemModal = ref(false);
const activePlanId = ref(null);
const currentItem = ref({
  id: null,
  procedure_name: '',
  region: '',
  sessions_planned: 1,
});
const isSavingItem = ref(false);

const globalDiagnosisTitle = ref('');
const globalDiagnosisDescription = ref('');

const showConfirmDeletePlan = ref(false);
const planToDelete = ref(null);

const showConfirmDeleteItem = ref(false);
const itemToDelete = ref({ planId: null, itemId: null });

// ── Actions ────────────────────────────────────────────────
const fetchTreatmentPlans = async () => {
  try {
    const { data } = await TreatmentPlansAPI.get(route.params.patientId);
    treatmentPlans.value = data?.data || data || [];
  } catch (error) {
    useAlert('Erro ao carregar planos de tratamento.');
  }
};

const createTreatmentPlan = async () => {
  try {
    const res = await TreatmentPlansAPI.create(route.params.patientId, {
      title: globalDiagnosisTitle.value,
      description: globalDiagnosisDescription.value,
    });
    useAlert('Novo plano criado!');
    await fetchTreatmentPlans();

    const newId = res.data?.payload?.id || res.data?.id;
    if (newId) editingPlanId.value = newId;

    globalDiagnosisTitle.value = '';
    globalDiagnosisDescription.value = '';
  } catch (error) {
    useAlert('Erro ao criar plano.');
  }
};

const savePlan = async plan => {
  try {
    await TreatmentPlansAPI.update(route.params.patientId, plan.id, {
      title: plan.title,
      description: plan.description,
      estimated_duration: plan.estimated_duration,
    });
    editingPlanId.value = null;
    useAlert('Plano atualizado com sucesso!');
    fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao atualizar plano.');
  }
};

const approvePlan = async planId => {
  try {
    await TreatmentPlansAPI.approve(route.params.patientId, planId);
    editingPlanId.value = null;
    useAlert('Plano aprovado e comissionamento disparado!');
    await fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao aprovar plano.');
  }
};

const requestDeletePlan = planId => {
  planToDelete.value = planId;
  showConfirmDeletePlan.value = true;
};

const cancelDeletePlan = () => {
  showConfirmDeletePlan.value = false;
  planToDelete.value = null;
};

const confirmDeletePlan = async () => {
  if (!planToDelete.value) return;
  try {
    await TreatmentPlansAPI.destroy(route.params.patientId, planToDelete.value);
    useAlert('Plano excluído com sucesso!');
    await fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao excluir plano.');
  } finally {
    cancelDeletePlan();
  }
};

const openItemModal = async (plan, item = null) => {
  if (editingPlanId.value === plan.id) {
    try {
      await TreatmentPlansAPI.update(route.params.patientId, plan.id, {
        title: plan.title,
        description: plan.description,
        estimated_duration: plan.estimated_duration,
      });
      editingPlanId.value = null;
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
    }
  }

  activePlanId.value = plan.id;
  if (item) {
    currentItem.value = { ...item };
  } else {
    currentItem.value = {
      id: null,
      procedure_name: '',
      region: '',
      sessions_planned: 1,
      unit_price: 0,
    };
  }
  showItemModal.value = true;
};

const handleProcedureSelect = () => {
  const selectedService = props.agendaServices.find(
    s => s.name === currentItem.value.procedure_name
  );
  if (selectedService) {
    currentItem.value.unit_price = selectedService.price;
  }
};

const saveItem = async () => {
  isSavingItem.value = true;
  try {
    if (currentItem.value.id) {
      await TreatmentPlansAPI.updateItem(
        route.params.patientId,
        activePlanId.value,
        currentItem.value.id,
        currentItem.value
      );
      useAlert('Procedimento atualizado!');
    } else {
      await TreatmentPlansAPI.createItem(
        route.params.patientId,
        activePlanId.value,
        currentItem.value
      );
      useAlert('Procedimento adicionado!');
    }
    showItemModal.value = false;
    fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao salvar procedimento.');
  } finally {
    isSavingItem.value = false;
  }
};

const requestDeleteItem = (planId, itemId) => {
  itemToDelete.value = { planId, itemId };
  showConfirmDeleteItem.value = true;
};

const cancelDeleteItem = () => {
  showConfirmDeleteItem.value = false;
  itemToDelete.value = { planId: null, itemId: null };
};

const confirmDeleteItem = async () => {
  if (!itemToDelete.value.planId || !itemToDelete.value.itemId) return;
  try {
    await TreatmentPlansAPI.deleteItem(
      route.params.patientId,
      itemToDelete.value.planId,
      itemToDelete.value.itemId
    );
    useAlert('Procedimento removido!');
    fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao remover procedimento.');
  } finally {
    cancelDeleteItem();
  }
};

const printPlan = plan => {
  if (plan && plan.pdf_url) {
    window.open(plan.pdf_url, '_blank');
  } else {
    window.print();
  }
};

onMounted(() => {
  fetchTreatmentPlans();
});
</script>

<template>
  <div class="tab-pane fade-in print-section">
    <!-- Cabeçalho -->
    <div class="rp-tab-header hide-on-print">
      <div>
        <h3 class="rp-tab-title">Plano de Tratamento</h3>
        <p class="rp-tab-subtitle">
          Planejamento clínico, orçamentos propostos e status de execução.
        </p>
      </div>
      <button
        v-can="['patients', 'manage_treatment_plans']"
        class="rp-btn-new"
        @click="createTreatmentPlan"
      >
        <i class="i-lucide-plus rp-btn-new-icon" />
        Novo Plano
      </button>
    </div>

    <div class="rp-content-grid">
      <!-- Formulário de novo diagnóstico -->
      <div class="rp-card hide-on-print">
        <div class="rp-card-header">
          <div class="rp-card-icon rp-card-icon--blue">
            <i class="i-lucide-search" />
          </div>
          <div>
            <span class="rp-card-title">Diagnóstico e Hipótese Inicial</span>
            <span class="rp-card-subtitle"
              >Preencha para criar um novo plano de tratamento</span
            >
          </div>
        </div>
        <div class="rp-card-body">
          <div class="rp-field">
            <label class="rp-field-label"
              >Justificativa Clínica / Queixa Principal do Novo Plano</label
            >
            <textarea
              v-model="globalDiagnosisDescription"
              class="rp-field-input"
              rows="2"
              placeholder="Paciente apresenta escurecimento generalizado nos dentes e má oclusão leve..."
            />
          </div>
          <div class="rp-field">
            <label class="rp-field-label"
              >Hipótese Diagnóstica / CID do Novo Plano</label
            >
            <input
              v-model="globalDiagnosisTitle"
              type="text"
              class="rp-field-input"
              placeholder="Ex: Esmalte escurecido (K03.7) + má oclusão leve"
            />
          </div>
        </div>
      </div>

      <!-- Empty State -->
      <div
        v-if="!treatmentPlans || treatmentPlans.length === 0"
        class="rp-empty"
      >
        <div class="rp-empty-icon">
          <i class="i-lucide-clipboard-list" />
        </div>
        <p class="rp-empty-text">Nenhum plano de tratamento criado ainda.</p>
        <p class="rp-empty-hint">
          Preencha os campos acima e clique em "Novo Plano".
        </p>
      </div>

      <!-- Planos dinâmicos -->
      <div
        v-for="plan in treatmentPlans"
        :key="plan.id"
        class="rp-plan page-break-inside-avoid print-card"
      >
        <!-- Cabeçalho do plano -->
        <div class="rp-plan-head">
          <div class="rp-plan-head-left">
            <div class="rp-plan-head-icon">
              <i class="i-lucide-list-checks" />
            </div>
            <div>
              <span class="rp-plan-name">Plano de Tratamento</span>
              <span class="rp-plan-cid">{{
                plan.title || 'Sem hipótese definida'
              }}</span>
            </div>
          </div>
          <div class="rp-plan-actions hide-on-print">
            <span
              v-if="plan.status === 'aprovado' || plan.status === 'approved'"
              class="rp-badge rp-badge--green"
            >
              <i class="i-lucide-check-circle rp-badge-icon" />
              Aprovado
            </span>
            <template v-else-if="plan.status === 'proposto'">
              <button
                class="rp-action-btn"
                @click="
                  editingPlanId === plan.id
                    ? savePlan(plan)
                    : (editingPlanId = plan.id)
                "
              >
                <i
                  :class="
                    editingPlanId === plan.id
                      ? 'i-lucide-save'
                      : 'i-lucide-pencil'
                  "
                  class="rp-action-btn-icon"
                />
                {{
                  editingPlanId === plan.id ? 'Salvar Plano' : 'Editar Plano'
                }}
              </button>
              <button
                v-can="['patients', 'manage_treatment_plans']"
                class="rp-action-btn rp-action-btn--green"
                @click="approvePlan(plan.id)"
              >
                <i class="i-lucide-check-circle rp-action-btn-icon" />
                Aprovar
              </button>
              <button
                v-can="['patients', 'manage_treatment_plans']"
                class="rp-action-btn rp-action-btn--danger"
                @click="requestDeletePlan(plan.id)"
              >
                <i class="i-lucide-trash-2 rp-action-btn-icon" />
              </button>
            </template>
          </div>
        </div>

        <!-- Diagnóstico e Hipótese -->
        <div class="rp-section">
          <div class="rp-section-label">
            <i class="i-lucide-search rp-section-icon rp-section-icon--blue" />
            Diagnóstico e Hipótese
          </div>

          <div v-if="editingPlanId === plan.id" class="rp-section-body">
            <div class="rp-field">
              <label class="rp-field-label"
                >Justificativa Clínica / Queixa Principal</label
              >
              <textarea
                v-model="plan.description"
                class="rp-field-input"
                rows="2"
              />
            </div>
            <div class="rp-field">
              <label class="rp-field-label">Hipótese Diagnóstica / CID</label>
              <input
                v-model="plan.title"
                type="text"
                class="rp-field-input"
              />
            </div>
          </div>

          <div v-else class="rp-section-body rp-diag-grid">
            <div class="rp-diag-item">
              <span class="rp-diag-label"
                >Justificativa / Queixa Principal</span
              >
              <p class="rp-diag-value">
                {{
                  plan.description ||
                  'O paciente não informou a queixa principal.'
                }}
              </p>
            </div>
            <div class="rp-diag-item">
              <span class="rp-diag-label">Hipótese / CID</span>
              <p class="rp-diag-value rp-diag-value--accent">
                {{ plan.title || 'Nenhum CID informado.' }}
              </p>
            </div>
          </div>
        </div>

        <!-- Procedimentos Planejados -->
        <div class="rp-section">
          <div class="rp-section-label">
            <i
              class="i-lucide-clipboard-list rp-section-icon rp-section-icon--amber"
            />
            Procedimentos Planejados
            <button
              v-if="plan.status === 'proposto'"
              class="rp-add-btn hide-on-print"
              @click="openItemModal(plan)"
            >
              <i class="i-lucide-plus rp-add-btn-icon" /> Adicionar
            </button>
          </div>

          <div class="rp-section-body rp-table-wrap">
            <table class="rp-table">
              <thead class="rp-table-head">
                <tr>
                  <th class="rp-th">Procedimento</th>
                  <th class="rp-th">Região/Elemento</th>
                  <th class="rp-th rp-th--center">Sessões</th>
                  <th class="rp-th rp-th--right">Valor Un.</th>
                  <th class="rp-th rp-th--right">Subtotal</th>
                  <th class="rp-th rp-th--center hide-on-print">Status</th>
                  <th
                    v-if="plan.status === 'proposto'"
                    class="rp-th rp-th--right hide-on-print"
                  >
                    Ação
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-if="
                    !plan.treatment_items || plan.treatment_items.length === 0
                  "
                >
                  <td colspan="7" class="rp-td-empty">
                    Nenhum procedimento adicionado a este plano.
                  </td>
                </tr>
                <tr
                  v-for="item in plan.treatment_items"
                  :key="item.id"
                  class="rp-tr"
                >
                  <td class="rp-td rp-td--name">
                    {{ item.procedure_name || item.procedure_code }}
                  </td>
                  <td class="rp-td rp-td--muted">
                    {{ item.region || item.tooth_number || '-' }}
                  </td>
                  <td class="rp-td rp-td--muted rp-td--center">
                    {{ item.sessions_planned }}
                  </td>
                  <td class="rp-td rp-td--muted rp-td--right">
                    {{ formatCurrency(item.unit_price) }}
                  </td>
                  <td class="rp-td rp-td--strong rp-td--right">
                    {{
                      formatCurrency(
                        (item.unit_price || 0) * (item.sessions_planned || 1)
                      )
                    }}
                  </td>
                  <td class="rp-td rp-td--center hide-on-print">
                    <span
                      class="rp-status"
                      :class="
                        item.status === 'aprovado' || item.status === 'approved'
                          ? 'rp-status--green'
                          : 'rp-status--blue'
                      "
                    >
                      {{
                        item.status === 'aprovado' || item.status === 'approved'
                          ? 'Aprovado'
                          : 'Proposto'
                      }}
                    </span>
                  </td>
                  <td
                    v-if="plan.status === 'proposto'"
                    class="rp-td rp-td--right hide-on-print"
                  >
                    <div class="rp-row-actions">
                      <button
                        class="rp-icon-btn"
                        title="Editar"
                        @click="openItemModal(plan, item)"
                      >
                        <i class="i-lucide-pencil" />
                      </button>
                      <button
                        class="rp-icon-btn rp-icon-btn--danger"
                        title="Remover"
                        @click="requestDeleteItem(plan.id, item.id)"
                      >
                        <i class="i-lucide-trash" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>

            <!-- Total estimado -->
            <div
              v-if="plan.treatment_items && plan.treatment_items.length > 0"
              class="rp-total"
            >
              <span class="rp-total-label">Total Estimado</span>
              <span class="rp-total-value">{{
                formatCurrency(
                  plan.treatment_items.reduce(
                    (sum, item) =>
                      sum +
                      (item.unit_price || 0) * (item.sessions_planned || 1),
                    0
                  )
                )
              }}</span>
            </div>
          </div>
        </div>

        <!-- Observações e Previsão -->
        <div class="rp-section">
          <div class="rp-section-label">
            <i
              class="i-lucide-calendar-clock rp-section-icon rp-section-icon--purple"
            />
            Observações e Previsão
          </div>
          <div class="rp-section-body rp-diag-grid">
            <div class="rp-diag-item">
              <span class="rp-diag-label">Previsão de Conclusão</span>
              <template v-if="editingPlanId === plan.id">
                <input
                  v-model="plan.estimated_duration"
                  type="text"
                  class="rp-field-input rp-field-input--sm"
                  placeholder="Ex: Aprox. 45 dias"
                />
              </template>
              <p v-else class="rp-diag-value">
                {{ plan.estimated_duration || 'Não informada' }}
              </p>
            </div>
            <div class="rp-diag-item">
              <span class="rp-diag-label">Profissional Responsável</span>
              <p class="rp-diag-value">
                {{ plan.professional_name || 'Profissional da Conta' }}
              </p>
            </div>
          </div>

          <div class="rp-plan-footer">
            <div class="rp-approval-info">
              <i
                class="i-lucide-shield-check rp-approval-icon"
                :class="
                  plan.status === 'aprovado' || plan.status === 'approved'
                    ? 'rp-approval-icon--green'
                    : 'rp-approval-icon--muted'
                "
              />
              <span>{{
                plan.status === 'aprovado' || plan.status === 'approved'
                  ? 'Plano aprovado em ' +
                    formatDate(plan.approved_at || new Date())
                  : 'Plano pendente de aprovação.'
              }}</span>
            </div>
            <div class="hide-on-print">
              <a
                v-if="plan.pdf_url"
                :href="plan.pdf_url"
                target="_blank"
                rel="noopener noreferrer"
                class="rp-action-btn"
              >
                <i class="i-lucide-file-text rp-action-btn-icon" />
                Visualizar PDF
              </a>
              <button v-else class="rp-action-btn" @click="printPlan(plan)">
                <i class="i-lucide-printer rp-action-btn-icon" />
                Imprimir Plano
              </button>
            </div>
          </div>
        </div>
      </div>
      <!-- fim v-for planos -->
    </div>

    <!-- Treatment Item Modal -->
    <div
      v-if="showItemModal"
      class="tp-modal-overlay"
      @click.self="showItemModal = false"
    >
      <div class="tp-modal-card">
        <div class="tp-modal-header">
          <div>
            <h3 class="tp-modal-title">
              {{ currentItem.id ? 'Editar Procedimento' : 'Novo Procedimento' }}
            </h3>
            <p class="tp-modal-subtitle">
              Defina os detalhes da intervenção planejada
            </p>
          </div>
          <button class="tp-modal-close" @click="showItemModal = false">
            <i class="i-lucide-x" />
          </button>
        </div>

        <div class="tp-modal-body">
          <div class="tp-field">
            <label class="tp-label">
              Nome do Procedimento <span class="tp-required">*</span>
            </label>
            <select
              v-model="currentItem.procedure_name"
              class="tp-input tp-select"
              @change="handleProcedureSelect"
            >
              <option disabled value="">Selecione um serviço...</option>
              <option
                v-for="svc in agendaServices"
                :key="svc.id"
                :value="svc.name"
              >
                {{ svc.name }} - {{ formatCurrency(svc.price) }}
              </option>
            </select>
          </div>

          <div class="tp-row-2">
            <div class="tp-field">
              <label class="tp-label">Região/Dente</label>
              <input
                v-model="currentItem.region"
                class="tp-input"
                placeholder="Ex: 11, 21 ou Geral"
              />
            </div>
            <div class="tp-field">
              <label class="tp-label">Qtd. Sessões</label>
              <input
                v-model.number="currentItem.sessions_planned"
                type="number"
                min="1"
                class="tp-input"
              />
            </div>
          </div>
        </div>

        <div class="tp-modal-footer">
          <button class="tp-btn-cancel" @click="showItemModal = false">
            Cancelar
          </button>
          <button
            class="tp-btn-submit"
            :disabled="isSavingItem || !currentItem.procedure_name"
            @click="saveItem"
          >
            <i
              v-if="isSavingItem"
              class="i-lucide-loader-2 tp-spinner-icon animate-spin"
            />
            <span v-else>Confirmar</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Modal Excluir Procedimento -->
    <div
      v-if="showConfirmDeleteItem"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999] bg-black/60"
      @click.self="cancelDeleteItem"
    >
      <div
        class="delete-modal-card rounded-2xl w-full max-w-[420px] overflow-hidden bg-[linear-gradient(145deg,#1e293b,#0f172a)] border border-white/5 shadow-[0_25px_50px_-12px_rgba(0,0,0,0.5)]"
      >
        <div class="p-6">
          <div class="flex items-start gap-4">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
            >
              <i class="i-lucide-alert-triangle size-5 text-rose-500" />
            </div>
            <div class="flex flex-col gap-2 pt-1">
              <h3 class="font-medium text-slate-100 m-0 text-lg leading-tight">
                Excluir Procedimento?
              </h3>
              <p class="text-slate-400 m-0 text-sm leading-relaxed">
                Esta ação não pode ser desfeita. O procedimento será removido
                permanentemente do plano de tratamento selecionado.
              </p>
            </div>
          </div>
        </div>
        <div class="px-6 py-4 flex justify-end gap-3 border-t border-white/5">
          <button
            class="rounded-lg px-4 py-2 text-sm font-medium bg-transparent text-slate-400 hover:text-slate-100 transition-colors border-0 cursor-pointer"
            @click="cancelDeleteItem"
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-rose-500 hover:text-rose-400 hover:bg-rose-500/10 bg-transparent transition-all border-0 cursor-pointer"
            @click="confirmDeleteItem"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>

    <!-- Modal Excluir Plano de Tratamento -->
    <div
      v-if="showConfirmDeletePlan"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999] bg-black/60"
      @click.self="cancelDeletePlan"
    >
      <div
        class="delete-modal-card rounded-2xl w-full max-w-[420px] overflow-hidden bg-[linear-gradient(145deg,#1e293b,#0f172a)] border border-white/5 shadow-[0_25px_50px_-12px_rgba(0,0,0,0.5)]"
      >
        <div class="p-6">
          <div class="flex items-start gap-4">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
            >
              <i class="i-lucide-alert-triangle size-5 text-rose-500" />
            </div>
            <div class="flex flex-col gap-2 pt-1">
              <h3 class="font-medium text-slate-100 m-0 text-lg leading-tight">
                Excluir Plano de Tratamento?
              </h3>
              <p class="text-slate-400 m-0 text-sm leading-relaxed">
                Tem certeza que deseja excluir este plano? Esta ação é
                irreversível e todos os procedimentos serão apagados.
              </p>
            </div>
          </div>
        </div>
        <div class="px-6 py-4 flex justify-end gap-3 border-t border-white/5">
          <button
            class="rounded-lg px-4 py-2 text-sm font-medium bg-transparent text-slate-400 hover:text-slate-100 transition-colors border-0 cursor-pointer"
            @click="cancelDeletePlan"
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-rose-500 hover:text-rose-400 hover:bg-rose-500/10 bg-transparent transition-all border-0 cursor-pointer"
            @click="confirmDeletePlan"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
