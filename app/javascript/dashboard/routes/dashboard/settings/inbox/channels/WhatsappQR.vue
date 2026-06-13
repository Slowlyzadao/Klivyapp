<script setup>
import { ref, computed, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const store = useStore();
const router = useRouter();
const route = useRoute();

const inboxName = ref('');
const qrCodeBase64 = ref(null);
const connectionStatus = ref('idle'); // idle | awaiting_qr | connected | error
const isConnecting = ref(false);
const isDisconnecting = ref(false);
const showDisconnectModal = ref(false);
const createdSuccessfully = ref(false);
const isCreatingChannel = ref(false);
const bridgeError = ref(null);
let pollInterval = null;
let consecutiveErrors = 0;
const MAX_ERRORS = 3;

// Unique temp ID generated once per component instance
const tempId = `tmp_${Date.now()}`;

const accountId = computed(
  () => route.params.accountId || route.params.account_id
);

const rules = { inboxName: { required } };
const v$ = useVuelidate(rules, { inboxName });
const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

// Computed states
const isIdle = computed(() => connectionStatus.value === 'idle');
const isConnected = computed(() => connectionStatus.value === 'connected');
const hasError = computed(() => connectionStatus.value === 'error');

const stopPolling = () => {
  if (pollInterval) {
    clearInterval(pollInterval);
    pollInterval = null;
  }
};

const qrI18n = key => t(`INBOX_MGMT.ADD.WHATSAPP.QR_CONNECT.${key}`);

const fetchQR = async () => {
  try {
    const response = await window.axios.get(
      `/api/v1/accounts/${accountId.value}/whatsapp/bridge/${tempId}/qr`
    );
    consecutiveErrors = 0;
    bridgeError.value = null;
    qrCodeBase64.value = response.data.qr;
    connectionStatus.value = response.data.status;

    // Stop polling once connected
    if (connectionStatus.value === 'connected') {
      stopPolling();
    }
  } catch (error) {
    if (error.response?.status === 401) return;

    consecutiveErrors += 1;

    if (consecutiveErrors >= MAX_ERRORS) {
      stopPolling();
      isConnecting.value = false;
      connectionStatus.value = 'error';
      bridgeError.value =
        error.response?.status === 503
          ? qrI18n('BRIDGE_NOT_RUNNING')
          : t('INBOX_MGMT.ADD.WHATSAPP.QR_CONNECT.CONNECTION_ERROR', {
              error: error.message,
            });
    }
  }
};

const startConnection = () => {
  if (isConnecting.value || isConnected.value) return;

  isConnecting.value = true;
  connectionStatus.value = 'awaiting_qr';
  bridgeError.value = null;
  consecutiveErrors = 0;
  qrCodeBase64.value = null;

  fetchQR();
  pollInterval = setInterval(fetchQR, 3000);
};

const requestDisconnect = () => {
  showDisconnectModal.value = true;
};

const disconnect = async () => {
  showDisconnectModal.value = false;
  isDisconnecting.value = true;
  stopPolling();

  try {
    qrCodeBase64.value = null;
    connectionStatus.value = 'disconnected';

    await window.axios.post(
      `/api/v1/accounts/${accountId.value}/whatsapp/bridge/${tempId}/disconnect`
    );

    useAlert(`🧹 ${qrI18n('SESSION_CLEANED')}`);

    isDisconnecting.value = false;
    isConnecting.value = false;
    connectionStatus.value = 'idle';
  } catch {
    isDisconnecting.value = false;
    useAlert(qrI18n('DISCONNECT_ERROR'));
  }
};

onUnmounted(async () => {
  stopPolling();

  if (!createdSuccessfully.value) {
    try {
      await window.axios.post(
        `/api/v1/accounts/${accountId.value}/whatsapp/bridge/${tempId}/disconnect`
      );
    } catch {
      // fire-and-forget
    }
  }
});

const createChannel = async () => {
  if (!isConnected.value) {
    useAlert(qrI18n('SCAN_QR_FIRST'));
    return;
  }
  if (isCreatingChannel.value) return;
  isCreatingChannel.value = true;

  try {
    let ownNumber = null;
    try {
      const statusRes = await window.axios.get(
        `/api/v1/accounts/${accountId.value}/whatsapp/bridge/${tempId}/status`
      );
      ownNumber = statusRes.data.own_number?.replace(/\D/g, '') || null;
    } catch {
      // não crítico
    }

    const phoneNumber = ownNumber || `QR_${Date.now()}`;

    const whatsappChannel = await store.dispatch('inboxes/createChannel', {
      name: inboxName.value.trim(),
      channel: {
        type: 'whatsapp',
        phone_number: phoneNumber,
        provider: 'whatsapp_qr',
        provider_config: { qr_code: true },
      },
    });

    const realInboxId = whatsappChannel.id;

    try {
      await window.axios.post(
        `/api/v1/accounts/${accountId.value}/whatsapp/bridge/${realInboxId}/migrate`,
        { migrate_from: tempId, phone_number: phoneNumber }
      );
    } catch {
      // não crítico
    }

    createdSuccessfully.value = true;

    router.replace({
      name: 'settings_inboxes_add_agents',
      params: {
        accountId: accountId.value,
        inbox_id: realInboxId,
      },
    });
  } catch (error) {
    isCreatingChannel.value = false;
    useAlert(error.message || t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <div class="flex-shrink-0 flex-grow-0 mb-4">
      <label :class="{ error: v$.inboxName.$error }">
        {{ t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex flex-col items-center gap-6 py-4">
      <div class="text-center">
        <h3 class="text-lg font-medium text-n-slate-12">
          {{ qrI18n('TITLE') }}
        </h3>
        <p class="text-sm text-n-slate-11">
          {{ qrI18n('SUBTITLE') }}
        </p>
      </div>

      <!-- Main area: QR Code / Connected / Loading / Idle / Error -->
      <div
        class="p-8 bg-n-alpha-1 rounded-3xl border border-n-weak min-h-[320px] w-full max-w-md flex flex-col items-center justify-center gap-6 transition-all duration-300"
      >
        <!-- IDLE: before clicking Connect -->
        <div
          v-if="isIdle"
          class="flex flex-col items-center gap-6 py-4 text-center"
        >
          <div
            class="w-24 h-24 bg-n-alpha-2 rounded-full flex items-center justify-center border border-n-weak shadow-sm"
          >
            <span class="i-woot-whatsapp text-green-500 size-16" />
          </div>
          <div class="space-y-1">
            <p class="text-lg font-bold text-n-slate-12">
              {{ qrI18n('READY_TITLE') }}
            </p>
            <p class="text-sm text-n-slate-11">
              {{ qrI18n('READY_SUBTITLE') }}
            </p>
          </div>
          <button
            class="px-8 py-3 bg-green-600 hover:bg-green-700 text-white font-bold rounded-xl shadow-md transition-all flex items-center gap-2 transform hover:scale-[1.02] active:scale-[0.98]"
            @click="startConnection"
          >
            <span class="i-ri-qr-code-line text-lg" />
            {{ qrI18n('CONNECT_BUTTON') }}
          </button>
        </div>

        <!-- CONNECTED -->
        <div
          v-else-if="isConnected"
          class="flex flex-col items-center gap-6 py-8 animate-in"
        >
          <div
            class="w-24 h-24 bg-green-500/10 rounded-full flex items-center justify-center border border-green-500/20 shadow-lg shadow-green-500/10"
          >
            <span class="i-woot-whatsapp text-green-500 size-16" />
          </div>
          <div class="text-center space-y-1">
            <span class="text-green-600 font-extrabold text-2xl block">{{
              qrI18n('CONNECTED_TITLE')
            }}</span>
            <p class="text-sm text-n-slate-11">
              {{ qrI18n('CONNECTED_SUBTITLE') }}
            </p>
          </div>
        </div>

        <!-- ERROR -->
        <div
          v-else-if="hasError"
          class="flex flex-col items-center gap-6 py-6 text-center"
        >
          <div
            class="w-20 h-20 bg-red-500/10 rounded-full flex items-center justify-center border border-red-500/20"
          >
            <span class="i-ri-error-warning-fill size-16 text-red-500" />
          </div>
          <div class="space-y-2">
            <p class="text-lg font-bold text-red-600">
              {{ qrI18n('ERROR_TITLE') }}
            </p>
            <p class="text-sm text-n-slate-11 max-w-xs leading-relaxed">
              {{ bridgeError }}
            </p>
          </div>
          <button
            class="px-6 py-2.5 bg-n-alpha-2 hover:bg-n-alpha-3 text-n-slate-12 font-bold rounded-xl border border-n-weak transition-all flex items-center gap-2"
            @click="startConnection"
          >
            <span class="i-ri-refresh-line" />
            {{ qrI18n('RETRY_BUTTON') }}
          </button>
        </div>

        <!-- QR CODE AVAILABLE -->
        <div
          v-else-if="qrCodeBase64"
          class="relative group p-4 bg-white rounded-2xl shadow-inner border border-n-weak"
        >
          <img
            :src="qrCodeBase64"
            alt="WhatsApp QR Code"
            class="w-64 h-64 rounded-lg"
          />
        </div>

        <!-- LOADING / DISCONNECTING -->
        <div v-else class="flex flex-col items-center gap-6 py-8">
          <div class="relative w-16 h-16">
            <div
              class="absolute inset-0 border-4 border-n-brand/10 rounded-full"
            />
            <div
              class="absolute inset-0 border-4 border-n-brand border-t-transparent rounded-full animate-spin"
            />
          </div>
          <p
            class="text-sm font-medium text-n-slate-11 animate-pulse tracking-wide"
          >
            {{
              isDisconnecting ? qrI18n('CLEANING_SESSION') : qrI18n('STARTING')
            }}
          </p>
        </div>

        <!-- Disconnect button (only show if not idle/error) -->
        <button
          v-if="
            !isIdle &&
            !hasError &&
            connectionStatus !== 'disconnected' &&
            !isDisconnecting
          "
          class="mt-4 text-xs font-bold text-n-slate-10 hover:text-red-500 flex items-center gap-1.5 transition-colors px-4 py-2 rounded-full hover:bg-red-500/10"
          @click="requestDisconnect"
        >
          <span class="i-ri-restart-line" />
          {{ qrI18n('DISCONNECT_RESET') }}
        </button>
      </div>

      <!-- Status indicator -->
      <div
        class="flex items-center gap-3 px-6 py-2.5 rounded-full border shadow-sm transition-all duration-300"
        :class="
          isConnected
            ? 'bg-green-500/10 border-green-500/20 text-green-700'
            : hasError
              ? 'bg-red-500/10 border-red-500/20 text-red-700'
              : 'bg-n-alpha-1 border-n-weak text-n-slate-11'
        "
      >
        <span
          class="w-3 h-3 rounded-full"
          :class="[
            isConnected
              ? 'bg-green-500 shadow-[0_0_10px_rgba(34,197,94,0.6)]'
              : hasError
                ? 'bg-red-500'
                : isIdle
                  ? 'bg-n-slate-6'
                  : 'bg-n-brand animate-pulse',
          ]"
        />
        <span class="text-xs font-black uppercase tracking-widest">
          {{
            isConnected
              ? qrI18n('STATUS_CONNECTED')
              : hasError
                ? qrI18n('STATUS_ERROR')
                : isDisconnecting
                  ? qrI18n('STATUS_CLEANING')
                  : isIdle
                    ? qrI18n('STATUS_IDLE')
                    : qrI18n('STATUS_SCANNING')
          }}
        </span>
      </div>

      <!-- Footer buttons -->
      <div
        class="w-full pt-8 mt-6 border-t border-n-weak flex justify-end gap-4"
      >
        <NextButton
          :label="qrI18n('FORCE_RESET')"
          ruby
          outline
          class="min-w-[200px] !rounded-xl"
          :disabled="isDisconnecting || isIdle"
          @click="requestDisconnect"
        />
        <NextButton
          :disabled="
            !isConnected ||
            !inboxName ||
            uiFlags.isCreating ||
            isCreatingChannel
          "
          solid
          blue
          :label="qrI18n('FINALIZE')"
          class="min-w-[200px] !rounded-xl"
          @click="createChannel"
        />
      </div>
    </div>
  </div>

  <!-- Disconnect confirmation modal -->
  <div
    v-if="showDisconnectModal"
    class="fixed inset-0 z-[999] flex items-center justify-center bg-n-slate-12/60 backdrop-blur-md animate-in fade-in"
    @click.self="showDisconnectModal = false"
  >
    <div
      class="bg-n-slate-1 rounded-2xl shadow-2xl p-8 max-w-sm w-full mx-4 border border-n-weak"
    >
      <div class="flex flex-col items-center text-center gap-6">
        <div
          class="w-16 h-16 bg-red-500/10 rounded-full flex items-center justify-center border border-red-500/20"
        >
          <span class="i-ri-error-warning-fill size-12 text-red-500" />
        </div>
        <div class="space-y-2">
          <h3 class="text-xl font-black text-n-slate-12">
            {{ qrI18n('RESET_MODAL_TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 leading-relaxed">
            {{ qrI18n('RESET_MODAL_DESC') }}
          </p>
        </div>
        <div class="flex flex-col gap-3 w-full mt-2">
          <button
            class="w-full py-3 px-4 rounded-xl font-bold text-white bg-red-600 hover:bg-red-700 transition-all shadow-lg shadow-red-600/20"
            @click="disconnect"
          >
            {{ qrI18n('CONFIRM_RESET') }}
          </button>
          <button
            class="w-full py-3 px-4 rounded-xl font-bold text-n-slate-11 hover:bg-n-alpha-2 transition-all border border-n-weak"
            @click="showDisconnectModal = false"
          >
            {{ qrI18n('CANCEL') }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.animate-in {
  animation: animate-in 0.5s ease-out;
}

@keyframes animate-in {
  from {
    opacity: 0;
    transform: scale(0.95);
  }
  to {
    opacity: 1;
    transform: scale(1);
  }
}
</style>
