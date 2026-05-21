<script setup>
/* eslint-disable no-use-before-define */
// Hoisting é seguro em <script setup>; manter ordem topo→base prioriza
// leitura "o que o componente faz" sobre "ordem de declaração estrita".
// Card de telemedicina no detalhe da consulta (Sprint J + K).
//
// 2026-05-19 (Google Meet pattern, revisão):
//   - Paciente entra a qualquer hora.
//   - Quando o evento está FORA da janela (too_early / window_closed),
//     o clique abre um modal de confirmação INLINE neste card (dentro do
//     app do paciente — não na rota /telemed). Só depois de confirmar
//     a navegação acontece. Antes, o modal aparecia já na sala em fundo
//     escuro, fora do contexto do app.
//   - Modal e botão são LIGHT MODE (UI do portal é toda clara).
//
// Backend (`PatientPortal::TelemedicineSession`) informa permanently_blocked,
// outside_window, can_join_now e starts_in_seconds via `to_h`.
import { computed, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import IconVideo from '@plugins/patient_portal/frontend/components/icons/IconVideo.vue';
import IconClock from '@plugins/patient_portal/frontend/components/icons/IconClock.vue';

const props = defineProps({
  telemedicine: { type: Object, default: () => ({}) },
});

const route = useRoute();
const router = useRouter();

const enabled = computed(() => !!props.telemedicine?.enabled);
const canJoinNow = computed(() => !!props.telemedicine?.can_join_now);
const permanentlyBlocked = computed(
  () => !!props.telemedicine?.permanently_blocked
);
const outsideWindow = computed(() => !!props.telemedicine?.outside_window);
const startsIn = computed(() => props.telemedicine?.starts_in_seconds ?? null);
const reason = computed(() => props.telemedicine?.reason);
const url = computed(() => props.telemedicine?.url);

const canEnter = computed(() => enabled.value && !permanentlyBlocked.value);
const showConfirm = ref(false);

const subtitle = computed(() => {
  if (canJoinNow.value)
    return 'A sala está aberta. Toque em entrar para começar.';
  if (reason.value === 'too_early') return startsInLabel(true);
  if (reason.value === 'window_closed')
    return 'O horário desta consulta já passou — você ainda pode tentar entrar.';
  if (reason.value === 'event_not_joinable')
    return 'Esta consulta não está disponível para vídeo.';
  if (reason.value === 'event_cancelled') return 'Consulta cancelada.';
  return 'Aguarde o horário marcado.';
});

const buttonLabel = computed(() =>
  canJoinNow.value ? 'Entrar agora' : 'Entrar e aguardar'
);

const blockedHint = computed(() => {
  if (reason.value === 'event_cancelled') return 'Consulta cancelada.';
  if (reason.value === 'event_not_joinable')
    return 'Esta consulta já foi encerrada.';
  if (reason.value === 'event_missing_times')
    return 'Agendamento sem horário definido.';
  return 'Esta consulta não está mais disponível para vídeo.';
});

// Formatação amigável "em 46 minutos". `withPreamble=true` adiciona a frase
// completa pra subtitle; sem preamble retorna só o tempo (usado no modal).
function startsInLabel(withPreamble) {
  const s = startsIn.value;
  if (s === null || s === undefined || s <= 0) {
    return withPreamble
      ? 'Você pode entrar e aguardar o profissional.'
      : 'a qualquer momento';
  }
  let label;
  if (s < 60) label = 'menos de 1 minuto';
  else {
    const minutes = Math.ceil(s / 60);
    if (minutes < 60)
      label = `${minutes} ${minutes === 1 ? 'minuto' : 'minutos'}`;
    else {
      const hours = Math.ceil(minutes / 60);
      label = `${hours} ${hours === 1 ? 'hora' : 'horas'}`;
    }
  }
  return withPreamble
    ? `Sua consulta começa em ~${label}. Você pode entrar e aguardar o profissional.`
    : `em ${label}`;
}

function onClickEnter() {
  // Caminho 1: URL externa (Zoom/Meet). Abre direto, sem modal.
  if (url.value) {
    window.open(url.value, '_blank', 'noopener,noreferrer');
    return;
  }
  // Caminho 2: dentro da janela → entra direto na sala (sem confirmação).
  if (!outsideWindow.value) {
    navigateToRoom();
    return;
  }
  // Caminho 3: fora da janela → confirma antes de navegar.
  showConfirm.value = true;
}

function confirmAndEnter() {
  showConfirm.value = false;
  navigateToRoom();
}

function navigateToRoom() {
  // Sprint K — prefere slug `pppp-eeee-aaaa` (estilo Google Meet); fallback
  // pro id puro do appointment quando o backend ainda não devolveu o slug
  // (compat com sessões antigas em cache ou eventos sem patient resolvível).
  const slug = props.telemedicine?.room_code;
  const id = slug || route.params.id;
  if (!id) return;
  router.push({ name: 'telemed-room', params: { id } });
}
</script>

<!-- eslint-disable vue/no-bare-strings-in-template, prettier/prettier -->
<!-- Strings PT-BR hardcoded + prettier desligado pra preservar quebras
     legíveis no parágrafo do modal (MVP Sprint K, pendente i18n). -->
<template>
  <section
    v-if="enabled"
    class="pp-telemed"
    :class="{ 'pp-telemed--live': canJoinNow }"
  >
    <header class="pp-telemed__header">
      <span class="pp-telemed__icon">
        <IconVideo :size="22" />
      </span>
      <div class="pp-telemed__head-text">
        <h3 class="pp-telemed__title">Consulta por vídeo</h3>
        <p class="pp-telemed__subtitle">{{ subtitle }}</p>
      </div>
    </header>

    <button
      v-if="canEnter"
      type="button"
      class="pp-telemed__btn"
      @click="onClickEnter"
    >
      {{ buttonLabel }}
    </button>
    <div v-else class="pp-telemed__hint">{{ blockedHint }}</div>

    <!-- Modal de confirmação INLINE (light, dentro do app do paciente).
         Renderiza via Teleport pra não ficar restrito ao card. -->
    <Teleport to="body">
      <transition
        enter-active-class="pp-telemed-confirm-enter"
        leave-active-class="pp-telemed-confirm-leave"
      >
        <div
          v-if="showConfirm"
          class="pp-telemed-confirm-backdrop"
          @click.self="showConfirm = false"
        >
          <div class="pp-telemed-confirm">
            <div class="pp-telemed-confirm__icon">
              <IconClock :size="28" />
            </div>
            <h2 class="pp-telemed-confirm__title">Quase lá!</h2>
            <p class="pp-telemed-confirm__text">
              Sua consulta começa
              <strong>{{ startsInLabel(false) }}</strong>.
              <br />
              Você pode entrar agora, mas vai ficar em uma
              <em>sala de espera</em> — o profissional precisa permitir o seu
              acesso quando estiver pronto.
            </p>
            <div class="pp-telemed-confirm__actions">
              <button
                type="button"
                class="pp-telemed-confirm__btn pp-telemed-confirm__btn--ghost"
                @click="showConfirm = false"
              >
                Voltar
              </button>
              <button
                type="button"
                class="pp-telemed-confirm__btn pp-telemed-confirm__btn--primary"
                @click="confirmAndEnter"
              >
                Entrar e aguardar
              </button>
            </div>
          </div>
        </div>
      </transition>
    </Teleport>
  </section>
</template>

<style scoped>
.pp-telemed {
  margin: 12px 16px;
  padding: 16px;
  border-radius: 16px;
  background: #fff;
  border: 1px solid var(--pp-color-border);
}
.pp-telemed--live {
  background: linear-gradient(135deg, #0ea5e9, #2563eb);
  color: #fff;
  border-color: transparent;
}

.pp-telemed__header {
  display: flex;
  align-items: center;
  gap: 12px;
}
.pp-telemed__icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  border-radius: 12px;
  background: rgba(37, 99, 235, 0.1);
  color: #2563eb;
}
.pp-telemed--live .pp-telemed__icon {
  background: rgba(255, 255, 255, 0.2);
  color: #fff;
}
.pp-telemed__head-text {
  flex: 1;
  min-width: 0;
}
.pp-telemed__title {
  margin: 0;
  font-size: 15px;
  font-weight: 700;
}
.pp-telemed__subtitle {
  margin: 4px 0 0;
  font-size: 12px;
  opacity: 0.85;
  line-height: 1.4;
}

/* Botão — bg azul sólido sempre, evita "invisível em card branco". Quando
   card está em modo live (gradient azul), invertemos pra branco/texto azul. */
.pp-telemed__btn {
  margin-top: 14px;
  width: 100%;
  padding: 14px;
  background: #2563eb;
  color: #fff;
  border: 0;
  border-radius: 12px;
  font-size: 15px;
  font-weight: 700;
  cursor: pointer;
  transition:
    transform 120ms ease,
    background 120ms ease;
}
.pp-telemed__btn:hover {
  background: #1d4ed8;
}
.pp-telemed__btn:active {
  transform: scale(0.98);
}
.pp-telemed--live .pp-telemed__btn {
  background: #fff;
  color: #1e40af;
}
.pp-telemed--live .pp-telemed__btn:hover {
  background: #f1f5f9;
}

.pp-telemed__hint {
  margin-top: 12px;
  padding: 10px 12px;
  background: rgba(15, 23, 42, 0.04);
  border-radius: 10px;
  font-size: 13px;
  color: var(--pp-color-text-muted);
  text-align: center;
}

/* ─── Modal de confirmação (light) ──────────────────────────────────── */
.pp-telemed-confirm-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.45);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
  z-index: 1000;
}
.pp-telemed-confirm {
  width: 100%;
  max-width: 380px;
  background: #fff;
  border-radius: 20px;
  padding: 28px 24px 20px;
  text-align: center;
  box-shadow: 0 20px 50px -12px rgba(15, 23, 42, 0.35);
}
.pp-telemed-confirm__icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 56px;
  height: 56px;
  margin-bottom: 12px;
  border-radius: 50%;
  background: rgba(37, 99, 235, 0.1);
  color: #2563eb;
}
.pp-telemed-confirm__title {
  margin: 0 0 10px;
  font-size: 19px;
  font-weight: 700;
  color: #0f172a;
}
.pp-telemed-confirm__text {
  margin: 0 0 22px;
  font-size: 14px;
  line-height: 1.55;
  color: #475569;
}
.pp-telemed-confirm__text strong {
  color: #0f172a;
}
.pp-telemed-confirm__text em {
  font-style: normal;
  font-weight: 600;
  color: #2563eb;
}

.pp-telemed-confirm__actions {
  display: flex;
  gap: 10px;
  justify-content: stretch;
}
.pp-telemed-confirm__btn {
  flex: 1;
  padding: 12px 16px;
  border: 0;
  border-radius: 12px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition:
    background 120ms ease,
    transform 80ms ease;
}
.pp-telemed-confirm__btn:active {
  transform: scale(0.97);
}
.pp-telemed-confirm__btn--ghost {
  background: #f1f5f9;
  color: #475569;
}
.pp-telemed-confirm__btn--ghost:hover {
  background: #e2e8f0;
}
.pp-telemed-confirm__btn--primary {
  background: #2563eb;
  color: #fff;
}
.pp-telemed-confirm__btn--primary:hover {
  background: #1d4ed8;
}

/* transitions */
.pp-telemed-confirm-enter {
  animation: confirmIn 180ms ease-out;
}
.pp-telemed-confirm-leave {
  animation: confirmOut 140ms ease-in;
}
@keyframes confirmIn {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
@keyframes confirmOut {
  from {
    opacity: 1;
  }
  to {
    opacity: 0;
  }
}
</style>
