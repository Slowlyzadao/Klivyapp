<script setup>
// Wrapper admin pra entrar na sala LiveKit (Sprint K).
// Reutiliza o componente puro TelemedicineRoom do patient_portal — só muda
// quem entrega o token. Aqui o token chega via sessionStorage (escrita pelo
// composable useTelemedicineJoin antes de abrir a aba) ou via reissue se
// a aba foi aberta direto (raro — fluxo normal vem do botão no popup).
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import TelemedicineRoom from '@plugins/telemed/frontend/shared/components/TelemedicineRoom.vue';
import { useTelemedicineJoin } from '../composables/useTelemedicineJoin';
import { useTelemedicineSession } from '@plugins/telemed/frontend/shared/composables/useTelemedicineSession';
import AgendaTelemedicineAPI from '../api/agendaTelemedicine';

const route = useRoute();
const { consumeToken } = useTelemedicineJoin();

const status = ref('loading');
const errorMessage = ref('');
const session = ref({ url: '', token: '', dev_mode: false, room_code: '' });

onMounted(async () => {
  const eventId = route.params.eventId;
  try {
    // Caminho normal: token foi escrito no sessionStorage pelo composable.
    let payload = consumeToken(eventId);

    // Fallback (refresh manual da aba ou copy/paste do link): pede um
    // token novo direto. O TTL é curto (10min), então custo é baixo.
    if (!payload) {
      const { data } = await AgendaTelemedicineAPI.issueToken(eventId);
      payload = data?.data || data;
    }
    if (!payload?.token || !payload?.url) {
      throw new Error('Token de acesso inválido. Volte e tente novamente.');
    }
    session.value = payload;
    status.value = 'ready';
  } catch (err) {
    status.value = 'error';
    errorMessage.value =
      err?.response?.data?.error ||
      err?.message ||
      'Não foi possível abrir a sala.';
  }
});

// Sprint K — reporta joined/left pra automação de status. Mesma estrutura
// do paciente; só muda o reporter (API admin com axios vs http fetch).
// O composable é o mesmo (em patient_portal/frontend/composables) pra
// não duplicar a lógica de idempotência entre os dois lados.
const { reportJoined, reportLeft } = useTelemedicineSession({
  reporter: async (eventId, kind) => {
    await AgendaTelemedicineAPI.reportEvent(eventId, kind);
  },
  eventId: route.params.eventId,
});

function onSessionEvent({ kind }) {
  if (kind === 'joined') reportJoined();
  else if (kind === 'left') reportLeft();
}

function closeWindow() {
  // Aba aberta por window.open → window.close fecha sem prompt
  // (regra HTML: aba aberta por script pode ser fechada por script).
  // Caso navegou direto pra URL, ainda assim tenta — sem erro se falhar.
  window.close();
}
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<!-- Strings em PT-BR hardcoded propositais (MVP Sprint K, pendente i18n). -->
<template>
  <div v-if="status === 'loading'" class="agenda-telemed-overlay">
    <div class="agenda-telemed-spinner" />
    <p>Preparando a sala…</p>
  </div>

  <div v-else-if="status === 'error'" class="agenda-telemed-overlay">
    <p class="agenda-telemed-error">{{ errorMessage }}</p>
    <button class="agenda-telemed-btn" @click="closeWindow">Fechar</button>
  </div>

  <!-- role=doctor: doutor entra direto, publica mic/cam imediato, vê fila
       de pacientes aguardando e clica "Admitir" pra cada um. -->
  <TelemedicineRoom
    v-else
    :url="session.url"
    :token="session.token"
    :dev-mode="session.dev_mode"
    :room-code="session.room_code"
    role="doctor"
    header-title="Atendimento por vídeo"
    @leave="closeWindow"
    @session-event="onSessionEvent"
  />
</template>

<style scoped>
.agenda-telemed-overlay {
  position: fixed;
  inset: 0;
  background: #0f172a;
  color: #fff;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  z-index: 1000;
}
.agenda-telemed-spinner {
  width: 36px;
  height: 36px;
  border: 3px solid rgba(255, 255, 255, 0.2);
  border-top-color: #fff;
  border-radius: 50%;
  animation: spin 0.9s linear infinite;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
.agenda-telemed-error {
  color: #fca5a5;
  max-width: 80%;
  text-align: center;
}
.agenda-telemed-btn {
  margin-top: 12px;
  padding: 10px 20px;
  background: #fff;
  color: #0f172a;
  border: 0;
  border-radius: 10px;
  font-weight: 600;
  cursor: pointer;
}
</style>
