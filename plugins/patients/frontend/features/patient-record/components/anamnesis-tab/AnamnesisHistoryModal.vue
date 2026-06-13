<script setup>
/**
 * AnamnesisHistoryModal — lista cronológica de anamneses + preview readonly.
 *
 * Acesso pelo botão "Histórico" no AnamnesisHeader. A lista mostra todas as
 * versões (rascunho + finalizadas) com data, status, especialidade, número
 * da versão. Clicar abre o PDF da versão (signed URL — só finalizadas têm).
 *
 * Por que não inline na tab? Anamnese é editada com pouca frequência;
 * histórico é consulta esporádica → não merece tirar espaço do form ativo.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  anamneses: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'view-pdf']);

const { t } = useI18n();

// Backend já ordena por id desc (mais recente primeiro). Mantém aqui um sort
// defensivo por updated_at desc → caso a API mude, UI continua coerente.
const sortedAnamneses = computed(() =>
  [...props.anamneses].sort((a, b) => {
    const da = new Date(a.updated_at || a.created_at || 0).getTime();
    const db = new Date(b.updated_at || b.created_at || 0).getTime();
    return db - da;
  })
);

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const statusBadge = item => {
  if (item.status === 'finalized') {
    return {
      label: t('PATIENT_ANAMNESIS.HISTORY.STATUS_FINALIZED'),
      intent: 'success',
      icon: 'i-lucide-lock',
    };
  }
  return {
    label: t('PATIENT_ANAMNESIS.HISTORY.STATUS_DRAFT'),
    intent: 'warning',
    icon: 'i-lucide-pencil',
  };
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md p-0 sm:p-4"
  >
    <div
      class="bg-n-background sm:border sm:border-n-strong sm:rounded-xl shadow-2xl w-full h-full sm:max-w-2xl sm:h-auto sm:max-h-[85vh] flex flex-col overflow-hidden"
    >
      <div
        class="flex items-center justify-between px-5 py-4 border-b border-n-strong flex-shrink-0"
      >
        <div class="flex items-center gap-3">
          <i class="i-lucide-history w-5 h-5 text-n-blue-9" />
          <div>
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ t('PATIENT_ANAMNESIS.HISTORY.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-9 mt-0.5">
              {{ t('PATIENT_ANAMNESIS.HISTORY.SUBTITLE') }}
            </p>
          </div>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div class="flex-1 overflow-y-auto px-5 py-4">
        <div
          v-if="sortedAnamneses.length === 0"
          class="text-center py-12 text-n-slate-9"
        >
          <i class="i-lucide-clipboard w-8 h-8 mx-auto mb-3 opacity-60" />
          <p class="text-sm">{{ t('PATIENT_ANAMNESIS.HISTORY.EMPTY') }}</p>
        </div>

        <div v-else class="flex flex-col gap-2">
          <article
            v-for="item in sortedAnamneses"
            :key="item.id"
            class="flex items-center gap-4 px-4 py-3 rounded-lg border border-n-strong bg-n-slate-2"
          >
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="text-xs font-semibold text-n-slate-9 uppercase tracking-wide">
                  v{{ item.version_number || 1 }}
                </span>
                <span class="text-sm font-medium text-n-slate-12 truncate">
                  {{ item.specialty || t('PATIENT_ANAMNESIS.HISTORY.NO_SPECIALTY') }}
                </span>
                <Badge v-bind="statusBadge(item)" size="xs" />
              </div>
              <p class="text-xs text-n-slate-9 mt-1">
                {{
                  t('PATIENT_ANAMNESIS.HISTORY.DATE_LABEL', {
                    date: formatDate(item.updated_at || item.created_at),
                  })
                }}
              </p>
            </div>
            <BeclinicButton
              v-if="item.pdf_url"
              size="sm"
              variant="faded"
              color="slate"
              icon="i-lucide-file-text"
              :label="t('PATIENT_ANAMNESIS.HISTORY.VIEW_PDF')"
              @click="emit('view-pdf', item)"
            />
            <span
              v-else
              class="text-xs text-n-slate-9 italic flex items-center gap-1"
            >
              <i class="i-lucide-info w-3.5 h-3.5" />
              {{ t('PATIENT_ANAMNESIS.HISTORY.NO_PDF') }}
            </span>
          </article>
        </div>
      </div>

      <div
        class="flex items-center justify-end px-5 py-3 border-t border-n-strong flex-shrink-0"
      >
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_ANAMNESIS.HISTORY.CLOSE')"
          @click="emit('close')"
        />
      </div>
    </div>
  </div>
</template>
