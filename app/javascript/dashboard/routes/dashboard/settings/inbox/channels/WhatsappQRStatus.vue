<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import axios from 'axios';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
  accountId: {
    type: [String, Number],
    required: true,
  },
});

const bridgeStatus = ref('loading'); // loading | connected | awaiting_qr | disconnected | error
const isAlive = ref(false); // resultado do liveness probe — fonte da verdade
const ownNumber = ref(null);
const qrCode = ref(null);
const showQR = ref(false);
const showResetModal = ref(false);
const isResetting = ref(false);
let pollInterval = null;

// O channel_id (ID do Channel::Whatsapp) é o identificador da sessão no bridge
// Exposto pelo jbuilder como `channel_id` no payload do inbox
const channelId = computed(() => props.inbox.channel_id || props.inbox.id);

// "Conectado" só pinta verde se o liveness probe do bridge confirmar.
// Caso contrário, mostramos "Reconectando..." mesmo que o estado interno
// do Baileys ainda diga 'connected' — o socket pode estar zumbi.
const isConnected = computed(
  () => bridgeStatus.value === 'connected' && isAlive.value
);
const isStale = computed(
  () => bridgeStatus.value === 'connected' && !isAlive.value
);
const isAwaitingQR = computed(() => bridgeStatus.value === 'awaiting_qr');

const statusLabel = computed(() => {
  if (isStale.value) return 'Reconectando...';
  switch (bridgeStatus.value) {
    case 'connected':
      return 'Conectado';
    case 'awaiting_qr':
      return 'Aguardando Escaneamento';
    case 'disconnected':
      return 'Desconectado';
    case 'loading':
      return 'Verificando...';
    case 'error':
      return 'Erro de Conexão';
    default:
      return bridgeStatus.value;
  }
});

const fetchStatus = async () => {
  try {
    const res = await axios.get(
      `/api/v1/accounts/${props.accountId}/whatsapp/bridge/${channelId.value}/status`
    );
    bridgeStatus.value = res.data.status || 'disconnected';
    isAlive.value = !!res.data.alive;
    ownNumber.value = res.data.own_number || null;
  } catch (e) {
    if (e.response && e.response.status === 401) return;
    bridgeStatus.value = 'error';
  }
};

const fetchQR = async () => {
  try {
    const res = await axios.get(
      `/api/v1/accounts/${props.accountId}/whatsapp/bridge/${channelId.value}/qr`
    );
    qrCode.value = res.data.qr;
    bridgeStatus.value = res.data.status || 'disconnected';
  } catch (e) {
    if (e.response && e.response.status === 401) return;
    console.warn('[WhatsappQRStatus] Erro ao buscar QR:', e.message);
  }
};

const handleShowQR = async () => {
  showQR.value = true;
  await fetchQR();
};

const handleResetConfirm = async () => {
  showResetModal.value = false;
  isResetting.value = true;

  try {
    await axios.post(
      `/api/v1/accounts/${props.accountId}/whatsapp/bridge/${channelId.value}/disconnect`
    );

    bridgeStatus.value = 'disconnected';
    qrCode.value = null;
    showQR.value = true;
    ownNumber.value = null;

    useAlert('Sessão limpa! Aguardando novo QR Code...');

    // Aguarda o bridge reiniciar e busca novo QR
    setTimeout(async () => {
      isResetting.value = false;
      await fetchQR();
    }, 4000);
  } catch (e) {
    isResetting.value = false;
    useAlert('Erro ao resetar. Verifique se o motor WhatsApp está rodando.');
  }
};

const formatPhone = phone => {
  if (!phone) return '';
  // Formata: 5511999999999 → +55 11 99999-9999
  const clean = phone.replace(/\D/g, '');
  if (clean.length === 13) {
    return `+${clean.slice(0, 2)} ${clean.slice(2, 4)} ${clean.slice(4, 9)}-${clean.slice(9)}`;
  }
  return `+${clean}`;
};

onMounted(() => {
  fetchStatus();
  // Polling a cada 8s (mais espaçado que no wizard, pois já está conectado em geral)
  pollInterval = setInterval(fetchStatus, 8000);
});

onUnmounted(() => {
  clearInterval(pollInterval);
});
</script>

