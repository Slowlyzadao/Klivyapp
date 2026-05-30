<script setup>
// Card de status de uma SignatureRequest in-progress. Mostra:
//   - status atual (badge colorido)
//   - timeline (sent → viewed → signed → completed)
//   - signing_url (link pro signer)
//   - ações: Reenviar, Atualizar status, Cancelar (se ainda não terminou)

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { STATUS_LABELS, STATUS_KIND } from '../constants/statuses';

const props = defineProps({
  request: { type: Object, required: true },
});

const emit = defineEmits(['cancel', 'resend', 'refresh']);

const { t } = useI18n();

const statusLabel = computed(() => STATUS_LABELS[props.request.status] || props.request.status);
const statusKind = computed(() => STATUS_KIND[props.request.status] || 'neutral');

const fmtDate = (iso) => {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleString('pt-BR');
  } catch (_e) {
    return iso;
  }
};

const timeline = computed(() => [
  { key: 'sent_at',      label: t('SIGNATURES.TIMELINE.SENT'),      at: props.request.sent_at,      done: !!props.request.sent_at },
  { key: 'viewed_at',    label: t('SIGNATURES.TIMELINE.VIEWED'),    at: props.request.viewed_at,    done: !!props.request.viewed_at },
  { key: 'signed_at',    label: t('SIGNATURES.TIMELINE.SIGNED'),    at: props.request.signed_at,    done: !!props.request.signed_at },
  { key: 'completed_at', label: t('SIGNATURES.TIMELINE.COMPLETED'), at: props.request.completed_at, done: !!props.request.completed_at },
]);
</script>

<template>
  <div class="signature-status-card">
    <header class="signature-status-card__header">
      <span
        class="signature-status-card__badge"
        :class="`signature-status-card__badge--${statusKind}`"
      >
        {{ statusLabel }}
      </span>
      <span class="signature-status-card__provider">
        {{ t('SIGNATURES.STATUS.PROVIDER_LABEL') }}: {{ request.provider }}
      </span>
    </header>

    <dl class="signature-status-card__info">
      <div>
        <dt>{{ t('SIGNATURES.STATUS.SIGNER') }}</dt>
        <dd>{{ request.signer_name }} · {{ request.signer_email }}</dd>
      </div>
      <div v-if="request.external_id">
        <dt>{{ t('SIGNATURES.STATUS.ENVELOPE') }}</dt>
        <dd>{{ request.external_id }}</dd>
      </div>
      <div v-if="request.signing_url">
        <dt>{{ t('SIGNATURES.STATUS.SIGNING_URL') }}</dt>
        <dd>
          <a :href="request.signing_url" target="_blank" rel="noopener">
            {{ request.signing_url }}
          </a>
        </dd>
      </div>
    </dl>

    <ol class="signature-status-card__timeline">
      <li
        v-for="step in timeline"
        :key="step.key"
        :class="{ 'signature-status-card__timeline-item--done': step.done }"
      >
        <span class="signature-status-card__timeline-dot" />
        <div>
          <strong>{{ step.label }}</strong>
          <span class="signature-status-card__timeline-at">{{ fmtDate(step.at) }}</span>
        </div>
      </li>
    </ol>

    <footer v-if="!request.terminal" class="signature-status-card__actions">
      <button type="button" class="signature-status-card__btn" @click="emit('refresh')">
        <span class="i-lucide-refresh-cw" />
        {{ t('SIGNATURES.ACTIONS.REFRESH') }}
      </button>
      <button type="button" class="signature-status-card__btn" @click="emit('resend')">
        <span class="i-lucide-mail" />
        {{ t('SIGNATURES.ACTIONS.RESEND') }}
      </button>
      <button
        type="button"
        class="signature-status-card__btn signature-status-card__btn--danger"
        @click="emit('cancel')"
      >
        <span class="i-lucide-x-circle" />
        {{ t('SIGNATURES.ACTIONS.CANCEL') }}
      </button>
    </footer>
  </div>
</template>

<style lang="scss" scoped>
@use '../styles/status-card';
</style>
