<script setup>
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import {
  DOC_TYPE_LABELS,
  docStatusConfig,
} from '@plugins/patients/frontend/constants/documents';

defineProps({
  documents: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'generate',
  'preview',
  'download',
  'send-whatsapp',
  'sign',
  'delete',
]);

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const STATUS_LABEL_KEYS = {
  gerado: 'PATIENT_DOCUMENTS.STATUS.GERADO',
  pendente_assinatura: 'PATIENT_DOCUMENTS.STATUS.PENDENTE_ASSINATURA',
  assinado: 'PATIENT_DOCUMENTS.STATUS.ASSINADO',
  enviado: 'PATIENT_DOCUMENTS.STATUS.ENVIADO',
  arquivado: 'PATIENT_DOCUMENTS.STATUS.ARQUIVADO',
};

const statusLabel = status =>
  t(STATUS_LABEL_KEYS[status] || STATUS_LABEL_KEYS.gerado);
</script>

<template>
  <div class="reg-section">
    <div class="reg-section-toggle" style="cursor: default">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-purple">
          <i class="i-lucide-file-text w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_DOCUMENTS.SECTION.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_DOCUMENTS.SECTION.SUBTITLE') }}
          </span>
        </div>
      </div>
      <span class="proc-count-badge">{{ documents?.length || 0 }}</span>
    </div>

    <div v-if="!documents || documents.length === 0" class="proc-empty-state">
      <div class="proc-empty-icon">
        <i class="i-lucide-file-x w-5 h-5" />
      </div>
      <p class="proc-empty-text">
        {{ t('PATIENT_DOCUMENTS.EMPTY.TITLE') }}
      </p>
      <BeclinicButton
        size="sm"
        variant="link"
        color="blue"
        :label="t('PATIENT_DOCUMENTS.EMPTY.FIRST_LINK')"
        @click="emit('generate')"
      />
    </div>

    <div v-else class="proc-table-wrap">
      <table class="proc-table">
        <thead>
          <tr class="proc-table-head">
            <th>{{ t('PATIENT_DOCUMENTS.TABLE.COL_DOCUMENT') }}</th>
            <th>{{ t('PATIENT_DOCUMENTS.TABLE.COL_TYPE') }}</th>
            <th>{{ t('PATIENT_DOCUMENTS.TABLE.COL_DATE') }}</th>
            <th>{{ t('PATIENT_DOCUMENTS.TABLE.COL_PROFESSIONAL') }}</th>
            <th>{{ t('PATIENT_DOCUMENTS.TABLE.COL_STATUS') }}</th>
            <th class="text-right">
              {{ t('PATIENT_DOCUMENTS.TABLE.COL_ACTIONS') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="doc in documents" :key="doc.id" class="proc-table-row">
            <td class="proc-table-cell">
              <div class="flex items-center gap-3">
                <div class="docs-file-icon">
                  <i class="i-lucide-file-text w-4 h-4" />
                </div>
                <div>
                  <p class="proc-cell-primary">
                    {{
                      doc.title || t('PATIENT_DOCUMENTS.TABLE.DEFAULT_TITLE')
                    }}
                  </p>
                  <p v-if="(doc.version || 1) > 1" class="proc-cell-secondary">
                    {{ t('PATIENT_DOCUMENTS.TABLE.VERSION_PREFIX')
                    }}{{ doc.version }}
                  </p>
                </div>
              </div>
            </td>
            <td class="proc-table-cell">
              <span class="proc-cell-secondary">
                {{
                  DOC_TYPE_LABELS[doc.document_type] || doc.document_type || '—'
                }}
              </span>
            </td>
            <td class="proc-table-cell">
              <span class="proc-cell-secondary">
                {{ doc.created_at ? formatDate(doc.created_at) : '—' }}
              </span>
            </td>
            <td class="proc-table-cell">
              <span class="proc-cell-secondary">
                {{
                  doc.generated_by?.name ||
                  t('PATIENT_DOCUMENTS.TABLE.DEFAULT_PROFESSIONAL')
                }}
              </span>
            </td>
            <td class="proc-table-cell">
              <span
                class="docs-status-badge"
                :class="docStatusConfig(doc.status).cls"
              >
                {{ statusLabel(doc.status) }}
              </span>
            </td>
            <td class="proc-table-cell text-right">
              <div class="flex items-center justify-end gap-1">
                <Tooltip :label="t('PATIENT_DOCUMENTS.TABLE.PREVIEW_TITLE')">
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="slate"
                    icon="i-lucide-eye"
                    @click="emit('preview', doc)"
                  />
                </Tooltip>
                <Tooltip :label="t('PATIENT_DOCUMENTS.TABLE.DOWNLOAD_TITLE')">
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="slate"
                    icon="i-lucide-download"
                    @click="emit('download', doc)"
                  />
                </Tooltip>
                <Tooltip :label="t('PATIENT_DOCUMENTS.TABLE.WHATSAPP_TITLE')">
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="teal"
                    icon="i-ri-whatsapp-fill"
                    @click="emit('send-whatsapp', doc.id)"
                  />
                </Tooltip>
                <Tooltip :label="t('PATIENT_DOCUMENTS.TABLE.SIGN_TITLE')">
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="blue"
                    icon="i-lucide-pen-line"
                    @click="emit('sign', doc)"
                  />
                </Tooltip>
                <Tooltip :label="t('PATIENT_DOCUMENTS.TABLE.DELETE_TITLE')">
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-trash-2"
                    @click="emit('delete', doc.id)"
                  />
                </Tooltip>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