<template>
  <div class="flex flex-col gap-6 py-4">
    <!-- Card de Status Principal -->
    <div
      class="rounded-2xl border border-n-weak bg-n-alpha-1 p-6 flex flex-col gap-6"
    >
      <div class="flex items-start justify-between">
        <div class="space-y-1">
          <h3 class="text-xl font-bold text-n-slate-12 flex items-center gap-2">
            <span class="i-woot-whatsapp text-green-500 size-6" />
            Status da Conexão
          </h3>
          <p class="text-sm text-n-slate-10">
            Motor WhatsApp QR Code — Sessão isolada
          </p>
        </div>

        <!-- Badge de status -->
        <div
          class="flex items-center gap-2 px-3 py-1.5 rounded-full border text-[10px] font-black uppercase tracking-widest transition-all duration-300"
          :class="{
            'bg-green-500/10 border-green-500/20 text-green-700': isConnected,
            'bg-orange-500/10 border-orange-500/20 text-orange-700': isStale,
            'bg-yellow-500/10 border-yellow-500/20 text-yellow-700': isAwaitingQR,
            'bg-n-alpha-2 border-n-weak text-n-slate-10':
              bridgeStatus === 'disconnected' || bridgeStatus === 'loading',
            'bg-red-500/10 border-red-500/20 text-red-700': bridgeStatus === 'error',
          }"
        >
          <span
            class="w-2 h-2 rounded-full"
            :class="{
              'bg-green-500 shadow-[0_0_6px_rgba(34,197,94,0.7)]': isConnected,
              'bg-orange-500 animate-pulse': isStale,
              'bg-yellow-500 animate-pulse': isAwaitingQR,
              'bg-n-slate-6':
                bridgeStatus === 'disconnected' || bridgeStatus === 'loading',
              'bg-red-500': bridgeStatus === 'error',
            }"
          />
          {{ statusLabel }}
        </div>
      </div>

      <!-- Info do número conectado -->
      <div
        v-if="isConnected && ownNumber"
        class="flex items-center gap-4 p-4 bg-n-alpha-2 rounded-xl border border-n-weak shadow-sm"
      >
        <div
          class="w-12 h-12 bg-green-500 rounded-full flex items-center justify-center flex-shrink-0 shadow-lg shadow-green-500/20"
        >
          <span class="i-ri-phone-fill text-white size-6" />
        </div>
        <div>
          <p class="text-xs font-bold text-n-slate-10 uppercase tracking-wide">Número Conectado</p>
          <p class="text-lg font-black text-n-slate-12">
            {{ formatPhone(ownNumber) }}
          </p>
        </div>
      </div>

      <!-- Estado: Resetting -->
      <div
        v-if="isResetting"
        class="flex items-center gap-4 p-4 bg-n-alpha-2 rounded-xl border border-n-weak"
      >
        <div class="relative w-6 h-6 flex-shrink-0">
          <div class="absolute inset-0 border-2 border-n-brand/20 rounded-full"></div>
          <div class="absolute inset-0 border-2 border-n-brand border-t-transparent rounded-full animate-spin"></div>
        </div>
        <p class="text-sm font-medium text-n-slate-11">
          Limpando sessão e gerando novo QR Code...
        </p>
      </div>

      <!-- Botões de ação -->
      <div class="flex gap-3 flex-wrap">
        <button
          v-if="!showQR && !isResetting"
          class="px-5 py-2.5 rounded-xl bg-n-alpha-2 border border-n-weak text-sm font-bold text-n-slate-11 hover:bg-n-alpha-3 hover:text-n-slate-12 transition-all flex items-center gap-2 shadow-sm"
          @click="handleShowQR"
        >
          <span class="i-ri-qr-code-line" />
          {{ isConnected ? 'Ver QR Code atual' : 'Gerar novo QR Code' }}
        </button>

        <button
          v-if="showQR && !isResetting"
          class="px-5 py-2.5 rounded-xl bg-n-alpha-2 border border-n-weak text-sm font-bold text-n-slate-11 hover:bg-n-alpha-3 transition-all flex items-center gap-2"
          @click="showQR = false"
        >
          <span class="i-ri-eye-off-line" />
          Ocultar QR
        </button>

        <button
          v-if="!isResetting"
          class="px-5 py-2.5 rounded-xl border border-red-500/20 text-sm font-bold text-red-600 hover:bg-red-500/10 transition-all flex items-center gap-2"
          @click="showResetModal = true"
        >
          <span class="i-ri-refresh-line" />
          Forçar Reset Completo
        </button>
      </div>

      <!-- QR Code exibido -->
      <div
        v-if="showQR && !isResetting"
        class="flex flex-col items-center gap-4 mt-2 animate-in slide-in-from-top-2"
      >
        <div
          v-if="isConnected && !qrCode"
          class="text-center p-8 bg-n-alpha-2 rounded-2xl border border-n-weak w-full flex flex-col items-center"
        >
          <div class="w-14 h-14 bg-green-500/10 rounded-full flex items-center justify-center mb-4">
             <span class="i-ri-check-double-line size-8 text-green-500" />
          </div>
          <p class="text-sm font-bold text-n-slate-12">
            WhatsApp já está conectado
          </p>
          <p class="text-xs text-n-slate-10 mt-1">
            Use "Forçar Reset" para gerar um novo QR Code.
          </p>
        </div>
        <div v-else-if="qrCode" class="flex flex-col items-center gap-4">
          <div class="p-4 bg-white rounded-2xl border border-n-weak shadow-inner">
            <img
              :src="qrCode"
              alt="WhatsApp QR Code"
              class="w-52 h-52 rounded-lg"
            />
          </div>
          <div class="flex items-center gap-2 text-xs text-n-slate-10 font-medium bg-n-alpha-2 px-4 py-2 rounded-full">
            <span class="i-ri-information-fill" />
            Abra o WhatsApp > Dispositivos Conectados > Conectar
          </div>
        </div>
        <div v-else class="flex items-center gap-4 p-6">
          <div class="w-6 h-6 border-2 border-n-brand/30 border-t-n-brand rounded-full animate-spin" />
          <p class="text-sm font-medium text-n-slate-10 italic">Gerando QR Code...</p>
        </div>
      </div>
    </div>

    <!-- Card informativo -->
    <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-5 flex gap-4 transition-all hover:border-n-brand/30">
      <div class="w-10 h-10 bg-n-alpha-2 rounded-lg flex items-center justify-center flex-shrink-0">
        <span class="i-ri-shield-check-line text-n-brand size-6" />
      </div>
      <div class="text-sm text-n-slate-10 space-y-1.5">
        <p>
          <strong class="text-n-slate-12">Sessão isolada:</strong> Esta caixa de
          entrada possui um ambiente exclusivo para maior estabilidade.
        </p>
        <p>
          <strong class="text-n-slate-12">Segurança:</strong> As credenciais são criptografadas e o reset limpa todos os dados temporários.
        </p>
      </div>
    </div>

    <!-- Modal de Confirmação de Reset -->
    <div
      v-if="showResetModal"
      class="fixed inset-0 z-[9999] flex items-center justify-center bg-n-slate-12/60 backdrop-blur-md animate-in fade-in"
      @click.self="showResetModal = false"
    >
      <div
        class="bg-n-slate-1 rounded-2xl shadow-2xl p-8 max-w-sm w-full mx-4 border border-n-weak"
      >
        <div class="flex flex-col items-center text-center gap-6">
          <div
            class="w-16 h-16 bg-red-500/10 rounded-full flex items-center justify-center border border-red-500/20"
          >
            <span class="i-ri-error-warning-fill size-10 text-red-500" />
          </div>
          <div class="space-y-2">
            <h3 class="text-xl font-black text-n-slate-12">
              Reset da Sessão
            </h3>
            <p class="text-sm text-n-slate-11 leading-relaxed">
              Isso irá limpar as credenciais salvas desta caixa de entrada.
              <strong class="text-n-slate-12 block mt-1">Apenas esta caixa será afetada.</strong>
            </p>
          </div>
          <div class="flex flex-col gap-3 w-full mt-2">
            <button
              class="w-full py-3 px-4 rounded-xl font-bold text-white bg-red-600 hover:bg-red-700 transition-all shadow-lg shadow-red-600/20"
              @click="handleResetConfirm"
            >
              Sim, resetar agora
            </button>
            <button
              class="w-full py-3 px-4 rounded-xl font-bold text-n-slate-11 hover:bg-n-alpha-2 transition-all border border-n-weak"
              @click="showResetModal = false"
            >
              Cancelar
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
