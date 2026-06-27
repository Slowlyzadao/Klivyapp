<script setup>
/**
 * SignatureViewerModal — exibe a imagem da assinatura do paciente.
 *
 * Substitui em [1.5.4.0] o `window.open(image_url, '_blank')` que abria a
 * imagem crua numa aba nova (UX ruim, perdia contexto). Agora é um modal
 * dentro do app com metadata da sessão + imagem da assinatura.
 *
 * Suporta lazy load: como `patient_signature_image_url` é um signed URL com
 * expiração curta (15min via SecureBlobTokenService), só renderiza o <img>
 * quando o modal abre — evita pré-carregar URLs que podem ter expirado.
 */
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  session: { type: Object, default: null },
});

const emit = defineEmits(['close']);
const { t } = useI18n();

const signedAt = computed(() => {
  if (!props.session?.patient_signed_at) return '';
  const d = new Date(props.session.patient_signed_at);
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'America/Sao_Paulo',
  });
});

const methodLabel = computed(() => {
  switch (props.session?.patient_signature_method) {
    case 'local':
      return t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.METHOD_LOCAL');
    case 'remote':
      return t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.METHOD_REMOTE');
    default:
      return '—';
  }
});
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
    @click.self="emit('close')"
  >
    <div class="evo-signature-viewer-modal">
      <div class="evo-modal-header">
        <h4 class="text-base font-semibold text-slate-100">
          {{ t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.TITLE') }}
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
        <dl class="evo-signature-meta">
          <div>
            <dt>{{ t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.SIGNED_AT') }}</dt>
            <dd>{{ signedAt }}</dd>
          </div>
          <div>
            <dt>{{ t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.METHOD') }}</dt>
            <dd>{{ methodLabel }}</dd>
          </div>
        </dl>

        <div class="evo-signature-image-wrap">
          <img
            v-if="open && session?.patient_signature_image_url"
            :src="session.patient_signature_image_url"
            :alt="t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.TITLE')"
            class="evo-signature-image"
          />
          <div v-else class="evo-signature-empty">
            {{ t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.EMPTY') }}
          </div>
        </div>

        <p class="evo-signature-disclaimer">
          {{ t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.DISCLAIMER') }}
        </p>
      </div>

      <div class="evo-modal-footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EVOLUTION.SIGNATURE_VIEWER.CLOSE')"
          @click="emit('close')"
        />
      </div>
    </div>
  </div>
</template>
