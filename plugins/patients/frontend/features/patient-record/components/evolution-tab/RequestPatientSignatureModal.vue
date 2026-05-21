<script setup>
/**
 * RequestPatientSignatureModal — modal "Solicitar Assinatura" do paciente.
 *
 * Em [1.5.4.0] (Fase 6 v1) o fluxo foi simplificado:
 *   - mode='link'   → DEFAULT, gera link público compartilhável (cópia + QR)
 *   - mode='screen' → tablet local, paciente assina ali na hora no canvas
 *
 * Os campos `phone` e `channel` (WhatsApp/SMS) ficam visíveis mas DESABILITADOS
 * com badge "Em breve" — eles só fazem sentido quando integrarmos com canal
 * de envio automático (NotificationDispatcher), o que é Fase 6 v2 do roadmap.
 * Por enquanto, o médico copia o link e envia manualmente pelo canal preferido.
 */
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { blankSignatureRequest } from '@plugins/patients/frontend/constants/evolution';

const props = defineProps({
  open: { type: Boolean, default: false },
  defaultPhone: { type: String, default: '' },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();
const form = ref(blankSignatureRequest());

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      form.value = {
        ...blankSignatureRequest(),
        phone: props.defaultPhone || '',
      };
    }
  },
  { immediate: true }
);

const handleConfirm = () => {
  emit('confirm', { ...form.value });
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
    @click.self="emit('close')"
  >
    <div class="evo-sign-request-modal">
      <div class="evo-modal-header">
        <h4 class="text-base font-semibold text-slate-100">
          {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.TITLE') }}
        </h4>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div class="evo-modal-body">
        <fieldset class="evo-radio-group">
          <legend class="evo-radio-legend">
            {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.MODE_TITLE') }}
          </legend>
          <label class="evo-radio-option">
            <input
              v-model="form.mode"
              type="radio"
              value="link"
            />
            <span>
              <strong>{{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.MODE_LINK_TITLE') }}</strong>
              <small class="evo-radio-help">
                {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.MODE_LINK_HELP') }}
              </small>
            </span>
          </label>
          <label class="evo-radio-option">
            <input
              v-model="form.mode"
              type="radio"
              value="screen"
            />
            <span>
              <strong>{{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.MODE_SCREEN_TITLE') }}</strong>
              <small class="evo-radio-help">
                {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.MODE_SCREEN_HELP') }}
              </small>
            </span>
          </label>
        </fieldset>

        <div class="evo-coming-soon-block">
          <div class="evo-coming-soon-header">
            <span class="evo-coming-soon-badge">
              {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.COMING_SOON_BADGE') }}
            </span>
            <span class="evo-coming-soon-title">
              {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.AUTO_SEND_TITLE') }}
            </span>
          </div>
          <p class="evo-coming-soon-help">
            {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.AUTO_SEND_HELP') }}
          </p>
          <div class="form-group" :class="{ 'is-disabled': true }">
            <label class="form-label">
              {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.PHONE_LABEL') }}
            </label>
            <input
              v-model="form.phone"
              type="tel"
              class="form-input"
              :placeholder="t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.PHONE_PLACEHOLDER')"
              disabled
            />
          </div>
          <fieldset class="evo-radio-group is-disabled">
            <legend class="evo-radio-legend">
              {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.CHANNEL_TITLE') }}
            </legend>
            <label class="evo-radio-option">
              <input
                v-model="form.channel"
                type="radio"
                value="whatsapp"
                disabled
              />
              <span>WhatsApp</span>
            </label>
            <label class="evo-radio-option">
              <input
                v-model="form.channel"
                type="radio"
                value="sms"
                disabled
              />
              <span>SMS</span>
            </label>
          </fieldset>
        </div>

        <p class="evo-mp-notice">
          {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.MP_NOTICE') }}
          <a
            href="https://www.planalto.gov.br/ccivil_03/mpv/antigas_2001/2200-2.htm"
            target="_blank"
            rel="noopener"
            class="evo-mp-link"
          >
            {{ t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.MP_LINK') }}
          </a>
        </p>
      </div>

      <div class="evo-modal-footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          :label="t('PATIENT_EVOLUTION.SIGN_REQUEST_MODAL.SUBMIT')"
          :is-loading="loading"
          :disabled="loading"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
