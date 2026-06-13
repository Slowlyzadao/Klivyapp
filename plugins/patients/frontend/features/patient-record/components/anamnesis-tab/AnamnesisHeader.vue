<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

const props = defineProps({
  anamnesis: { type: Object, required: true },
  anamneses: { type: Array, default: () => [] },
  isDirty: { type: Boolean, default: false },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits([
  'view-pdf',
  'start-new',
  'save',
  'finalize',
  'open-history',
  'open-clinic-settings',
]);

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const historyCount = computed(() => props.anamneses?.length || 0);
</script>

<template>
  <div class="reg-header mb-5">
    <div>
      <h3 class="text-xl font-semibold text-slate-100">
        {{ t('PATIENT_ANAMNESIS.HEADER.TITLE') }}
      </h3>
      <p class="text-sm text-slate-400 mt-0.5">
        {{ t('PATIENT_ANAMNESIS.HEADER.SUBTITLE') }}
        <span
          v-if="anamnesis.status === 'finalized'"
          class="ml-2 inline-flex items-center gap-1 text-amber-400 text-xs bg-amber-500/10 px-2 py-0.5 rounded-full border border-amber-500/20"
        >
          <i class="i-lucide-lock w-3 h-3" />
          {{ t('PATIENT_ANAMNESIS.HEADER.READONLY_BADGE') }}
        </span>
      </p>
    </div>
    <div class="flex items-center gap-3">
      <span v-if="anamnesis.updated_at" class="text-xs text-slate-500">
        {{
          t('PATIENT_ANAMNESIS.HEADER.LAST_UPDATED', {
            date: formatDate(anamnesis.updated_at),
          })
        }}
      </span>

      <Tooltip :label="t('PATIENT_ANAMNESIS.HEADER.CLINIC_SETTINGS_TOOLTIP')">
        <BeclinicButton
          variant="ghost"
          color="slate"
          icon="i-lucide-stethoscope"
          @click="emit('open-clinic-settings')"
        />
      </Tooltip>

      <BeclinicButton
        v-if="historyCount > 0"
        variant="faded"
        color="slate"
        icon="i-lucide-history"
        :label="
          t('PATIENT_ANAMNESIS.HEADER.HISTORY', { count: historyCount })
        "
        @click="emit('open-history')"
      />

      <BeclinicButton
        v-if="anamnesis.pdf_url"
        variant="faded"
        color="slate"
        icon="i-lucide-file-text"
        :label="t('PATIENT_ANAMNESIS.HEADER.VIEW_PDF')"
        @click="emit('view-pdf')"
      />

      <BeclinicButton
        v-if="anamnesis.status === 'finalized'"
        variant="faded"
        color="slate"
        icon="i-lucide-plus"
        :label="t('PATIENT_ANAMNESIS.HEADER.NEW')"
        @click="emit('start-new')"
      />

      <BeclinicButton
        v-else
        variant="faded"
        :color="isDirty ? 'amber' : 'slate'"
        icon="i-lucide-save"
        :label="
          isDirty
            ? t('PATIENT_ANAMNESIS.HEADER.SAVE_DRAFT_DIRTY')
            : t('PATIENT_ANAMNESIS.HEADER.SAVE_DRAFT')
        "
        :disabled="isSaving"
        @click="emit('save')"
      />

      <BeclinicButton
        v-if="anamnesis.status !== 'finalized'"
        variant="solid"
        color="blue"
        icon="i-lucide-lock"
        :label="t('PATIENT_ANAMNESIS.HEADER.FINALIZE')"
        :disabled="isSaving"
        :is-loading="isSaving"
        @click="emit('finalize')"
      />
    </div>
  </div>
</template>
