<script setup>
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { consentStatusConfig } from '@plugins/patients/frontend/constants/consents';

defineProps({
  open: { type: Boolean, default: false },
  consent: { type: Object, default: null },
});

const emit = defineEmits(['close', 'sign']);

const { t } = useI18n();

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const STATUS_LABEL_KEYS = {
  pendente: 'PATIENT_CONSENTS.STATUS.PENDING',
  signed: 'PATIENT_CONSENTS.STATUS.SIGNED',
  vencido: 'PATIENT_CONSENTS.STATUS.EXPIRED',
  revogado: 'PATIENT_CONSENTS.STATUS.REVOKED',
};
const statusLabel = status =>
  t(STATUS_LABEL_KEYS[status] || STATUS_LABEL_KEYS.pendente);
</script>

<template>
  <div
    v-if="open && consent"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md"
    @click.self="emit('close')"
  >
    <div class="consent-view-modal">
      <div class="docs-modal-header">
        <div class="flex items-center gap-3">
          <div class="consent-modal-icon consent-modal-icon--purple">
            <i class="i-lucide-file-signature w-4 h-4" />
          </div>
          <div>
            <h4 class="text-base font-semibold text-slate-100">
              {{
                consent.title || t('PATIENT_CONSENTS.VIEW_MODAL.DEFAULT_TITLE')
              }}
            </h4>
            <div class="flex items-center gap-3 mt-0.5">
              <span
                class="docs-status-badge"
                :class="consentStatusConfig(consent.status).cls"
              >
                {{ statusLabel(consent.status) }}
              </span>
              <span class="text-xs text-slate-500">
                {{ formatDate(consent.created_at) }}
              </span>
            </div>
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

      <div class="docs-modal-body">
        <div class="consent-view-body">
          <p class="consent-view-text">
            {{
              consent.body || t('PATIENT_CONSENTS.VIEW_MODAL.EMPTY_BODY')
            }}
          </p>
        </div>

        <div v-if="consent.status === 'signed'" class="consent-audit-block">
          <p class="consent-audit-title">
            {{ t('PATIENT_CONSENTS.VIEW_MODAL.AUDIT_TITLE') }}
          </p>
          <div class="consent-audit-row consent-audit-row--green">
            <i class="i-lucide-check-circle w-3.5 h-3.5" />
            {{
              t('PATIENT_CONSENTS.VIEW_MODAL.SIGNED_AT', {
                date: formatDate(consent.signed_at),
              })
            }}
          </div>
          <div v-if="consent.integrity_hash" class="consent-audit-row">
            <i class="i-lucide-fingerprint w-3.5 h-3.5 flex-shrink-0 mt-0.5" />
            <span class="font-mono break-all">{{ consent.integrity_hash }}</span>
          </div>
          <div
            v-if="consent.signed_ip"
            class="consent-audit-row consent-audit-row--muted"
          >
            <i class="i-lucide-map-pin w-3.5 h-3.5" />
            {{ t('PATIENT_CONSENTS.VIEW_MODAL.IP_LABEL') }}
            {{ consent.signed_ip }}
          </div>

          <div
            v-if="consent.signature_image_url || consent.signature_blob"
            class="consent-sig-preview"
          >
            <p class="consent-sig-label">
              {{ t('PATIENT_CONSENTS.VIEW_MODAL.SIGNATURE_LABEL') }}
            </p>
            <div class="consent-sig-frame">
              <img
                :src="consent.signature_image_url || consent.signature_blob"
                :alt="t('PATIENT_CONSENTS.VIEW_MODAL.SIGNATURE_ALT')"
                class="consent-sig-img"
              />
            </div>
          </div>
        </div>
      </div>

      <div class="docs-modal-footer">
        <BeclinicButton
          v-if="!['signed', 'revogado'].includes(consent.status)"
          variant="solid"
          color="teal"
          icon="i-lucide-pen-tool"
          :label="t('PATIENT_CONSENTS.VIEW_MODAL.SIGN_NOW')"
          @click="emit('sign', consent.id)"
        />
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_CONSENTS.VIEW_MODAL.CLOSE')"
          @click="emit('close')"
        />
      </div>
    </div>
  </div>
</template>
