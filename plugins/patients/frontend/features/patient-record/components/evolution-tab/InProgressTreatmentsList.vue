<script setup>
/**
 * InProgressTreatmentsList — sub-aba "Ficha de Tratamentos em Andamento".
 *
 * Lista os itens de planos de tratamento aprovados/em execução com sessões
 * pendentes. Cada item tem botão "Executar" → o pai abre SessionFormModal
 * pré-preenchido com o `treatment_item_id`.
 */
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  pendingItems: { type: Array, required: true },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['execute-item']);

const { t } = useI18n();
</script>

<template>
  <div class="evo-subtab-pane">
    <header class="evo-subtab-header">
      <div>
        <h3 class="evo-subtab-title">
          {{ t('PATIENT_EVOLUTION.IN_PROGRESS.TITLE') }}
        </h3>
        <p class="evo-subtab-subtitle">
          {{ t('PATIENT_EVOLUTION.IN_PROGRESS.SUBTITLE') }}
        </p>
      </div>
    </header>

    <div v-if="isLoading" class="evo-loading">
      <i class="i-lucide-loader-2 w-5 h-5 animate-spin" />
    </div>

    <div
      v-else-if="!pendingItems || pendingItems.length === 0"
      class="evo-empty-state"
    >
      <i class="i-lucide-check-circle-2 w-8 h-8 mb-2 text-slate-500" />
      <h4>{{ t('PATIENT_EVOLUTION.IN_PROGRESS.EMPTY_TITLE') }}</h4>
      <p>{{ t('PATIENT_EVOLUTION.IN_PROGRESS.EMPTY_HINT') }}</p>
    </div>

    <div v-else class="evo-card-grid">
      <article
        v-for="item in pendingItems"
        :key="`${item.plan_id}-${item.item_id}`"
        class="evo-progress-card"
      >
        <div class="evo-progress-card-body">
          <span class="evo-progress-plan-title">{{ item.plan_title }}</span>
          <h4 class="evo-progress-procedure-name">
            {{ item.item_name }}
          </h4>
          <div class="evo-progress-meta">
            <span class="evo-progress-badge">
              <i class="i-lucide-target w-3.5 h-3.5" />
              {{
                t('PATIENT_EVOLUTION.IN_PROGRESS.SESSIONS_PROGRESS', {
                  done: item.sessions_done,
                  planned: item.sessions_planned,
                })
              }}
            </span>
          </div>
        </div>
        <div class="evo-progress-card-actions">
          <BeclinicButton
            variant="solid"
            color="blue"
            size="sm"
            icon="i-lucide-play"
            :label="t('PATIENT_EVOLUTION.IN_PROGRESS.EXECUTE')"
            @click="emit('execute-item', item)"
          />
        </div>
      </article>
    </div>
  </div>
</template>
