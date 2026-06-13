<script setup>
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import {
  consentStatusConfig,
  consentTypeLabel,
} from '@plugins/patients/frontend/constants/consents';

defineProps({
  consents: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'view',
  'send-remote',
  'sign',
  'send-for-signature',
  'revoke',
]);

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const STATUS_LABEL_KEYS = {
  pendente: 'PATIENT_CONSENTS.STATUS.PENDING',
  signed: 'PATIENT_CONSENTS.STATUS.SIGNED',
  vencido: 'PATIENT_CONSENTS.STATUS.EXPIRED',
  revogado: 'PATIENT_CONSENTS.STATUS.REVOKED',
};

const statusLabel = status => {
  const key = STATUS_LABEL_KEYS[status] || STATUS_LABEL_KEYS.pendente;
  return t(key);
};
</script>

<template>
  <div class="reg-section">
    <div class="reg-section-toggle consent-form-header">
      <div class="reg-section-toggle-left">
        <div class="reg-section-icon reg-icon-purple">
          <i class="i-lucide-file-signature w-4 h-4" />
        </div>
        <div>
          <span class="reg-section-title">
            {{ t('PATIENT_CONSENTS.TABLE.TITLE') }}
          </span>
          <span class="reg-section-subtitle">
            {{ t('PATIENT_CONSENTS.TABLE.SUBTITLE') }}
          </span>
        </div>
      </div>
      <span class="proc-count-badge">{{ consents.length }}</span>
    </div>

    <div class="proc-table-wrap">
      <table class="proc-table">
        <thead>
          <tr class="proc-table-head">
            <th>{{ t('PATIENT_CONSENTS.TABLE.DOCUMENT') }}</th>
            <th>{{ t('PATIENT_CONSENTS.TABLE.CATEGORY') }}</th>
            <th>{{ t('PATIENT_CONSENTS.TABLE.VALIDITY') }}</th>
            <th>{{ t('PATIENT_CONSENTS.TABLE.STATUS') }}</th>
            <th class="text-right">{{ t('PATIENT_CONSENTS.TABLE.ACTIONS') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="consent in consents"
            :key="consent.id"
            class="proc-table-row"
          >
            <td class="proc-table-cell">
              <div class="flex items-center gap-3">
                <div class="consent-doc-icon">
                  <i class="i-lucide-file-signature w-3.5 h-3.5" />
                </div>
                <div>
                  <p class="proc-cell-primary">
                    {{
                      consent.title ||
                      t('PATIENT_CONSENTS.TABLE.DEFAULT_TITLE')
                    }}
                  </p>
                  <p class="proc-cell-secondary">
                    <i class="i-lucide-calendar w-2.5 h-2.5 mr-0.5" />
                    {{
                      consent.created_at ? formatDate(consent.created_at) : '—'
                    }}
                    <span v-if="consent.version" class="ml-2 text-slate-600">
                      {{ t('PATIENT_CONSENTS.TABLE.VERSION_PREFIX')
                      }}{{ consent.version }}
                    </span>
                  </p>
                </div>
              </div>
            </td>

            <td class="proc-table-cell">
              <span class="proc-cell-secondary">
                {{ consentTypeLabel(consent.document_type) }}
              </span>
            </td>

            <td class="proc-table-cell">
              <span
                v-if="consent.expires_at"
                class="proc-cell-secondary flex items-center gap-1"
              >
                <i class="i-lucide-timer w-2.5 h-2.5" />
                {{ formatDate(consent.expires_at) }}
              </span>
              <span v-else class="proc-cell-secondary">—</span>
            </td>

            <td class="proc-table-cell">
              <div class="flex flex-col gap-1 items-start">
                <span
                  class="docs-status-badge"
                  :class="consentStatusConfig(consent.status).cls"
                >
                  <i
                    :class="consentStatusConfig(consent.status).icon"
                    class="w-3 h-3 mr-1"
                  />
                  {{ statusLabel(consent.status).toUpperCase() }}
                </span>
                <span
                  v-if="consent.integrity_hash"
                  class="text-[10px] text-slate-500 flex items-center gap-1"
                >
                  <i class="i-lucide-fingerprint w-2.5 h-2.5" />
                  {{ t('PATIENT_CONSENTS.TABLE.HASH_PREFIX') }}
                  {{ consent.integrity_hash?.slice(0, 8) }}...
                </span>
                <span
                  v-if="consent.signed_at"
                  class="text-[10px] text-slate-500 flex items-center gap-1"
                >
                  <i class="i-lucide-clock w-2.5 h-2.5" />
                  {{ formatDate(consent.signed_at) }}
                </span>
              </div>
            </td>

            <td class="proc-table-cell text-right">
              <div class="consent-actions-group">
                <BeclinicButton
                  size="sm"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-eye"
                  :label="t('PATIENT_CONSENTS.TABLE.VIEW')"
                  :title="t('PATIENT_CONSENTS.TABLE.VIEW_TITLE')"
                  @click="emit('view', consent)"
                />
                <template
                  v-if="!['signed', 'revogado'].includes(consent.status)"
                >
                  <BeclinicButton
                    size="sm"
                    variant="faded"
                    color="teal"
                    icon="i-ri-whatsapp-fill"
                    :label="t('PATIENT_CONSENTS.TABLE.SEND')"
                    :title="t('PATIENT_CONSENTS.TABLE.SEND_TITLE')"
                    @click="emit('send-remote', consent.id)"
                  />
                  <BeclinicButton
                    size="sm"
                    variant="faded"
                    color="teal"
                    icon="i-lucide-pen-tool"
                    :label="t('PATIENT_CONSENTS.TABLE.SIGN')"
                    :title="t('PATIENT_CONSENTS.TABLE.SIGN_TITLE')"
                    @click="emit('sign', consent.id)"
                  />
                  <BeclinicButton
                    size="sm"
                    variant="faded"
                    color="blue"
                    icon="i-lucide-pen-line"
                    :label="t('PATIENT_CONSENTS.TABLE.SIGN_REMOTE')"
                    :title="t('PATIENT_CONSENTS.TABLE.SIGN_REMOTE_TITLE')"
                    @click="emit('send-for-signature', consent)"
                  />
                </template>
                <template v-if="consent.status === 'signed'">
                  <BeclinicButton
                    size="sm"
                    variant="faded"
                    color="blue"
                    icon="i-lucide-shield-check"
                    :label="t('PATIENT_CONSENTS.TABLE.HASH')"
                    :title="t('PATIENT_CONSENTS.TABLE.HASH_TITLE')"
                    @click="emit('view', consent)"
                  />
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-x-circle"
                    :label="t('PATIENT_CONSENTS.TABLE.REVOKE')"
                    :title="t('PATIENT_CONSENTS.TABLE.REVOKE_TITLE')"
                    @click="emit('revoke', consent.id)"
                  />
                </template>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
