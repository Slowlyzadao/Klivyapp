<script setup>
/**
 * PlanDetailsModal — Modal de leitura rápida do Plano de Tratamento.
 *
 * Aberto quando o usuário clica no link "Plano de Tratamento #X" dentro de
 * um card do Financeiro. Resolve a UX de "quem é quem após aprovar" sem
 * tirar o usuário da aba Financeiro — mostra título, status, itens, total.
 *
 * Para ver/editar completo, botão "Abrir no Plano de Tratamento" navega
 * pra aba PT (mesma rota que o link tinha antes).
 *
 * Estados especiais:
 *   - PT existe ativo  → mostra dados normalmente
 *   - PT soft-deleted  → backend retorna 404; modal mostra estado "arquivado"
 *     com explicação (canon Regra 3 cascade: PT excluído mas Budget mantém
 *     histórico financeiro com status=cancelado)
 *
 * Mobile: full-screen takeover (h-screen w-screen). Desktop: dialog comum.
 *
 * Props:
 *   open           — controla visibilidade
 *   planId         — id do TreatmentPlan a buscar
 *   patientId      — id do paciente (escopo da API)
 *
 * Eventos:
 *   close          — fechar modal
 *   open-in-tab    — usuário pediu pra ir pra aba PT (parent navega)
 */
import { ref, watch, computed } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import TreatmentPlansAPI from '@plugins/patients/frontend/api/patients/treatmentPlans';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';

const props = defineProps({
  open: { type: Boolean, default: false },
  planId: { type: [Number, String, null], default: null },
  patientId: { type: [Number, String, null], default: null },
});
const emit = defineEmits(['close', 'open-in-tab']);

const loading = ref(false);
const plan = ref(null);
const errorState = ref(null); // 'archived' | 'generic' | null

watch(
  () => [props.open, props.planId, props.patientId],
  async ([open, planId, patientId]) => {
    if (!open || !planId || !patientId) return;
    loading.value = true;
    errorState.value = null;
    plan.value = null;
    try {
      const { data } = await TreatmentPlansAPI.show(patientId, planId);
      plan.value = data?.payload || data;
    } catch (e) {
      // Canon Regra 3: PT pode ter sido cascade-deleted (soft-delete) mas o
      // Budget permanece como cancelado pra histórico contábil. Backend
      // retorna 404 nesses casos. Diferenciamos da falha real (5xx/network)
      // pra dar feedback útil.
      const status = e?.response?.status;
      errorState.value = status === 404 ? 'archived' : 'generic';
      // eslint-disable-next-line no-console
      console.error('[PlanDetailsModal] fetch error', e);
    } finally {
      loading.value = false;
    }
  },
  { immediate: true }
);

const statusBadge = computed(() => {
  // Badge global aceita apenas: blue | emerald | amber | ruby | slate | cyan | violet.
  // (não tem 'teal' — usar 'emerald' ou 'cyan' como semelhantes).
  const map = {
    rascunho:    { color: 'slate',   label: 'Rascunho',    icon: 'i-lucide-file-edit' },
    aprovado:    { color: 'emerald', label: 'Aprovado',    icon: 'i-lucide-check-circle-2' },
    cancelado:   { color: 'ruby',    label: 'Cancelado',   icon: 'i-lucide-x-circle' },
    em_execucao: { color: 'blue',    label: 'Em execução', icon: 'i-lucide-play' },
    concluido:   { color: 'violet',  label: 'Concluído',   icon: 'i-lucide-trophy' },
  };
  return map[plan.value?.status] || { color: 'slate', label: plan.value?.status || '—', icon: 'i-lucide-circle' };
});

const totalValue = computed(() => plan.value?.summary?.total_value ?? 0);
const totalItems = computed(() => plan.value?.summary?.total_items ?? 0);
const completionPct = computed(() =>
  Math.round(plan.value?.summary?.completion_percentage ?? 0)
);

const itemSubtotal = item => Number(item?.net_subtotal ?? item?.total_price ?? 0);

const itemDiscountLabel = item => {
  if (!item?.discount_value || Number(item.discount_value) === 0) return null;
  if (item.discount_type === 'percentual' || item.discount_type === 'percent') {
    return `${item.discount_value}%`;
  }
  return formatCurrency(item.discount_value);
};

