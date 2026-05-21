<script setup>
/* eslint-disable no-console */
// Wrapper fino: pede token JWT e delega o resto pro componente puro
// TelemedicineRoom.
//
// 2026-05-19 (revisão Google Meet pattern):
//   - O modal "Quase lá!" de confirmação foi MOVIDO pro TelemedicineJoinCard
//     (fica dentro do app do paciente, antes de navegar pra esta rota). Por
//     isso este wrapper só lida com loading/error/ready — não mostra mais
//     `confirm` aqui.
//   - Estados loading/error agora em fundo LIGHT (alinha com o portal).
//
// Disables: no-console — falhas de issueToken precisam de log pra debug.
import { ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { telemedicineApi } from '../api/telemedicine';
import TelemedicineRoom from '@plugins/telemed/frontend/shared/components/TelemedicineRoom.vue';
import { useTelemedicineSession } from '@plugins/telemed/frontend/shared/composables/useTelemedicineSession';

const route = useRoute();
const router = useRouter();

const status = ref('loading'); // loading | error | ready
const errorMessage = ref('');
const session = ref({
  url: '',
  token: '',
  dev_mode: false,
  outside_window: false,
  starts_in_seconds: null,
  room_code: '',
});

onMounted(async () => {
  try {
    session.value = await telemedicineApi.issueToken(route.params.id);
    status.value = 'ready';
  } catch (err) {
    console.error('[telemed-page] issueToken falhou:', err);
    status.value = 'error';
    errorMessage.value =
      err?.response?.data?.error ||
      err?.message ||
      'Não foi possível abrir a sala.';
  }
});

// Sprint K — automação de status. TelemedicineRoom emite session-event
// {kind:'joined'|'left'}; este composable bate no /telemedicine_event do
// backend que dispara SessionEventHandler (arrived / in_progress / etc).
const { reportJoined, reportLeft } = useTelemedicineSession({
  // Sprint L — repassa `opts.consented` (aceite do termo de gravação) ao
  // endpoint. Wrapper do doutor não envia (consent é do paciente).
  reporter: (id, kind, opts) => telemedicineApi.reportEvent(id, kind, opts),
  eventId: route.params.id,
});

function onSessionEvent({ kind, consented }) {
  if (kind === 'joined') reportJoined({ consented });
  else if (kind === 'left') reportLeft();
}

function goBack() {
  // replace (não push) — não queremos a sala no histórico, senão "voltar"
  // do navegador joga o paciente DE VOLTA pra sala que ele acabou de sair,
  // e o Room reconnecta. replace troca a entrada atual pelo detalhe da
  // consulta, comportamento esperado de fim de chamada.
  router.replace({
    name: 'appointment-detail',
    params: { id: route.params.id },
  });
}
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<!-- Strings PT-BR hardcoded propositais (MVP Sprint K, pendente i18n). -->
<template>
  <div v-if="status === 'loading'" class="pp-telemed-page-overlay">
    <div class="pp-telemed-page-spinner" />
    <p class="pp-telemed-page-text">Preparando sua consulta…</p>
  </div>

  <div v-else-if="status === 'error'" class="pp-telemed-page-overlay">
    <p class="pp-telemed-page-error">{{ errorMessage }}</p>
    <button class="pp-telemed-page-btn" @click="goBack">Voltar</button>
  </div>

  <!-- Sala. Paciente entra com requires-admit=true quando o backend marcou
       outside_window — fica na sala de espera local. -->
  <TelemedicineRoom
    v-else
    :url="session.url"
    :token="session.token"
    :dev-mode="session.dev_mode"
    :room-code="session.room_code"
    role="patient"
    :requires-admit="session.outside_window"
    @leave="goBack"
    @session-event="onSessionEvent"
  />
</template>

<style scoped>
/* Light theme — alinha com o resto do portal do paciente. */
.pp-telemed-page-overlay {
  position: fixed;
  inset: 0;
  background: #f8fafc;
  color: #0f172a;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  z-index: 1000;
  padding: 20px;
}
.pp-telemed-page-spinner {
  width: 36px;
  height: 36px;
  border: 3px solid rgba(15, 23, 42, 0.1);
  border-top-color: #2563eb;
  border-radius: 50%;
  animation: spin 0.9s linear infinite;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
.pp-telemed-page-text {
  font-size: 14px;
  color: #475569;
}
.pp-telemed-page-error {
  color: #b91c1c;
  max-width: 80%;
  text-align: center;
  font-size: 14px;
}

.pp-telemed-page-btn {
  margin-top: 12px;
  padding: 10px 20px;
  background: #2563eb;
  color: #fff;
  border: 0;
  border-radius: 10px;
  font-weight: 600;
  cursor: pointer;
  font-size: 14px;
}
.pp-telemed-page-btn:hover {
  background: #1d4ed8;
}
</style>
