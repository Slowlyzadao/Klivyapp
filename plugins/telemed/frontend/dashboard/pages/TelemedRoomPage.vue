<script setup>
// Wrapper admin pra entrar na sala LiveKit (Sprint K).
// Reutiliza o componente puro TelemedicineRoom do patient_portal — só muda
// quem entrega o token. Aqui o token chega via sessionStorage (escrita pelo
// composable useTelemedicineJoin antes de abrir a aba) ou via reissue se
// a aba foi aberta direto (raro — fluxo normal vem do botão no popup).
//
// 2026-05-21 — modal pós-encerramento. Quando o doutor clica "Encerrar",
// abre um modal "Conseguiu atender o paciente?" antes de fechar a aba.
// Sim → confirma `completed` no backend; Não → fecha sem mudar status.
// Mudança correlata: `SessionEventHandler#left!` não auto-marca completed
// mais — só essa confirmação do doutor faz a transição.
import { ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import TelemedicineRoom from '@plugins/telemed/frontend/shared/components/TelemedicineRoom.vue';
import { useTelemedicineJoin } from '../composables/useTelemedicineJoin';
import { useTelemedicineSession } from '@plugins/telemed/frontend/shared/composables/useTelemedicineSession';
import AgendaTelemedicineAPI from '../api/agendaTelemedicine';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const route = useRoute();
const router = useRouter();
const { consumeToken } = useTelemedicineJoin();

const status = ref('loading');
const errorMessage = ref('');
const session = ref({ url: '', token: '', dev_mode: false, room_code: '' });

// Modal pós-encerramento. Aberto QUANDO o TelemedicineRoom emite 'leave'
// (doutor clicou Encerrar). Bloqueia o fechamento da aba até o doutor
// decidir — caso contrário, ele tinha 0s pra refletir sobre o que acabou
// de acontecer e a regra de "atendido" automático voltava por outras vias.
const showEndCallModal = ref(false);
const confirming = ref(false);
const confirmError = ref('');

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

// TelemedicineRoom emite 'leave' quando o doutor clica Encerrar. Antes
// fechávamos a aba direto. Agora abrimos o modal pra confirmar atendimento.
function onLeave() {
  showEndCallModal.value = true;
}

function closeWindow() {
  // Aba aberta por window.open (fluxo normal: botão "Entrar na sala" da agenda)
  // fecha sem prompt. Quando a sala foi aberta navegando DIRETO pela URL,
  // window.close() NÃO fecha (regra HTML) — então caímos num fallback de
  // navegação pra não deixar o doutor preso no modal/sala morta.
  window.close();
  setTimeout(() => {
    if (!window.closed) {
      router.push({
        name: 'teleconsultas_index',
        params: { accountId: route.params.accountId },
      });
    }
  }, 200);
}

async function confirmAttended() {
  if (confirming.value) return;
  confirming.value = true;
  confirmError.value = '';
  try {
    await AgendaTelemedicineAPI.confirmCompleted(route.params.eventId);
    closeWindow();
  } catch (err) {
    confirmError.value =
      err?.response?.data?.error ||
      'Não foi possível confirmar agora. Tente de novo ou feche e marque manualmente no calendário.';
  } finally {
    confirming.value = false;
  }
}

function dismissWithoutConfirming() {
  // Não confirmou atendimento → status fica em in_progress. Doutor pode
  // mudar manualmente no calendário (cancelar, marcar no-show, etc.).
  closeWindow();
}

// 2026-05-21 — Server-side admit. Chamado pelo TelemedicineRoom quando o
// dentista clica "Aceitar". Backend faz LiveKit UpdateParticipant
// (canPublish=true) e persiste em event.custom_attributes['telemed_session'].
// O paciente recebe ParticipantPermissionsChanged → applyAdmit().
//
// Erros propagam: o componente da sala vê o reject e mantém o card "Aceitar"
// visível pra dentista tentar de novo (sem desaparecer silenciosamente).
async function onAdmitPatient(identity) {
  await AgendaTelemedicineAPI.admitPatient(route.params.eventId, identity);
}

// 2026-05-22 — Gravação manual. TelemedicineRoom chama estes callbacks
// quando o doutor clica no botão "Gravar" da toolbar. Backend chama
// RecordingOrchestrator#start!(force: true) / #stop!.
// Erros propagam: o componente mostra o `recordingError` na própria
// toolbar (toast curto) sem fingir que iniciou.
async function onStartRecording() {
  await AgendaTelemedicineAPI.startRecording(route.params.eventId);
}
async function onStopRecording() {
  await AgendaTelemedicineAPI.stopRecording(route.params.eventId);
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
       de pacientes aguardando e clica "Admitir" pra cada um.

       2026-05-21 — admitter chama LiveKit UpdateParticipant server-side;
       initialAdmissions reidrata pacientes já aceitos após F5. -->
  <TelemedicineRoom
    v-else
    :url="session.url"
    :token="session.token"
    :dev-mode="session.dev_mode"
    :room-code="session.room_code"
    role="doctor"
    header-title="Atendimento por vídeo"
    :initial-admissions="session.admissions || {}"
    :admitter="onAdmitPatient"
    :initial-recording="session.recording || {}"
    :record-starter="onStartRecording"
    :record-stopper="onStopRecording"
    @leave="onLeave"
    @session-event="onSessionEvent"
  />

  <!-- Modal pós-encerramento (doutor): "Conseguiu atender o paciente?".
       Z-index alto pra garantir overlay sobre QUALQUER coisa da sala. -->
  <transition name="telemed-end-modal">
    <div
      v-if="showEndCallModal"
      class="agenda-telemed-end-modal"
      role="dialog"
      aria-modal="true"
    >
      <div class="agenda-telemed-end-modal__box">
        <h2 class="agenda-telemed-end-modal__title">Como foi a consulta?</h2>
        <p class="agenda-telemed-end-modal__text">
          Conseguiu atender o paciente? Se a chamada não rolou bem (internet do
          paciente ruim, ele saiu antes etc.), responda "Não consegui" e o
          status fica como está — você ajusta depois no calendário.
        </p>

        <p v-if="confirmError" class="agenda-telemed-end-modal__error">
          {{ confirmError }}
        </p>

        <div class="agenda-telemed-end-modal__actions">
          <BeclinicButton
            variant="outline"
            color="slate"
            label="Não consegui"
            class="flex-1"
            :disabled="confirming"
            @click="dismissWithoutConfirming"
          />
          <BeclinicButton
            variant="solid"
            color="blue"
            :label="confirming ? 'Confirmando…' : 'Sim, atendi'"
            :is-loading="confirming"
            class="flex-1"
            :disabled="confirming"
            @click="confirmAttended"
          />
        </div>
      </div>
    </div>
  </transition>
</template>

<style scoped>
.agenda-telemed-overlay {
  position: fixed;
  inset: 0;
  /* Mesma cor clara da Pré-consulta (lobby Meet-style) — evita o flash
     azul-escuro antes do preflight pintar. */
  background: #f6f3f2;
  color: #1c1b1b;
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
  border: 3px solid rgb(var(--blue-9) / 0.18);
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.9s linear infinite;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
.agenda-telemed-error {
  color: rgb(var(--ruby-11));
  max-width: 80%;
  text-align: center;
}
.agenda-telemed-btn {
  margin-top: 12px;
  padding: 10px 20px;
  background: rgb(var(--blue-9));
  color: #fff;
  border: 0;
  border-radius: 10px;
  font-weight: 600;
  cursor: pointer;
}

/* Modal pós-encerramento. Light theme — alinha com o resto do dashboard
   (doctor olha pra ele depois de uma chamada, deve sentir que voltou pra
   UI normal do app). */
.agenda-telemed-end-modal {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
  z-index: 2000;
  backdrop-filter: blur(4px);
}
.agenda-telemed-end-modal__box {
  width: 100%;
  max-width: 440px;
  background: rgb(var(--slate-1));
  color: rgb(var(--slate-12));
  border-radius: 20px;
  padding: 28px 28px 24px;
  box-shadow: 0 20px 50px -12px rgba(15, 23, 42, 0.35);
}
.agenda-telemed-end-modal__title {
  margin: 0 0 12px;
  font-size: 22px;
  font-weight: 700;
  color: rgb(var(--slate-12));
}
.agenda-telemed-end-modal__text {
  margin: 0 0 22px;
  font-size: 14px;
  line-height: 1.55;
  color: rgb(var(--slate-11));
}
.agenda-telemed-end-modal__error {
  margin: 0 0 14px;
  padding: 10px 12px;
  background: rgb(var(--ruby-9) / 0.10);
  border: 1px solid rgb(var(--ruby-9) / 0.30);
  border-radius: 10px;
  font-size: 13px;
  color: rgb(var(--ruby-11));
}
.agenda-telemed-end-modal__actions {
  display: flex;
  gap: 10px;
  justify-content: stretch;
}
.agenda-telemed-end-modal__btn {
  flex: 1;
  padding: 14px 18px;
  border: 0;
  border-radius: 12px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition:
    background 120ms ease,
    transform 80ms ease;
}
.agenda-telemed-end-modal__btn:active:not(:disabled) {
  transform: scale(0.98);
}
.agenda-telemed-end-modal__btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.agenda-telemed-end-modal__btn--ghost {
  background: #f1f5f9;
  color: #475569;
}
.agenda-telemed-end-modal__btn--ghost:hover:not(:disabled) {
  background: #e2e8f0;
}
.agenda-telemed-end-modal__btn--primary {
  background: #1552f1;
  color: #fff;
}
.agenda-telemed-end-modal__btn--primary:hover:not(:disabled) {
  background: #0c3fcc;
}

/* Entrada/saída suaves */
.telemed-end-modal-enter-active,
.telemed-end-modal-leave-active {
  transition: opacity 160ms ease;
}
.telemed-end-modal-enter-active .agenda-telemed-end-modal__box,
.telemed-end-modal-leave-active .agenda-telemed-end-modal__box {
  transition:
    transform 160ms ease,
    opacity 160ms ease;
}
.telemed-end-modal-enter-from,
.telemed-end-modal-leave-to {
  opacity: 0;
}
.telemed-end-modal-enter-from .agenda-telemed-end-modal__box,
.telemed-end-modal-leave-to .agenda-telemed-end-modal__box {
  opacity: 0;
  transform: translateY(8px) scale(0.98);
}
</style>