const itemStatusVisual = item => {
  const map = {
    aprovado:    { color: 'emerald', label: 'Aprovado',    icon: 'i-lucide-check' },
    proposto:    { color: 'slate',   label: 'Proposto',    icon: 'i-lucide-circle-dashed' },
    em_execucao: { color: 'blue',    label: 'Em execução', icon: 'i-lucide-play' },
    concluido:   { color: 'violet',  label: 'Concluído',   icon: 'i-lucide-check-check' },
    cancelado:   { color: 'ruby',    label: 'Cancelado',   icon: 'i-lucide-x' },
  };
  return map[item?.status] || { color: 'slate', label: item?.status || '—', icon: 'i-lucide-circle' };
};

const handleOpenInTab = () => {
  emit('open-in-tab', { planId: props.planId });
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-stretch sm:items-center justify-center sm:p-4 bg-black/70 backdrop-blur-sm"
    @click.self="emit('close')"
  >
    <div
      class="bg-slate-900 border-slate-700 shadow-2xl w-full flex flex-col
             sm:max-w-3xl sm:max-h-[calc(100vh-2rem)] sm:rounded-2xl sm:border
             h-full sm:h-auto rounded-none border-0"
      role="dialog"
      aria-modal="true"
    >
      <!-- Header -->
      <div
        class="flex items-start justify-between gap-3 p-4 sm:p-6 border-b border-slate-700/50"
      >
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2 flex-wrap">
            <i class="i-lucide-stethoscope text-emerald-400 w-5 h-5 flex-shrink-0" />
            <h3 class="text-base sm:text-lg font-semibold text-slate-100 truncate">
              <template v-if="plan">{{ plan.title || `Plano de Tratamento #${plan.id}` }}</template>
              <template v-else-if="errorState === 'archived'">
                Plano de Tratamento #{{ planId }}
              </template>
              <template v-else>Plano de Tratamento</template>
            </h3>
            <Badge
              v-if="plan"
              :label="statusBadge.label"
              :color="statusBadge.color"
              :icon="statusBadge.icon"
              size="xs"
            />
            <Badge
              v-else-if="errorState === 'archived'"
              label="Arquivado"
              color="slate"
              icon="i-lucide-archive"
              size="xs"
            />
          </div>
          <p class="text-xs text-slate-400 mt-1">
            <template v-if="errorState === 'archived'">
              Este plano foi excluído. O orçamento financeiro foi mantido como cancelado para histórico.
            </template>
            <template v-else>
              Visão rápida do plano sem sair do Financeiro.
            </template>
          </p>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <!-- Body -->
      <div class="p-4 sm:p-6 space-y-4 overflow-y-auto flex-1">
        <!-- Loading -->
        <div
          v-if="loading"
          class="flex flex-col items-center justify-center py-16 gap-3 text-slate-400"
        >
          <div
            class="w-10 h-10 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
            aria-hidden="true"
          />
          <p class="text-sm">Carregando plano...</p>
        </div>

        <!-- Estado: PT arquivado (cascade-deleted) -->
        <div
          v-else-if="errorState === 'archived'"
          class="flex flex-col items-center justify-center py-12 px-4 gap-3 text-center"
        >
          <div
            class="w-14 h-14 rounded-full bg-slate-800 border border-slate-700 flex items-center justify-center"
          >
            <i class="i-lucide-archive w-7 h-7 text-slate-400" />
          </div>
          <div class="space-y-1.5 max-w-md">
            <h4 class="text-base font-semibold text-slate-100">Plano arquivado</h4>
            <p class="text-sm text-slate-400 leading-relaxed">
              Este plano de tratamento foi excluído. O orçamento financeiro
              vinculado foi <strong class="text-slate-200">cancelado automaticamente</strong>
              e permanece visível aqui para fins de histórico e auditoria.
            </p>
          </div>
          <p class="text-xs text-slate-500 mt-2">
            Canon Regra 3 — exclusão de PT com Budget sem pagamento.
          </p>
        </div>

        <!-- Estado: erro genérico -->
        <div
          v-else-if="errorState === 'generic'"
          class="flex flex-col items-center justify-center py-12 px-4 gap-3 text-center"
        >
          <div
            class="w-14 h-14 rounded-full bg-red-500/10 border border-red-500/30 flex items-center justify-center"
          >
            <i class="i-lucide-alert-triangle w-7 h-7 text-red-400" />
          </div>
          <div class="space-y-1.5 max-w-md">
            <h4 class="text-base font-semibold text-slate-100">
              Erro ao carregar plano
            </h4>
            <p class="text-sm text-slate-400">
              Não foi possível buscar os detalhes deste plano. Tente novamente
              em alguns instantes.
            </p>
          </div>
        </div>

        <!-- Conteúdo normal -->
        <template v-else-if="plan">
          <!-- KPIs -->
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-2.5 sm:gap-3">
            <div
              class="bg-slate-800 border border-slate-700 rounded-xl px-3 py-3 flex flex-col gap-1"
            >
              <span
                class="text-[10px] sm:text-[11px] uppercase tracking-wide text-slate-400 font-medium"
              >Total estimado</span>
              <strong
                class="text-base sm:text-lg text-emerald-300 font-semibold font-mono leading-tight"
              >
                {{ formatCurrency(totalValue) }}
              </strong>
            </div>
            <div
              class="bg-slate-800 border border-slate-700 rounded-xl px-3 py-3 flex flex-col gap-1"
            >
              <span
                class="text-[10px] sm:text-[11px] uppercase tracking-wide text-slate-400 font-medium"
              >Procedimentos</span>
              <strong class="text-base sm:text-lg text-slate-100 font-semibold leading-tight">
                {{ totalItems }}
              </strong>
            </div>
            <div
              class="bg-slate-800 border border-slate-700 rounded-xl px-3 py-3 flex flex-col gap-1 col-span-2 sm:col-span-1"
            >
              <span
                class="text-[10px] sm:text-[11px] uppercase tracking-wide text-slate-400 font-medium"
              >Sessões</span>
              <div class="flex items-baseline gap-2">
                <strong class="text-base sm:text-lg text-slate-100 font-semibold leading-tight">
                  {{ plan.summary?.total_sessions_done || 0 }}/{{ plan.summary?.total_sessions_planned || 0 }}
                </strong>
                <span
                  v-if="completionPct > 0"
                  class="text-xs text-slate-400 font-mono"
                >({{ completionPct }}%)</span>
              </div>
              <!-- Mini barra de progresso -->
              <div
                v-if="(plan.summary?.total_sessions_planned || 0) > 0"
                class="mt-1 h-1 bg-slate-700/60 rounded-full overflow-hidden"
              >
                <div
                  class="h-full bg-emerald-500 transition-all"
                  :style="{ width: completionPct + '%' }"
                />
              </div>
            </div>
          </div>

          <!-- Profissional + datas -->
          <div
            class="bg-slate-800/60 border border-slate-700/60 rounded-xl p-3 sm:p-4 space-y-3"
          >
            <div v-if="plan.professional_name" class="flex items-center gap-3">
              <ProfessionalChip
                :name="plan.professional_name"
                :avatar-url="plan.professional_avatar_url || ''"
                size="md"
              />
            </div>
            <div
              v-if="plan.approved_at"
              class="flex items-start gap-2 text-sm text-slate-300 pt-3 border-t border-slate-700/40"
            >
              <i class="i-lucide-check-circle-2 w-4 h-4 flex-shrink-0 text-emerald-400 mt-0.5" />
              <span class="leading-snug">
                Aprovado em
                <strong class="text-slate-100">{{ formatDateBR(plan.approved_at) }}</strong>
                <template v-if="plan.approved_by_name">
                  <br class="sm:hidden">
                  <span class="text-slate-400"> por {{ plan.approved_by_name }}</span>
                </template>
              </span>
            </div>
            <div
              v-else-if="plan.created_at"
              class="flex items-start gap-2 text-sm text-slate-300 pt-3 border-t border-slate-700/40"
            >
              <i class="i-lucide-calendar w-4 h-4 flex-shrink-0 text-slate-400 mt-0.5" />
              <span>Criado em <strong class="text-slate-100">{{ formatDateBR(plan.created_at) }}</strong></span>
            </div>
          </div>

          <!-- Itens (desktop: tabela; mobile: cards) -->
          <div v-if="plan.treatment_items?.length">
            <h4
              class="text-xs uppercase tracking-wide text-slate-400 font-medium mb-2"
            >
              Procedimentos planejados
            </h4>

            <!-- Mobile: lista de cards -->
            <div class="sm:hidden space-y-2">
              <div
                v-for="item in plan.treatment_items"
                :key="`m-${item.id}`"
                class="bg-slate-800 border border-slate-700 rounded-xl p-3 space-y-2"
              >
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0 flex-1">
                    <p class="text-sm font-semibold text-slate-100 truncate">
                      {{ item.procedure_name || '—' }}
                    </p>
                    <p
                      v-if="item.region || item.tooth_number"
                      class="text-xs text-slate-400 mt-0.5"
                    >
                      {{ item.region || item.tooth_number }}
                    </p>
                  </div>
                  <Badge
                    :label="itemStatusVisual(item).label"
                    :color="itemStatusVisual(item).color"
                    :icon="itemStatusVisual(item).icon"
                    size="xs"
                  />
                </div>
                <div class="grid grid-cols-3 gap-2 text-xs">
                  <div>
                    <p class="text-slate-500">Sessões</p>
                    <p class="text-slate-200 font-medium">
                      {{ item.sessions_done || 0 }}/{{ item.sessions_planned || 1 }}
                    </p>
                  </div>
                  <div>
                    <p class="text-slate-500">Valor un.</p>
                    <p class="text-slate-200 font-mono">{{ formatCurrency(item.unit_price || 0) }}</p>
                  </div>
                  <div class="text-right">
                    <p class="text-slate-500">Subtotal</p>
                    <p class="text-emerald-300 font-mono font-semibold">
                      {{ formatCurrency(itemSubtotal(item)) }}
                    </p>
                  </div>
                </div>
                <div
                  v-if="itemDiscountLabel(item)"
                  class="text-xs text-amber-300 flex items-center gap-1"
                >
                  <i class="i-lucide-tag w-3 h-3" />
                  Desconto: {{ itemDiscountLabel(item) }}
                </div>
              </div>
            </div>

            <!-- Desktop: tabela -->
            <div class="hidden sm:block border border-slate-700 rounded-xl overflow-hidden">
              <table class="w-full text-sm">
                <thead class="bg-slate-800/60">
                  <tr class="text-left text-[11px] uppercase tracking-wide text-slate-400">
                    <th class="px-3 py-2.5 font-medium">Procedimento</th>
                    <th class="px-3 py-2.5 font-medium">Região</th>
                    <th class="px-3 py-2.5 font-medium">Sessões</th>
                    <th class="px-3 py-2.5 font-medium">Valor un.</th>
                    <th class="px-3 py-2.5 font-medium">Desconto</th>
                    <th class="px-3 py-2.5 font-medium text-right">Subtotal</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-800">
                  <tr
                    v-for="item in plan.treatment_items"
                    :key="item.id"
                    class="hover:bg-slate-800/40 text-slate-200 transition-colors"
                  >
                    <td class="px-3 py-3">
                      <div class="flex items-center gap-2">
                        <span class="font-medium">{{ item.procedure_name || '—' }}</span>
                        <Badge
                          :label="itemStatusVisual(item).label"
                          :color="itemStatusVisual(item).color"
                          :icon="itemStatusVisual(item).icon"
                          size="xs"
                        />
                      </div>
                    </td>
                    <td class="px-3 py-3 text-slate-400">
                      {{ item.region || item.tooth_number || '—' }}
                    </td>
                    <td class="px-3 py-3 font-mono">
                      {{ item.sessions_done || 0 }}/{{ item.sessions_planned || 1 }}
                    </td>
                    <td class="px-3 py-3 font-mono">
                      {{ formatCurrency(item.unit_price || 0) }}
                    </td>
                    <td class="px-3 py-3 text-amber-300">
                      {{ itemDiscountLabel(item) || '—' }}
                    </td>
                    <td class="px-3 py-3 text-right font-mono font-semibold text-emerald-300">
                      {{ formatCurrency(itemSubtotal(item)) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <p
            v-else
            class="text-center text-slate-500 text-sm border border-dashed border-slate-700 rounded-lg py-6"
          >
            Este plano ainda não tem procedimentos.
          </p>

          <!-- Descrição -->
          <div v-if="plan.description">
            <h4
              class="text-xs uppercase tracking-wide text-slate-400 font-medium mb-2"
            >
              Observações
            </h4>
            <div
              class="bg-slate-800 border border-slate-700/60 rounded-xl px-3 py-2.5 text-sm text-slate-300 whitespace-pre-wrap leading-relaxed"
            >
              {{ plan.description }}
            </div>
          </div>
        </template>
      </div>

      <!-- Footer -->
      <div
        class="p-4 sm:p-6 border-t border-slate-700/50 flex flex-col-reverse sm:flex-row justify-end gap-2 sm:gap-3"
      >
        <BeclinicButton
          variant="ghost"
          color="slate"
          label="Fechar"
          @click="emit('close')"
        />
        <BeclinicButton
          v-if="plan"
          variant="solid"
          color="blue"
          icon="i-lucide-external-link"
          label="Abrir no Plano de Tratamento"
          @click="handleOpenInTab"
        />
      </div>
    </div>
  </div>
</template>
