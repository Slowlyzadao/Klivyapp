<script setup>
/**
 * RemoteLinkInfoModal — exibe o link de assinatura remota gerado.
 *
 * Em [1.5.4.0] (Fase 6 v1) ganhou:
 *   - QR code (paciente presente lê com câmera)
 *   - Botão "Enviar pelo WhatsApp" usando wa.me (abre WhatsApp Web/app com
 *     mensagem pré-preenchida e telefone do paciente já discado). Funciona
 *     SEM API oficial — é só um deeplink, o médico clica e o WhatsApp dele
 *     abre a conversa pra revisar/enviar manualmente.
 *   - Feedback visual no botão "Copiar link" (vira "Copiado!" por 2s).
 *
 * O link aponta pra `/public/sessao/<token>` (página HTML standalone).
 */
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  url: { type: String, default: '' },
  expiresAt: { type: String, default: '' },
  patientPhone: { type: String, default: '' },
  patientName: { type: String, default: '' },
});

const emit = defineEmits(['close', 'copy']);

const { t } = useI18n();
const qrDataUrl = ref('');
const justCopied = ref(false);
let copyTimer = null;

// Gera o QR code via lib `qrcode` (lazy import — ~30KB, só carrega quando o
// modal abre). Falhar não é crítico — o copy/paste continua.
async function generateQr(url) {
  qrDataUrl.value = '';
  if (!url) return;
  try {
    const QRCode = (await import('qrcode')).default;
    qrDataUrl.value = await QRCode.toDataURL(url, {
      width: 240,
      margin: 1,
      color: { dark: '#1f6cf2', light: '#ffffff' },
    });
  } catch (err) {
    // sem QR → segue só com link
  }
}

watch(
  () => [props.open, props.url],
  ([isOpen, url]) => {
    if (isOpen && url) generateQr(url);
    if (!isOpen) justCopied.value = false;
  },
  { immediate: true }
);

// Tira não-dígitos do telefone do paciente; wa.me exige formato puro com DDI.
// Brasil sempre 55 — se faltar, prepend.
const whatsappHref = computed(() => {
  if (!props.url) return '';
  const digits = String(props.patientPhone || '').replace(/\D/g, '');
  // Se já vier com 55 na frente, usa direto. Senão prefixa.
  const intl = digits.startsWith('55') ? digits : `55${digits}`;
  const greeting = props.patientName ? `Olá ${props.patientName}, ` : '';
  const text = encodeURIComponent(
    `${greeting}segue o link para assinar seu prontuário:\n\n${props.url}\n\nVálido por 48 horas.`
  );
  // Sem telefone válido (8+ dígitos), wa.me cai num seletor de contato — ainda útil.
  return digits.length >= 8 ? `https://wa.me/${intl}?text=${text}` : `https://wa.me/?text=${text}`;
});

const handleCopy = () => {
  emit('copy');
  justCopied.value = true;
  if (copyTimer) clearTimeout(copyTimer);
  copyTimer = setTimeout(() => {
    justCopied.value = false;
  }, 2000);
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
  >
    <div class="evo-remote-link-modal">
      <div class="evo-modal-header">
        <h4 class="text-base font-semibold text-slate-100">
          {{ t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.TITLE') }}
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
        <p>{{ t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.INSTRUCTIONS') }}</p>

        <div v-if="qrDataUrl" class="evo-remote-link-qr-wrap">
          <img :src="qrDataUrl" alt="QR code" class="evo-remote-link-qr" />
          <small class="evo-remote-link-qr-hint">
            {{ t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.QR_HINT') }}
          </small>
        </div>

        <div class="evo-remote-link-row">
          <div class="evo-remote-link-box">{{ url }}</div>
          <Tooltip :label="justCopied ? t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.COPIED') : t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.COPY')">
            <button
              type="button"
              class="evo-remote-link-copy-icon"
              :class="{ 'is-copied': justCopied }"
              @click="handleCopy"
            >
              <i :class="justCopied ? 'i-lucide-check' : 'i-lucide-copy'" />
            </button>
          </Tooltip>
        </div>
        <p class="evo-remote-link-expires">
          {{ t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.EXPIRES_AT') }}:
          {{ expiresAt }}
        </p>
      </div>
      <div class="evo-modal-footer">
        <a
          v-if="whatsappHref"
          :href="whatsappHref"
          target="_blank"
          rel="noopener"
          class="evo-whatsapp-btn"
        >
          <i class="i-lucide-message-circle w-4 h-4" />
          {{ t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.WHATSAPP') }}
        </a>
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.CLOSE')"
          @click="emit('close')"
        />
      </div>
    </div>
  </div>
</template>
