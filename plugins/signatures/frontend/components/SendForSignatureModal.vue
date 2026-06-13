<script setup>
// Modal "Enviar pra Assinatura" — coleta dados do signatário (paciente
// geralmente) e dispara `signatureRequestsApi.create`. Quando há request
// in-progress pro mesmo signable, mostra estado atual em vez do form.

import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useSignatureRequests } from '../composables/useSignatureRequests';
import SignatureStatusCard from './SignatureStatusCard.vue';

const props = defineProps({
  signableType: { type: String, required: true }, // 'Document' | 'ConsentRecord'
  signableId:   { type: [Number, String], required: true },
  // Dados pre-fill do signer (geralmente paciente do contexto)
  defaultSigner: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['close', 'sent']);

const { t } = useI18n();

const {
  requests,
  activeRequest,
  fetchAll,
  sendForSignature,
  cancel,
  resend,
  refreshStatus,
} = useSignatureRequests(props.signableType, props.signableId);

const form = ref({
  signer_name:  props.defaultSigner.name  || '',
  signer_email: props.defaultSigner.email || '',
  signer_phone: props.defaultSigner.phone || '',
  signer_cpf:   props.defaultSigner.cpf   || '',
  message:      '',
});

const saving = ref(false);

const canSubmit = computed(
  () => form.value.signer_name.length >= 2 && form.value.signer_email.includes('@')
);

const submit = async () => {
  if (!canSubmit.value) return;
  saving.value = true;
  try {
    const created = await sendForSignature(form.value);
    useAlert(t('SIGNATURES.MESSAGES.SENT'));
    emit('sent', created);
  } catch (e) {
    useAlert(e.response?.data?.error || e.message);
  } finally {
    saving.value = false;
  }
};

const onCancel = async () => {
  const reason = window.prompt(t('SIGNATURES.PROMPT.CANCEL_REASON'));
  if (reason === null) return;
  try {
    await cancel(activeRequest.value.id, reason);
    useAlert(t('SIGNATURES.MESSAGES.CANCELLED'));
  } catch (e) {
    useAlert(e.response?.data?.error || e.message);
  }
};

const onResend = async () => {
  try {
    await resend(activeRequest.value.id);
    useAlert(t('SIGNATURES.MESSAGES.RESENT'));
  } catch (e) {
    useAlert(e.response?.data?.error || e.message);
  }
};

const onRefresh = async () => {
  try {
    await refreshStatus(activeRequest.value.id);
    useAlert(t('SIGNATURES.MESSAGES.REFRESHED'));
  } catch (e) {
    useAlert(e.response?.data?.error || e.message);
  }
};

onMounted(fetchAll);
</script>

<template>
  <Teleport to="body">
    <!-- Sem fechar por click no backdrop (regra Modais V2): só × e Cancelar
         fecham, pra não perder os dados do signatário num form longo. -->
    <div class="signatures-modal__backdrop">
      <div class="signatures-modal__container" role="dialog" aria-modal="true">
        <header class="signatures-modal__header">
          <h2 class="signatures-modal__title">
            <span class="i-lucide-pen-line" />
            {{ t('SIGNATURES.MODAL.TITLE') }}
          </h2>
          <button
            type="button"
            class="signatures-modal__close"
            :aria-label="t('GENERAL.CLOSE') || 'Fechar'"
            @click="emit('close')"
          >
            <span class="i-lucide-x" />
          </button>
        </header>

        <div class="signatures-modal__body">
          <!-- Caminho A: já existe request in-progress → mostra status -->
          <SignatureStatusCard
            v-if="activeRequest"
            :request="activeRequest"
            @cancel="onCancel"
            @resend="onResend"
            @refresh="onRefresh"
          />

          <!-- Caminho B: sem request → form pra criar -->
          <form v-else class="signatures-form" @submit.prevent="submit">
            <p class="signatures-form__intro">
              {{ t('SIGNATURES.MODAL.INTRO') }}
            </p>

            <label class="signatures-form__field">
              <span class="signatures-form__label">
                {{ t('SIGNATURES.FIELDS.SIGNER_NAME') }}
              </span>
              <input
                v-model="form.signer_name"
                type="text"
                required
                autofocus
                class="signatures-form__input"
              />
            </label>

            <label class="signatures-form__field">
              <span class="signatures-form__label">
                {{ t('SIGNATURES.FIELDS.SIGNER_EMAIL') }}
              </span>
              <input
                v-model="form.signer_email"
                type="email"
                required
                class="signatures-form__input"
              />
            </label>

            <label class="signatures-form__field">
              <span class="signatures-form__label">
                {{ t('SIGNATURES.FIELDS.SIGNER_PHONE') }}
                <span class="signatures-form__label-hint">
                  ({{ t('GENERAL.OPTIONAL') || 'opcional' }})
                </span>
              </span>
              <input
                v-model="form.signer_phone"
                type="tel"
                class="signatures-form__input"
              />
            </label>

            <label class="signatures-form__field">
              <span class="signatures-form__label">
                {{ t('SIGNATURES.FIELDS.MESSAGE') }}
                <span class="signatures-form__label-hint">
                  ({{ t('GENERAL.OPTIONAL') || 'opcional' }})
                </span>
              </span>
              <textarea
                v-model="form.message"
                rows="3"
                :placeholder="t('SIGNATURES.FIELDS.MESSAGE_PLACEHOLDER')"
                class="signatures-form__input"
              />
            </label>
          </form>
        </div>

        <footer v-if="!activeRequest" class="signatures-modal__footer">
          <button
            type="button"
            class="signatures-form__btn signatures-form__btn--secondary"
            :disabled="saving"
            @click="emit('close')"
          >
            {{ t('GENERAL.CANCEL') || 'Cancelar' }}
          </button>
          <button
            type="button"
            class="signatures-form__btn signatures-form__btn--primary"
            :disabled="!canSubmit || saving"
            @click="submit"
          >
            <span class="i-lucide-send" />
            {{ saving
              ? t('SIGNATURES.MODAL.SENDING')
              : t('SIGNATURES.MODAL.SEND') }}
          </button>
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style lang="scss" scoped>
@use '../styles/modal';
</style>
