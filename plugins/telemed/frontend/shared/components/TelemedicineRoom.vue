<script setup>
/* eslint-disable no-console, no-use-before-define, no-restricted-syntax, no-continue, no-await-in-loop, no-empty, no-unused-vars */
// Componente PURO da sala de telemedicina (Sprint K).
//
// Lint disables (Sprint K MVP, escopo desta sala apenas):
//   - no-console:               WebRTC tem falhas opacas — logamos pra debug.
//   - no-use-before-define:     `<script setup>` faz hoisting; ordem topo→base
//                               favorece leitura do que o componente faz primeiro.
//   - no-restricted-syntax/no-continue/no-await-in-loop:
//                               getStats() do WebRTC retorna iterators de
//                               RTCStatsReport — for-of é a API canônica.
//   - no-empty:                 catches silenciosos em paths não-fatais (autoplay,
//                               enumerateDevices) propositais pra não derrubar
//                               a UI por uma quirk de browser.
//   - no-unused-vars:           handlers do LiveKit recebem args fixos (track,
//                               publication, participant) mesmo quando só
//                               usamos um.
//
// Recebe { url, token } via props e cuida só do LiveKit. Não chama API,
// não conhece roteamento — quem chamar passa o token já emitido.
// Eventos:
//   - leave: usuário clicou em "Sair" ou apertou voltar.
//
// Reutilizado em 2 wrappers:
//   - TelemedicineRoomPage.vue (patient_portal): paciente
//   - AgendaTelemedRoomPage.vue (agenda):       profissional/dentista
import { ref, computed, onMounted, onUnmounted, nextTick, watch } from 'vue';
import {
  Room,
  RoomEvent,
  Track,
  VideoPresets,
  VideoQuality,
  ConnectionQuality,
  createLocalVideoTrack,
  createLocalAudioTrack,
} from 'livekit-client';
import IconMic from '@plugins/patient_portal/frontend/components/icons/IconMic.vue';
import IconMicOff from '@plugins/patient_portal/frontend/components/icons/IconMicOff.vue';
import IconVideo from '@plugins/patient_portal/frontend/components/icons/IconVideo.vue';
import IconVideoOff from '@plugins/patient_portal/frontend/components/icons/IconVideoOff.vue';
import IconScreenShare from '@plugins/patient_portal/frontend/components/icons/IconScreenShare.vue';
import IconSwitchCamera from '@plugins/patient_portal/frontend/components/icons/IconSwitchCamera.vue';
import IconMessage from '@plugins/patient_portal/frontend/components/icons/IconMessage.vue';
import IconClose from '@plugins/patient_portal/frontend/components/icons/IconClose.vue';
import IconClock from '@plugins/patient_portal/frontend/components/icons/IconClock.vue';
import IconChevronLeft from '@plugins/patient_portal/frontend/components/icons/IconChevronLeft.vue';
import IconChatBubble from '@plugins/patient_portal/frontend/components/icons/IconChatBubble.vue';
import IconShield from '@plugins/patient_portal/frontend/components/icons/IconShield.vue';
import IconBlur from '@plugins/patient_portal/frontend/components/icons/IconBlur.vue';
import { vOnClickOutside } from '@vueuse/components';
import TelemedDeviceSelect from './TelemedDeviceSelect.vue';

const props = defineProps({
  url: { type: String, required: true },
  token: { type: String, required: true },
  devMode: { type: Boolean, default: false },
  headerTitle: { type: String, default: 'Consulta por vídeo' },
  // 2026-05-19 — Google Meet pattern. role muda 2 coisas:
  //   - doctor: publica mic/cam direto. Vê painel "aguardando" com
  //             pacientes pra admitir.
  //   - patient + requiresAdmit=true: NÃO publica até receber admit
  //             via Data Channel. Vê preview local (getUserMedia) e
  //             pode mexer mic/cam antes de ser admitido.
  // role default = 'patient' (mais restritivo — falha pro lado seguro
  // se o wrapper esquecer de passar).
  role: { type: String, default: 'patient' },
  // Quando true E role='patient', entra em sala de espera. O wrapper do
  // paciente passa true quando o backend marcou meta.outside_window=true.
  // Default false: paciente dentro da janela conecta e publica direto.
  requiresAdmit: { type: Boolean, default: false },
  // Slug "pppp-eeee-aaaa" (estilo Google Meet `tkt-vxoc-drv`). Mostrado no
  // header sob o título — útil pra paciente ler pelo telefone se precisar
  // de suporte e pra log/auditoria.
  roomCode: { type: String, default: '' },
  // 2026-05-21 — Lista de identities já admitidas (server-side waiting room).
  // Dentista reidrata estado: se ele recarrega a página, pacientes já
  // aceitos não voltam pro card "Aceitar". Vem do backend em meta.admissions.
  // Formato: { 'patient-12-abc': { admitted_at: '2026-05-21T...' }, ... }
  initialAdmissions: { type: Object, default: () => ({}) },
  // 2026-05-21 — Caller pra admit server-side (chama o endpoint Rails que
  // executa LiveKit UpdateParticipant). Função `async (identity) => {}`.
  // Wrapper do dentista injeta. Wrapper do paciente passa null (no-op).
  admitter: { type: Function, default: null },
  // 2026-05-22 — Estado inicial da gravação manual (vem do payload do
  // endpoint /sessions). Permite reidratar a UI: se o doutor recarrega
  // a página com gravação ON, o botão volta a aparecer aceso.
  initialRecording: {
    type: Object,
    default: () => ({ active: false, started_at: null, consented: false }),
  },
  // 2026-05-22 — Callbacks pra start/stop da gravação manual. Wrapper
  // dashboard injeta as 2; wrapper paciente passa null (paciente não
  // tem controle de gravação, apenas o doutor).
  recordStarter: { type: Function, default: null },
  recordStopper: { type: Function, default: null },
});
// 'sessionEvent' (Sprint K — automação de status):
//   - { kind: 'joined' } — emitido UMA vez quando o local participant
//     conecta ao Room (após publishLocalTracks). Wrapper chama API
//     /telemedicine_event { kind: 'joined' }.
//   - { kind: 'left' } — emitido UMA vez quando sai (RoomEvent.Disconnected
//     ou clique em "Sair"). Idempotência via emitSessionEventOnce.
// Nome camelCase exigido pelo lint vue/custom-event-name-casing (Vue 3
// convention); template pode escutar via @session-event ou @sessionEvent.
// 'endedByHost' — emitido SÓ no lado do paciente quando recebemos um
// `{type:'call_ended'}` do doutor via data channel. Wrapper do paciente
// hooka pra navegar pra home (em vez do detalhe do appointment, que é
// o destino default do `leave`).
const emit = defineEmits(['leave', 'sessionEvent', 'endedByHost']);

// 'preflight' (lobby Meet-style: preview + escolha de devices) → 'connecting'
// → 'connected' | 'disconnected' | 'error'.
const state = ref('preflight');
const errorMessage = ref('');
const micOn = ref(true);
const camOn = ref(true);
const remoteCount = ref(0);

// Sprint L — Consent LGPD/CFM 2.314/2022 pra gravação da teleconsulta.
// Checkbox no preflight; sem aceite, botão "Entrar agora" fica bloqueado.
// Quando aceito, é repassado no `sessionEvent` 'joined' pro backend
// registrar PatientPortalConsent (kind='telemedicine_recording').
//
// Audit Fase 2 — persiste em localStorage por roomCode pra não pedir
// aceite de novo após F5/reconnect. Aceitar uma vez vale pela sala toda.
// Sem roomCode (legacy/dev), comportamento volta a ser session-only.
const consentStorageKey = () =>
  props.roomCode ? `telemed_consent:${props.roomCode}` : null;

const readPersistedConsent = () => {
  try {
    const key = consentStorageKey();
    return key ? window.localStorage.getItem(key) === '1' : false;
  } catch (_) {
    // SSR, privacy mode ou disabled storage — defaulta false (mais seguro).
    return false;
  }
};

const recordingConsent = ref(readPersistedConsent());
const showConsentTerms = ref(false);

watch(recordingConsent, val => {
  try {
    const key = consentStorageKey();
    if (!key) return;
    if (val) window.localStorage.setItem(key, '1');
    else window.localStorage.removeItem(key);
  } catch (_) {
    // idem readPersistedConsent — falha silenciosa, comportamento degrada
    // pra "pede de novo no F5" que é o estado anterior ao fix.
  }
});

// ─── Pre-flight (lobby antes de entrar na sala, Google Meet pattern) ──
// Lista de devices disponíveis + qual está selecionado. Populados em
// `setupPreflight()` via `Room.getLocalDevices`.
const audioInputs = ref([]);
const videoInputs = ref([]);
const audioOutputs = ref([]);
const selectedVideoDevice = ref('');
const selectedAudioDevice = ref('');
// Saída de áudio (speaker selector). Aplicado via setSinkId em todos os
// <audio> remotos quando muda. Safari não suporta setSinkId — nesse caso o
// select fica disabled. Tracking de elements em `audioElementsForSink` pra
// reaplicar quando um novo track remoto chega.
const selectedAudioOutputDevice = ref('');
const supportsAudioOutputSelection =
  typeof HTMLAudioElement !== 'undefined' &&
  typeof HTMLAudioElement.prototype.setSinkId === 'function';
const audioElementsForSink = new Set();
// Resolução real do preview track (vem de `getSettings().{width,height}`).
// Usado pra mostrar "1080p" / "720p" / "360p" no canto do preview.
const previewResolution = ref({ width: 0, height: 0 });
const preflightVideo = ref(null);
// Idempotência do emit 'leave' — `leave()` (clique do usuário) e o evento
// `RoomEvent.Disconnected` (servidor/kick) podem ambos disparar. Sem este
// guard, o wrapper recebe 2x e tenta navegar duas vezes.
let hasEmittedLeave = false;
// Idempotência do emit 'session-event' — joined dispara em connect();
// left dispara em leave() OU em Disconnected. Cada um só vai 1x.
let hasEmittedSessionJoined = false;
let hasEmittedSessionLeft = false;

const chatOpen = ref(false);
const chatInput = ref('');
const messages = ref([]);
const unreadChat = ref(0);
let msgCounter = 0;

// Tempo decorrido desde que entrou na sala (marca em "Em andamento - HH:MM").
// Conta a partir do primeiro `connected`. Em reconnect, NÃO reseta — a chamada
// continua sendo a mesma. Formato HH:MM (hora suprimida se 0).
const callStartedAt = ref(0);
const callElapsedMs = ref(0);
let durationInterval = null;
const liveDurationLabel = computed(() => {
  const total = Math.max(0, Math.floor(callElapsedMs.value / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = n => String(n).padStart(2, '0');
  return h > 0 ? `${pad(h)}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
});

function startDurationTimer() {
  if (durationInterval) return;
  if (!callStartedAt.value) callStartedAt.value = Date.now();
  callElapsedMs.value = Date.now() - callStartedAt.value;
  durationInterval = setInterval(() => {
    callElapsedMs.value = Date.now() - callStartedAt.value;
  }, 1000);
}
function stopDurationTimer() {
  if (durationInterval) {
    clearInterval(durationInterval);
    durationInterval = null;
  }
}

// Google Meet pattern: host (doutor) controla se participantes podem mandar
// mensagem. Quando off, paciente vê input desabilitado e mensagem
// explicativa. Doutor sempre pode mandar (ele É o host). Sincroniza via
// data channel `{type:'chat_lock', enabled:<bool>}` broadcast.
// Default true — chat aberto pra todos, doutor desativa se quiser.
const chatAllowed = ref(true);

const activeSpeaker = ref('');
const screenOn = ref(false);

// ─── Indicador de qualidade da conexão (LiveKit ConnectionQuality) ─────
// LiveKit avalia a conexão de cada participant via RTT, packet loss e
// banda agregada — expõe um enum `Excellent | Good | Poor | Lost | Unknown`
// via `RoomEvent.ConnectionQualityChanged`. Antes era "Conexão estável"
// hardcoded (não refletia a realidade); agora é reativo.
//
// UI: pílula muda label + cor conforme estado. Pra dar sensação de
// "monitoramento ativo" (UX request — "barras se mexendo"), as 3 barrinhas
// animam continuamente em loop discreto, mesmo quando estável. Quando
// instável, vira amarelo e a animação fica mais rápida.
const connectionQuality = ref('unknown'); // 'excellent' | 'good' | 'poor' | 'lost' | 'unknown'

const connectionLabel = computed(() => {
  switch (connectionQuality.value) {
    case 'excellent':
    case 'good':
      return 'Conexão estável';
    case 'poor':
      return 'Conexão instável';
    case 'lost':
      return 'Sem conexão';
    default:
      return 'Conectando…';
  }
});

const connectionState = computed(() => {
  if (connectionQuality.value === 'poor') return 'warn';
  if (connectionQuality.value === 'lost') return 'bad';
  return 'ok';
});

// Mapeia o enum opaco do LiveKit pros nossos string keys (mais fácil de
// inspecionar em DevTools/log que `0|1|2|3`).
function mapConnectionQuality(quality) {
  switch (quality) {
    case ConnectionQuality.Excellent:
      return 'excellent';
    case ConnectionQuality.Good:
      return 'good';
    case ConnectionQuality.Poor:
      return 'poor';
    case ConnectionQuality.Lost:
      return 'lost';
    default:
      return 'unknown';
  }
}

function onConnectionQualityChanged(quality, participant) {
  // Só interessa a qualidade do LOCAL participant (a minha). Quality de
  // remotes representa quão bem ELES estão conectados ao SFU — útil pra
  // diagnóstico de bug ("paciente não me ouve, vê se a conexão dele está
  // ruim"), mas no header mostramos a minha.
  if (!participant?.isLocal) return;
  connectionQuality.value = mapConnectionQuality(quality);
}

// ─── Desfoque de fundo (MediaPipe via @livekit/track-processors) ──────
// Processor roda no browser do usuário — zero custo no servidor (o SFU só
// repassa o stream já processado). O pacote (~3 MB de WASM + modelo) é
// carregado via dynamic import só quando o usuário ATIVA o blur, evitando
// peso no bundle inicial pra quem nunca usa.
//
// Mudanças de intensidade usam `updateTransformerOptions` em vez de
// recriar o processor — assim o pipeline de vídeo não é destruído entre
// frames e NÃO há flash preto na câmera enquanto o slider arrasta. Range
// 5–50 (Meet usa até ~50 também). Valores >30 só fazem sentido em closeups.
const blurEnabled = ref(false);
const blurIntensity = ref(15);
const blurMenuOpen = ref(false);
const blurApplying = ref(false);
let blurProcessor = null;

function getActiveLocalVideoTrack() {
  if (room?.localParticipant) {
    const pub = room.localParticipant.getTrackPublication(Track.Source.Camera);
    if (pub?.videoTrack) return pub.videoTrack;
  }
  return previewVideoTrack;
}

// Liga/desliga o blur. Mantém a instância do processor viva mesmo desligado
// (via setProcessor / stopProcessor no track) pra evitar recarregar o WASM
// quando o usuário re-ativa.
//
// 2026-05-22 — Race guard. Se a câmera foi desligada entre o pedido do
// blur e a execução assíncrona (caso comum quando o usuário togglea
// câmera rápido), o `track` aqui é o stale — chamar setProcessor nele
// trava o WASM e deixa o vídeo preto sem recovery.
async function applyBlurState() {
  const track = getActiveLocalVideoTrack();
  if (!track) return;
  if (!camOn.value) return;
  // O track pode ter sido stopado por trás (toggleCam concorrente);
  // checagem leve antes de tocar no processor.
  if (track.isMuted || track.mediaStreamTrack?.readyState === 'ended') return;
  blurApplying.value = true;
  try {
    if (blurEnabled.value) {
      if (!blurProcessor) {
        const { BackgroundProcessor } = await import(
          '@livekit/track-processors'
        );
        blurProcessor = BackgroundProcessor({
          mode: 'background-blur',
          blurRadius: blurIntensity.value,
        });
      } else {
        // Garante que a intensidade atual está aplicada (caso o usuário tenha
        // mexido no slider com blur off antes de ligar).
        try {
          await blurProcessor.updateTransformerOptions({
            blurRadius: blurIntensity.value,
          });
        } catch (_) {
          /* não-fatal */
        }
      }
      await track.setProcessor(blurProcessor);
    } else {
      try {
        await track.stopProcessor();
      } catch (_) {
        /* já estava sem processor — não-fatal */
      }
      // NÃO zera blurProcessor — reaproveita quando religar.
    }
  } catch (err) {
    console.warn('[telemed] Falha ao aplicar desfoque de fundo:', err);
    blurEnabled.value = false;
  } finally {
    blurApplying.value = false;
  }
}

async function reapplyBlurIfActive() {
  if (!blurEnabled.value) return;
  await applyBlurState();
}

function toggleBlur() {
  blurEnabled.value = !blurEnabled.value;
  applyBlurState();
}

// Atualiza a intensidade do blur em tempo real (sem recriar o processor) —
// chamado pelo slider em cada `input` event. Como updateTransformerOptions é
// barato e roda no próprio loop de frames, NÃO causa flash entre frames.
async function setBlurIntensity(value) {
  const v = Number(value);
  if (Number.isNaN(v)) return;
  blurIntensity.value = Math.max(5, Math.min(50, v));
  if (!blurEnabled.value || !blurProcessor) return;
  try {
    await blurProcessor.updateTransformerOptions({
      blurRadius: blurIntensity.value,
    });
  } catch (err) {
    console.warn('[telemed] Falha ao atualizar intensidade:', err);
  }
}

function toggleBlurMenu() {
  blurMenuOpen.value = !blurMenuOpen.value;
}

function closeBlurMenu() {
  blurMenuOpen.value = false;
}

// ─── Fixar participante em destaque (spotlight, Meet pattern) ─────────
// `pinnedIdentity`: identity do participante em foco. '' = layout normal,
// 'local' = o próprio usuário em destaque, qualquer outra string = remote.
// `pinIsGlobal`: quando true, mudanças são broadcast pra todos via data
// channel — o pin "espalha" pra outros participantes. False = só local.
//
// Quem pode broadcastar: só o doutor (mesma regra do admit/chat_lock).
// Paciente pode fixar localmente, mas não impõe pra todos.
const LOCAL_PIN_KEY = 'local';
const pinnedIdentity = ref('');
const pinIsGlobal = ref(false);
const pinMenuOpenFor = ref('');

const isLocalPinned = computed(() => pinnedIdentity.value === LOCAL_PIN_KEY);
const hasPin = computed(() => pinnedIdentity.value !== '');

function isParticipantPinned(identity) {
  return pinnedIdentity.value === identity;
}

function broadcastPin(identity) {
  if (!room) return;
  try {
    const payload = encoder.encode(
      JSON.stringify({ type: 'pin', identity: identity || '' })
    );
    room.localParticipant.publishData(payload, { reliable: true });
  } catch (e) {
    console.warn('[telemed] broadcastPin falhou:', e);
  }
}

function pinFor(identity, global) {
  pinnedIdentity.value = identity;
  pinIsGlobal.value = !!global;
  pinMenuOpenFor.value = '';
  if (global)
    broadcastPin(identity === LOCAL_PIN_KEY ? getLocalIdentity() : identity);
}

function unpin() {
  const wasGlobal = pinIsGlobal.value;
  pinnedIdentity.value = '';
  pinIsGlobal.value = false;
  pinMenuOpenFor.value = '';
  if (wasGlobal) broadcastPin('');
}

// Posição fixed do menu (teleportado pra body). Calculada a partir do rect
// do botão trigger no momento do abrir — garante que o popup escape do
// `overflow: hidden` dos containers de vídeo (PIP local, tile remoto).
const pinMenuStyle = ref({});

function togglePinMenu(target, event) {
  if (pinMenuOpenFor.value === target) {
    pinMenuOpenFor.value = '';
    return;
  }
  if (event?.currentTarget) {
    const rect = event.currentTarget.getBoundingClientRect();
    const menuHeight = 110;
    const menuWidth = 200;
    const spaceBelow = window.innerHeight - rect.bottom;
    const openUp = spaceBelow < menuHeight + 16;
    const top = openUp ? rect.top - menuHeight - 8 : rect.bottom + 8;
    // Alinha o lado direito do menu com o lado direito do botão; se isso
    // jogar o menu pra fora da viewport (botão muito à esquerda), usa
    // alinhamento pela esquerda como fallback.
    const rightFromEdge = window.innerWidth - rect.right;
    const useRight = rect.right >= menuWidth;
    pinMenuStyle.value = {
      position: 'fixed',
      top: `${Math.max(8, top)}px`,
      ...(useRight
        ? { right: `${Math.max(8, rightFromEdge)}px` }
        : { left: `${rect.left}px` }),
    };
  }
  pinMenuOpenFor.value = target;
}

function closePinMenu() {
  pinMenuOpenFor.value = '';
}

function getLocalIdentity() {
  return room?.localParticipant?.identity || '';
}

const videoDevices = ref([]);
const hasMultipleCameras = ref(false);
// Facing mode da câmera ativa — 'user' (frontal) ou 'environment' (traseira).
// Usado pra decidir se o PIP local deve espelhar (scaleX(-1)). Frontal espelha
// (espelho natural), traseira NÃO (filmando paciente/doutor, espelhar inverte
// texto e referências visuais).
const cameraFacing = ref('user');

// Switch camera (frontal ↔ traseira) só faz sentido em mobile. Em desktop,
// "múltiplas câmeras" geralmente é webcam interna + USB e o caso de troca
// no meio da chamada é raro. Detecta via UA + touch — não é à prova de
// bala, mas evita o botão poluir o layout do desktop.
const isMobile = (() => {
  if (typeof window === 'undefined') return false;
  const ua = window.navigator?.userAgent || '';
  const hasTouch = (window.navigator?.maxTouchPoints || 0) > 0;
  return /Android|iPhone|iPad|iPod|Mobile/i.test(ua) && hasTouch;
})();

// ─── Sala de espera (Google Meet pattern) ─────────────────────────────
// `admitted` controla se o participante já está "ativo" na sala. Doutor
// sempre nasce admitido. Paciente nasce admitido SE não precisa de admit
// (entrou dentro da janela). Paciente em waiting room começa admitted=false
// e só vira true ao receber data channel `{type:'admit'}` do doutor.
const admitted = ref(props.role !== 'patient' || !props.requiresAdmit);
// Lista de pacientes aguardando admissão — só preenchida pro doutor.
// Map<identity, {name, since}> → key = identity LiveKit do paciente.
const pendingPatients = ref(new Map());
// Tracks locais criadas em modo "preview" pro paciente (antes do admit).
// Quando admit chega, publicamos elas via publishTrack. Pro doutor, ficam
// null porque ele usa setMicrophoneEnabled/setCameraEnabled (caminho que
// cria E publica de uma vez só).
let previewVideoTrack = null;
let previewAudioTrack = null;

const isDoctor = computed(() => props.role === 'doctor');
const isWaiting = computed(() => !admitted.value);

// Texto do CTA do preflight muda conforme o fluxo:
//   - Doutor: "Iniciar consulta" (ele É o host).
//   - Paciente com requiresAdmit: "Solicitar entrada na consulta" (espera o
//     doutor admitir).
//   - Paciente dentro da janela (sem admit): "Entrar na consulta".
const enterCtaLabel = computed(() => {
  if (isDoctor.value) return 'Iniciar consulta';
  if (props.requiresAdmit) return 'Solicitar entrada na consulta';
  return 'Entrar na consulta';
});

const localVideo = ref(null);
const chatList = ref(null);

// Tiles dos participantes remotos — array reativo. Antes era um container
// DOM com .appendChild imperativo, mas isso fazia "remoteCount===0" quando
// o paciente conectava sem publicar mídia (getUserMedia falhou). Agora o
// tile aparece no `ParticipantConnected` independente de track, e o vídeo é
// anexado quando o TrackSubscribed chega. Pacientes sem câmera aparecem
// como avatar com inicial — igual Google Meet.
//
// Shape: { id: identity, name, hasVideo, hasAudio, micEnabled, speaking }
const remoteParticipants = ref([]);
// Map paralela identity → { el, videoTrack } pra anexar/desanexar tracks
// quando os refs do Vue mudam. NÃO é reativa (manipulação direta).
const videoBindings = new Map();

const localName = ref('');
const localSpeaking = ref(false);

// 2026-05-22 — Estado da gravação manual (doutor).
// `recordingActive`: true quando gravação está rolando agora.
// `recordingToggling`: true entre clique e resposta do backend (evita
//   double-click do doutor disparar 2 starts em paralelo).
// `recordingError`: string com a mensagem do backend (consent ausente,
//   participants_not_ready, etc.) — mostrada em toast curto.
// `recordHintVisible`: tooltip "balão de gibi" que aparece quando o doctor
//   entra na sala lembrando de gravar. Auto-dismiss em 7s.
const recordingActive = ref(!!props.initialRecording?.active);
const recordingToggling = ref(false);
const recordingError = ref('');
const recordHintVisible = ref(false);
let recordHintTimer = null;

function dismissRecordHint() {
  recordHintVisible.value = false;
  if (recordHintTimer) {
    clearTimeout(recordHintTimer);
    recordHintTimer = null;
  }
}

// Mostra o balão "Não esqueça de gravar essa consulta" pro doutor uma vez
// quando o PACIENTE entra na sala (não quando o doutor entra — antes
// disso o botão fica em estado waiting e clicar não grava, o que
// confundia). Pula se a gravação já estiver ativa (recovery após F5)
// ou se o balão já apareceu nesta sessão.
let recordHintShown = false;
function maybeShowRecordHint() {
  if (!isDoctor.value) return;
  if (recordingActive.value) return;
  if (recordHintShown) return;
  recordHintShown = true;
  recordHintVisible.value = true;
  recordHintTimer = setTimeout(dismissRecordHint, 7000);
}

// Title/aria-label do botão Gravar — reflete o estado em flight pra
// usuário não ficar com tooltip "Aguarde" cortado quando o disabled
// fica ativo no meio do toggle.
const recordButtonTitle = computed(() => {
  if (recordingToggling.value) {
    return recordingActive.value
      ? 'Parando gravação…'
      : 'Iniciando gravação…';
  }
  if (recordingActive.value) return 'Parar gravação';
  return 'Gravar consulta com IA';
});

// Limpa o toast de erro depois de N ms. Cancelável — se o usuário clica
// outra vez, o toast antigo some sem deixar timer órfão.
let recordingErrorTimer = null;
function showRecordingError(message, ms = 8000) {
  recordingError.value = message;
  if (recordingErrorTimer) clearTimeout(recordingErrorTimer);
  recordingErrorTimer = setTimeout(() => {
    recordingError.value = '';
    recordingErrorTimer = null;
  }, ms);
}

// Doutor clicou no botão "Gravar" — alterna estado via API admin que
// chama RecordingOrchestrator.start!/stop!. Sem guard local: o backend
// é a fonte da verdade do estado da sala LiveKit (o tile remoto no
// front mostra `participant.identity`, mas nem sempre coincide 1:1 com
// o que `room_service_client.list_participants` enxerga). Erros do
// backend caem no catch e viram toast.
async function toggleRecording() {
  if (!isDoctor.value) return;
  if (recordingToggling.value) return;
  dismissRecordHint();
  recordingError.value = '';
  recordingToggling.value = true;
  try {
    if (recordingActive.value) {
      if (typeof props.recordStopper === 'function') await props.recordStopper();
      recordingActive.value = false;
    } else {
      if (typeof props.recordStarter !== 'function') return;
      await props.recordStarter();
      recordingActive.value = true;
    }
  } catch (err) {
    // Mensagens human-readable do backend (consent_missing,
    // participants_not_ready) chegam em err.response.data.error.
    // Mantém o estado anterior — sem fingir que iniciou.
    showRecordingError(
      err?.response?.data?.error ||
        err?.message ||
        'Não foi possível alternar a gravação.'
    );
  } finally {
    recordingToggling.value = false;
  }
}

// Lock pra reentrância do toggleCam (clicar rápido OFF/ON quebrava o
// blur processor e deixava câmera preta).
let camToggleInFlight = false;

// Feedback claro pro usuário quando getUserMedia falha. Sem isso, paciente
// vê tela cinza sem entender por quê — bug crítico reportado quando o app
// rodava em HTTP (pacientes.lvh.me:3000) onde Chrome BLOQUEIA câmera/mic.
// Tipos: 'insecure' (HTTP), 'denied' (usuário negou), 'no_device' (sem hw),
//        'in_use' (outra app), 'generic'.
const mediaError = ref(null);

let room = null;
const encoder = new TextEncoder();
const decoder = new TextDecoder();

const stats = ref({
  width: 0,
  height: 0,
  fps: 0,
  kbps: 0,
  codec: '',
  layer: '',
});
const showStats = ref(true);
let statsInterval = null;
let lastBytesReceived = 0;
let lastStatsAt = 0;
// Lista de [event, handler] do Room — registrada em connect(),
// desregistrada em disconnect(). Evita leak de listeners.
let roomListeners = [];

// Handler nomeado (extraído de arrow inline) pra permitir room.off().
//
// 2026-05-22 — Guard contra emit prematuro. Os listeners são registrados
// ANTES de `room.connect()` (ver connect()). Se o handshake falha
// (timeout, token inválido, WS fechado), o LiveKit dispara Disconnected
// durante o connect — e antes o handler chamava emit('leave') aqui, o
// que abria o modal "Como foi a consulta?" no dashboard SEM o doutor
// nem ter entrado na sala. Fix: só emite leave/left quando a sessão foi
// de fato CONNECTED (ou estava reconnecting). Erros pré-conexão são
// tratados pelo catch do connect() que seta state='error'.
function onRoomDisconnected() {
  const hadSession =
    state.value === 'connected' || state.value === 'reconnecting';
  // Pre-conexão: NÃO troca state nem emite. O catch do connect() já vai
  // setar state='error' com a mensagem certa. Sem isso, o user via tela
  // branca (state ficava 'disconnected' que o template não cobre antes
  // de ter conectado) ou o modal pós-encerramento abria sem sessão.
  if (!hadSession) return;
  state.value = 'disconnected';
  // Reporta saída PRA automação. Idempotente — se já mandamos no botão
  // Sair, esta chamada vira no-op.
  emitSessionLeft();
  emitLeaveOnce();
}

// Audit Fase 2 — UX de reconnect.
// LiveKit SDK já tenta reconnect automático (~30s). Antes não havia
// feedback visual: o usuário via "Connected" e de repente "Disconnected"
// se o reconnect falhasse. Agora mostramos um estado intermediário
// `reconnecting` enquanto o SDK tenta — se voltar, retomamos `connected`;
// se desistir, `Disconnected` dispara o handler acima.
function onRoomReconnecting() {
  if (state.value === 'connected') state.value = 'reconnecting';
}

function onRoomReconnected() {
  if (state.value === 'reconnecting') state.value = 'connected';
}

onMounted(setupPreflight);
onUnmounted(disconnect);

// Reage se o componente for reusado com outro token (raro, mas defensivo).
// Reseta `hasEmittedLeave` — sem isso, sair da segunda sala não emitiria
// 'leave' (o guard de idempotência ficou preso da sessão anterior).
watch(
  () => props.token,
  async (next, prev) => {
    if (!prev || next === prev) return;
    disconnect();
    hasEmittedLeave = false;
    state.value = 'connecting';
    await connect();
  }
);

async function connect() {
  try {
    if (!props.url || !props.token) throw new Error('Token de acesso ausente.');

    room = new Room({
      adaptiveStream: true,
      dynacast: true,
      // 2026-05-21 — capture rebaixado de h1080 (1920×1080) pra h720
      // (1280×720). Webcams de notebook costumam ser NATIVAS 720p; pedir
      // 1080p força o browser a digitalmente fazer zoom/upscale e perde
      // campo de visão (usuário vê crop apertado no busto). Meet usa
      // 720p como default pelo mesmo motivo. Bitrate cai junto (menos
      // CPU/banda) sem impacto perceptível — a publish layer mais alta
      // já era 360p (ver simulcastLayers).
      videoCaptureDefaults: { resolution: VideoPresets.h720.resolution },
      publishDefaults: {
        videoSimulcastLayers: [VideoPresets.h180, VideoPresets.h360],
        videoEncoding: VideoPresets.h720.encoding,
        videoCodec: 'vp8',
      },
      audioCaptureDefaults: {
        // 2026-05-21 — `{ideal: true}` explícito em vez de `true`. Em alguns
        // browsers (Chromium versões mais novas), `true` é tratado como
        // "preferred" e pode ser descartado se a constraint anterior for
        // mais restritiva. `{ideal: true}` força o navegador a manter AEC/
        // NS/AGC ON quando o device suporta. Resolve relato de eco
        // duplicando a voz do paciente em notebooks com webcam built-in.
        echoCancellation: { ideal: true },
        noiseSuppression: { ideal: true },
        autoGainControl: { ideal: true },
      },
    });

    // Registro nomeado dos listeners pra garantir cleanup simétrico no
    // disconnect() — sem isso (`room.on` sem `room.off`), cada remount do
    // componente acumulava handlers órfãos no Room antigo (memory leak +
    // double-fire em reuso de instância).
    roomListeners = [
      [RoomEvent.TrackSubscribed, attachRemote],
      [RoomEvent.TrackUnsubscribed, detachRemote],
      [RoomEvent.LocalTrackPublished, attachLocalCamera],
      [RoomEvent.LocalTrackUnpublished, detachLocalCamera],
      // TrackMuted/Unmuted refletem o `isMicrophoneEnabled` do outro lado.
      // Sem isso, não tinha como saber se o paciente apertou mute (a track
      // continua publicada, só vira muted=true). Resultado UI: ícone de
      // mic-off no centro do tile + na pílula do nome (parecido com Meet).
      [RoomEvent.TrackMuted, onRemoteTrackMuted],
      [RoomEvent.TrackUnmuted, onRemoteTrackUnmuted],
      [RoomEvent.DataReceived, handleData],
      [RoomEvent.ActiveSpeakersChanged, onActiveSpeakers],
      [RoomEvent.ParticipantConnected, onParticipantConnected],
      [RoomEvent.ParticipantDisconnected, onParticipantDisconnected],
      [RoomEvent.ConnectionQualityChanged, onConnectionQualityChanged],
      // Disconnected pode vir de 2 origens:
      //   (a) usuário clicou Sair (já emitimos no leave())
      //   (b) servidor encerrou (kick, network drop, room fechado)
      [RoomEvent.Disconnected, onRoomDisconnected],
      // Reconnecting/Reconnected dão feedback visual durante reconnect
      // automático do SDK — sem isso o user via "Connected" → "Disconnected"
      // sem nada no meio.
      [RoomEvent.Reconnecting, onRoomReconnecting],
      [RoomEvent.Reconnected, onRoomReconnected],
      // 2026-05-21 — Server-side waiting room. Quando o dentista chama
      // admit_patient, backend faz LiveKit UpdateParticipant(canPublish=true)
      // e o LiveKit emite ParticipantPermissionsChanged no client do paciente.
      // Aí disparamos applyAdmit() — STOP preview tracks + publish real.
      [RoomEvent.ParticipantPermissionsChanged, onLocalPermissionsChanged],
    ];
    roomListeners.forEach(([event, handler]) => room.on(event, handler));

    await room.connect(props.url, props.token);
    state.value = 'connected';
    startDurationTimer();

    // Sprint K — reporta entrada PRA automação de status. Wrapper escuta
    // o emit e bate em /telemedicine_event. Idempotência: emitSessionJoined
    // só dispara 1x mesmo se connect() for chamado de novo (watch token).
    emitSessionJoined();

    // Bifurcação fundamental:
    //   - Paciente em waiting room: NÃO publica. Cria preview local pra
    //     mostrar a própria câmera e permitir ajustar mic/cam antes do
    //     admit. Quando admit chega, publica.
    //   - Doutor (ou paciente sem requiresAdmit): publica direto via
    //     setMicrophoneEnabled/setCameraEnabled — mesmo caminho de antes.
    if (admitted.value) {
      await publishLocalTracks();
    } else {
      await createPreviewTracks();
    }

    // Varre participants já na sala (entrou DEPOIS deles): cria tile pra
    // cada um e, se for doutor, marca pacientes como pendentes.
    //
    // 2026-05-22 — Também dispara `maybeShowRecordHint` aqui (não só no
    // `onParticipantConnected`) porque o LiveKit NÃO emite ParticipantConnected
    // pra quem já estava na sala antes de você. Sem isso, quando o paciente
    // entrava primeiro (waiting room) e o doutor chegava depois, o lembrete
    // "Não esqueça de gravar" nunca aparecia. Helper ignora chamadas extras
    // (1x por sessão via `recordHintShown`).
    for (const p of room.remoteParticipants.values()) {
      addRemote(p);
      if (isDoctor.value) {
        registerPendingIfPatient(p);
        if (String(p?.identity || '').startsWith('patient-')) {
          maybeShowRecordHint();
        }
      }
      // Tracks já existentes — anexa via attachRemote.
      for (const pub of p.trackPublications.values()) {
        if (pub.track) attachRemote(pub.track, pub, p);
      }
    }

    // Nome local — pra usar no avatar quando câmera off.
    localName.value =
      room.localParticipant?.name || room.localParticipant?.identity || 'Você';

    await refreshDevices();
    // Hot-plug: paciente pode conectar/desconectar câmera USB no meio.
    // Reescaneia a lista de devices pra atualizar `hasMultipleCameras` e
    // o botão de switch sumir/aparecer dinamicamente.
    if (
      typeof navigator !== 'undefined' &&
      navigator.mediaDevices?.addEventListener
    ) {
      navigator.mediaDevices.addEventListener('devicechange', refreshDevices);
    }
  } catch (err) {
    console.error('[telemed] connect falhou:', err);
    state.value = 'error';
    errorMessage.value = err.message || 'Falha ao conectar.';
  }
}

async function refreshDevices() {
  try {
    videoDevices.value = await Room.getLocalDevices('videoinput');
    hasMultipleCameras.value = videoDevices.value.length > 1;
  } catch (_) {
    /* não-fatal */
  }
}

// Caminho do doutor (ou paciente já admitido) — cria E publica os tracks.
// LiveKit gera os MediaStreamTracks por baixo, publica no SFU e dispara
// LocalTrackPublished que renderiza no PIP via attachLocalCamera.
//
// Tratamento de erro: se mic OU cam falham, traduzimos o erro pra mensagem
// amigável via mediaError. Antes ficava silencioso e o usuário via tela
// cinza sem entender — bug crítico em HTTP.
//
// 2026-05-21 — STOPA os preview tracks da preflight ANTES de publicar.
// Sem isso, getUserMedia abria 2 captures do mesmo mic (1 do preflight +
// 1 do setMicrophoneEnabled). Em alguns devices (notebooks com webcam
// built-in) isso causava ECO PERSISTENTE — o AEC do browser ficava
// confuso com 2 streams paralelos do mesmo input. Resolve relato
// 2026-05-21 "voz do paciente duplica e fica duplicando".
async function publishLocalTracks() {
  if (!room) return;
  if (!checkSecureContext()) return;

  // Stop dos preview tracks ANTES de pedir novos via setXxxEnabled — evita
  // 2 captures ativos do mesmo mic/cam.
  if (previewAudioTrack) {
    try {
      previewAudioTrack.stop();
    } catch (_) {}
    previewAudioTrack = null;
  }
  if (previewVideoTrack) {
    try {
      previewVideoTrack.stop();
    } catch (_) {}
    previewVideoTrack = null;
  }

  let captured = false;
  // Respeita micOn/camOn (usuário pode ter desligado no preflight) e o
  // deviceId selecionado (segundo parâmetro do setXxxEnabled aceita opções
  // de captura). Sem isso, paciente que escolheu "Webcam USB" no preflight
  // entraria com a câmera built-in.
  //
  // 2026-05-21 — `{ideal: true}` nos flags AEC/NS/AGC pra forçar o navegador
  // a HONRAR essas constraints quando o device suporta (alguns browsers
  // tratam `true` como "preferred"; `{ideal: true}` é mais explícito).
  const audioOpts = {
    echoCancellation: { ideal: true },
    noiseSuppression: { ideal: true },
    autoGainControl: { ideal: true },
    ...(selectedAudioDevice.value
      ? { deviceId: selectedAudioDevice.value }
      : {}),
  };
  const videoOpts = selectedVideoDevice.value
    ? { deviceId: selectedVideoDevice.value }
    : undefined;
  try {
    await room.localParticipant.setMicrophoneEnabled(micOn.value, audioOpts);
  } catch (err) {
    console.warn('[telemed] mic falhou:', err);
    micOn.value = false;
    mediaError.value = mapMediaError(err);
    captured = true;
  }
  try {
    await room.localParticipant.setCameraEnabled(camOn.value, videoOpts);
    await reapplyBlurIfActive();
  } catch (err) {
    console.warn('[telemed] câmera falhou:', err);
    camOn.value = false;
    if (!captured) mediaError.value = mapMediaError(err);
  }
}

// Caminho do paciente em waiting room — cria tracks LOCAIS mas NÃO publica.
// Servem só pra preview da própria câmera (UX: paciente confere câmera/mic
// enquanto aguarda admit). Quando admit chega, publishTrack reusa esses.
//
// Erros viram mediaError pra mostrar UI explicativa.
//
// 2026-05-21 — STOPA tracks anteriores antes de criar novos. Antes, se
// `createPreviewTracks` era chamado depois da preflight (que já tinha
// criado preview tracks), os tracks antigos ficavam órfãos sem stop —
// 2 captures do mesmo mic ativos simultaneamente (eco/duplicação).
async function createPreviewTracks() {
  if (!checkSecureContext()) return;

  // Limpa tracks da preflight antes de criar novos no connect()
  if (previewVideoTrack) {
    try {
      previewVideoTrack.stop();
    } catch (_) {}
    previewVideoTrack = null;
  }
  if (previewAudioTrack) {
    try {
      previewAudioTrack.stop();
    } catch (_) {}
    previewAudioTrack = null;
  }

  let captured = false;
  try {
    previewVideoTrack = await createLocalVideoTrack({
      resolution: VideoPresets.h720.resolution,
      deviceId: selectedVideoDevice.value || undefined,
    });
    try {
      const fm =
        previewVideoTrack.mediaStreamTrack?.getSettings?.()?.facingMode;
      if (fm) cameraFacing.value = fm;
    } catch (_) {
      /* não-fatal */
    }
    // Attach manual no element <video ref="localVideo"> — não usa o caminho
    // LocalTrackPublished porque não publicamos ainda.
    nextTick(() => {
      if (localVideo.value && previewVideoTrack) {
        previewVideoTrack.attach(localVideo.value);
        localVideo.value.play().catch(() => {});
      }
    });
    // Reaplica desfoque ao novo track de preview (caso usuário já tinha
    // ativado e estamos recriando depois de uma troca de device).
    await reapplyBlurIfActive();
  } catch (err) {
    console.warn('[telemed] preview camera falhou:', err);
    camOn.value = false;
    mediaError.value = mapMediaError(err);
    captured = true;
  }
  try {
    previewAudioTrack = await createLocalAudioTrack({
      echoCancellation: { ideal: true },
      noiseSuppression: { ideal: true },
      autoGainControl: { ideal: true },
      deviceId: selectedAudioDevice.value || undefined,
    });
  } catch (err) {
    console.warn('[telemed] preview mic falhou:', err);
    micOn.value = false;
    if (!captured) mediaError.value = mapMediaError(err);
  }
}

// Paciente foi admitido (via data channel) — para os preview tracks e
// publica via path normal (setCameraEnabled/setMicrophoneEnabled).
//
// Por que esse caminho e não publishTrack(previewTrack):
// publishTrack do track standalone funcionava no client (track entrava
// na sala), mas o doutor às vezes não recebia o TrackSubscribed event
// — provavelmente porque a track não estava associada a `Track.Source.Camera`
// e o LiveKit tem heurística sobre quais tracks renderizar como remote
// participants reais. O caminho `setXxxEnabled` cria a track JÁ com
// `Source.Camera` e `Source.Microphone` corretos, garantindo que o
// doutor receba via subscribe normal.
//
// Trade-off: pode haver um pequeno flicker da câmera reabrindo, mas as
// permissions estão cacheadas no browser — usuário não vê prompt.
async function applyAdmit() {
  if (admitted.value) return;
  admitted.value = true;
  if (!room) return;

  // Stopa tracks de preview ANTES de chamar setXxxEnabled pra evitar
  // que duas streams da mesma câmera/mic fiquem ativas ao mesmo tempo.
  if (previewVideoTrack) {
    try {
      previewVideoTrack.stop();
    } catch (_) {}
    previewVideoTrack = null;
  }
  if (previewAudioTrack) {
    try {
      previewAudioTrack.stop();
    } catch (_) {}
    previewAudioTrack = null;
  }

  // Pequeno delay pra garantir que o SO liberou o handle do mic/cam ANTES
  // de pedir de novo — sem isso alguns browsers retornavam o stream antigo
  // (já parado) ou abriam um segundo capture em paralelo (eco).
  await new Promise(resolve => setTimeout(resolve, 80));

  // Respeita o estado micOn/camOn que o paciente deixou no waiting room
  // (se desligou o mic enquanto esperava, ele segue desligado depois).
  // 2026-05-21 — passa audioOpts com constraints AEC/NS/AGC explícitas
  // (ver publishLocalTracks pro racional).
  const audioOpts = {
    echoCancellation: { ideal: true },
    noiseSuppression: { ideal: true },
    autoGainControl: { ideal: true },
    ...(selectedAudioDevice.value
      ? { deviceId: selectedAudioDevice.value }
      : {}),
  };
  const videoOpts = selectedVideoDevice.value
    ? { deviceId: selectedVideoDevice.value }
    : undefined;
  try {
    await room.localParticipant.setMicrophoneEnabled(micOn.value, audioOpts);
  } catch (err) {
    console.warn('[telemed] applyAdmit mic publish falhou:', err);
  }
  try {
    await room.localParticipant.setCameraEnabled(camOn.value, videoOpts);
    await reapplyBlurIfActive();
  } catch (err) {
    console.warn('[telemed] applyAdmit cam publish falhou:', err);
  }

  // Grace period de 2s antes de desmutar o áudio remoto. Dá tempo pro
  // vídeo terminar de subir e evita o paciente ouvir um clique/pedaço de
  // conversa enquanto a UI ainda está montando os tiles.
  setTimeout(unmuteAllRemoteAudio, 2000);
}

// 2026-05-21 — Listener pro ParticipantPermissionsChanged.
// LiveKit dispara esse evento quando o servidor atualiza as permissions
// de um participant. No nosso fluxo: backend chama UpdateParticipant pra
// dar canPublish=true ao paciente quando o dentista clica "Aceitar".
//
// O SDK passa (prevPermissions, participant). Filtra:
//   - Só interessa o LOCAL participant (ignora doutor recebendo evento
//     sobre outro paciente).
//   - Paciente em waiting room que ganhou canPublish → dispara applyAdmit().
//   - Doutor (já admitido na conexão) é no-op.
function onLocalPermissionsChanged(prevPermissions, participant) {
  if (!room) return;
  const local = room.localParticipant;
  if (!local || !participant) return;
  // SDK pode disparar o evento pra remote participants também — filtra.
  if (participant.identity !== local.identity) return;
  if (admitted.value) return;
  const canPublishNow = !!participant.permissions?.canPublish;
  if (!canPublishNow) return;
  applyAdmit();
}

// Extrai patient_id de identity `patient-{ID}-{nonce}` (formato emitido por
// Telemed::SessionIssuer). Backend persiste admissões por patient_id (não
// pela identity completa) pra sobreviver a F5/reconnect do paciente.
function extractPatientId(identity) {
  if (!identity) return null;
  const m = /^patient-(\d+)/.exec(identity);
  return m ? m[1] : null;
}

// Doutor — registra remote participant como pendente se for identity patient-*.
//
// 2026-05-21 — Filtra pacientes já admitidos server-side. Chave por
// patient_id (não identity completa): se o paciente recarregar, vem com
// novo nonce mas ainda casa via patient_id.
function registerPendingIfPatient(participant) {
  if (!isDoctor.value) return;
  const id = participant?.identity;
  if (!id || !id.startsWith('patient-')) return;
  const pid = extractPatientId(id);
  // Reidratação: paciente já foi admitido server-side → não mostra card.
  if (pid && props.initialAdmissions && props.initialAdmissions[pid]) return;
  // Map é reativo só com .set, então clonamos pra disparar reatividade.
  const next = new Map(pendingPatients.value);
  next.set(id, {
    name: participant.name || participant.identity,
    since: Date.now(),
  });
  pendingPatients.value = next;
}

function unregisterPending(identity) {
  if (!pendingPatients.value.has(identity)) return;
  const next = new Map(pendingPatients.value);
  next.delete(identity);
  pendingPatients.value = next;
}

// Doutor ignora o pedido localmente (não broadcasta). O paciente continua
// no waiting room — se o doutor mudar de ideia, o card volta na próxima
// ParticipantConnected ou no F5. Mais leve que "kick" pelo SFU.
function dismissPending(identity) {
  unregisterPending(identity);
}

// "Pediu agora" se < 60s, senão "X min". `since` é Date.now(). Re-renderiza
// automaticamente a cada segundo porque o `liveDurationLabel` (lido em
// outro lugar do template) é reativo e força repaint do componente.
function formatPendingDuration(since) {
  const elapsed = Math.max(0, Math.floor((Date.now() - since) / 1000));
  if (elapsed < 60) return 'agora';
  const min = Math.floor(elapsed / 60);
  return `${min} min`;
}

function onParticipantConnected(participant) {
  addRemote(participant);
  registerPendingIfPatient(participant);
  // 2026-05-22 — Lembrete de gravação só dispara quando o PACIENTE entra
  // (antes disso o botão fica em waiting e a UX é confusa). Helper ignora
  // chamadas extras (1x por sessão).
  if (String(participant?.identity || '').startsWith('patient-')) {
    maybeShowRecordHint();
  }
}

function onParticipantDisconnected(participant) {
  removeRemote(participant.identity);
  unregisterPending(participant.identity);
}

// ─── Tiles dos remotos (Google Meet pattern) ──────────────────────────
// Tile aparece ASSIM QUE o participant conecta — sem esperar tracks.
// Pacientes sem câmera ainda aparecem (com avatar). Pacientes com mídia
// pendente (getUserMedia falhou) também aparecem — doutor sabe que tem
// alguém na sala mesmo sem vídeo.

function addRemote(participant) {
  if (!participant) return;
  const id = participant.identity;
  if (remoteParticipants.value.find(p => p.id === id)) return;
  // micMuted default true até receber TrackSubscribed pro mic — assim o
  // ícone de mic-off já aparece pro participante recém-conectado sem audio
  // ainda. Quando o track chega, recalculamos via publication.isMuted.
  remoteParticipants.value = [
    ...remoteParticipants.value,
    {
      id,
      name: participant.name || participant.identity || 'Participante',
      hasVideo: false,
      hasAudio: false,
      micMuted: true,
      speaking: false,
      isScreenShare: false,
    },
  ];
}

// Tile sintético pro screen share de um remoto. Convive lado-a-lado com o
// tile da câmera (mesmo padrão do Meet). Removido em detachRemote quando
// o share termina, ou em removeRemote quando o publisher desconecta.
function addRemoteScreenShare(participant) {
  if (!participant) return;
  const id = `${participant.identity}::screen`;
  if (remoteParticipants.value.find(p => p.id === id)) return;
  const baseName = participant.name || participant.identity || 'Participante';
  remoteParticipants.value = [
    ...remoteParticipants.value,
    {
      id,
      name: `${baseName} (compartilhamento)`,
      hasVideo: true,
      hasAudio: false,
      micEnabled: false,
      speaking: false,
      isScreenShare: true,
    },
  ];
}

function removeRemote(identity) {
  // Remove o tile principal E o tile sintético de screen share (se existir).
  // Sem isso, quando o publisher desconecta direto (sem antes parar o share),
  // o tile fantasma do share fica pra sempre no DOM até refresh.
  const screenId = `${identity}::screen`;
  remoteParticipants.value = remoteParticipants.value.filter(
    p => p.id !== identity && p.id !== screenId
  );
  [identity, screenId].forEach(key => {
    const binding = videoBindings.get(key);
    if (binding?.videoTrack) {
      try {
        binding.videoTrack.detach();
      } catch (_) {}
    }
    videoBindings.delete(key);
  });
}

function updateRemote(identity, patch) {
  const idx = remoteParticipants.value.findIndex(p => p.id === identity);
  if (idx === -1) return;
  remoteParticipants.value = remoteParticipants.value.map((p, i) =>
    i === idx ? { ...p, ...patch } : p
  );
}

// Binding ref→track. Vue chama `bindRemoteVideo(id, el)` quando o <video>
// é montado/desmontado pelo v-for. Quando temos os DOIS (el + track),
// anexa o track.
function bindRemoteVideo(id, el) {
  const entry = videoBindings.get(id) || {};
  entry.el = el || null;
  if (entry.videoTrack && el) {
    try {
      entry.videoTrack.attach(el);
      el.play?.().catch(() => {});
    } catch (_) {}
  }
  videoBindings.set(id, entry);
}

// Doutor clicou "Admitir" pra um paciente específico.
//
// 2026-05-21 — Agora server-side first:
//   1. Chama API admit_patient (props.admitter) → backend faz
//      LiveKit UpdateParticipant(canPublish=true). LiveKit emite
//      ParticipantPermissionsChanged no client do paciente → applyAdmit().
//   2. Envia data channel `admit` como fallback de UX (caso o client do
//      paciente esteja em versão antiga sem o listener de permissions).
//      Inofensivo: applyAdmit é idempotente.
//   3. Se a API falhar, NÃO remove o paciente da lista de pendentes — o
//      dentista clica de novo. Sem isso, falha silenciosa = dentista
//      pensa que admitiu e paciente continua bloqueado.
async function admitPatient(identity) {
  if (!room || !isDoctor.value) return;
  let serverOk = true;
  if (typeof props.admitter === 'function') {
    try {
      await props.admitter(identity);
    } catch (err) {
      serverOk = false;
      console.error('[telemed] admit (server) falhou:', err);
      // Mantém na lista de pendentes pra dentista tentar de novo.
      return;
    }
  }
  // Data channel — fallback de UX (idempotente no client do paciente).
  try {
    const payload = encoder.encode(
      JSON.stringify({ type: 'admit', target: identity })
    );
    await room.localParticipant.publishData(payload, {
      reliable: true,
      destinationIdentities: [identity],
    });
  } catch (err) {
    console.warn('[telemed] admit (data channel) falhou:', err);
    // Não bloqueia — server-side já fez o trabalho real.
  }
  if (serverOk) unregisterPending(identity);
}

function attachLocalCamera(publication) {
  // Filtra por source (não kind) — sem isso, screen share (também Video)
  // entrava aqui e era atachado no elemento do PIP local, SOBRESCREVENDO
  // a câmera. Resultado: ao parar o compartilhamento, o elemento ficava
  // vazio e nem religar a câmera resolvia (o novo track era atachado,
  // mas o handler do screen share continuava interferindo).
  if (publication.source !== Track.Source.Camera) return;
  try {
    const fm = publication.track?.mediaStreamTrack?.getSettings?.()?.facingMode;
    if (fm) cameraFacing.value = fm;
  } catch (_) {
    /* não-fatal */
  }
  nextTick(() => {
    if (!localVideo.value || !publication.track) return;
    publication.track.attach(localVideo.value);
    localVideo.value.play().catch(() => {});
  });
}

function detachLocalCamera(publication) {
  // Camera unpublish — limpa o elemento. Screen share unpublish dispara
  // onLocalScreenShareEnded (abaixo) pra sincronizar o estado do botão.
  if (publication.source === Track.Source.ScreenShare) {
    onLocalScreenShareEnded();
    return;
  }
  if (publication.source !== Track.Source.Camera) return;
  publication.track?.detach();
}

// Quando o usuário para de compartilhar pelo botão NATIVO do browser
// ("Stop sharing"), o LiveKit auto-chama setScreenShareEnabled(false) e
// emite LocalTrackUnpublished — mas nosso `screenOn` ficava dessincronizado
// (continuava true). Próximo clique no nosso botão era no-op e atrapalhava
// o fluxo. Esse handler garante o estado bate com a realidade.
//
// Re-attach defensivo da câmera: em alguns browsers (observado no Chrome
// desktop), parar o screen share deixava o <video> local com srcObject nulo
// — a câmera continuava publicada e tocando do outro lado, mas o PIP do
// doutor mostrava avatar/inicial como se estivesse off. Reanexar a track da
// câmera ao localVideo aqui resolve o "fantasma off" sem efeito colateral
// (se já estiver anexada, attach() é idempotente).
function onLocalScreenShareEnded() {
  if (screenOn.value) screenOn.value = false;
  if (!room) return;
  const camPub = room.localParticipant?.getTrackPublication?.(
    Track.Source.Camera
  );
  const camTrack = camPub?.videoTrack || camPub?.track;
  if (!camTrack || !localVideo.value) return;
  try {
    camTrack.attach(localVideo.value);
    localVideo.value.play().catch(() => {});
  } catch (_) {
    /* não-fatal — se attach falhar, próximo render do Vue acomoda */
  }
}

// Trata novo track de um remote. Em vez de criar element imperativamente,
// guardamos o track no binding por identity. O <video> declarativo do
// template (v-for nos tiles) chama bindRemoteVideo() quando o ref é
// definido, aí o anexamos.
//
// Screen share recebe um TILE SEPARADO (id sintético `${identity}::screen`).
// Sem isso, o screen share — que também é Track.Kind.Video — sobrescrevia
// `entry.videoTrack` da câmera e o <video> da câmera ficava com o stream
// errado (HTMLMediaElement.srcObject só aceita um stream). Resultado pro
// outro lado: "minha câmera some quando o colega compartilha tela". Tile
// sintético segue o padrão Google Meet (tile da câmera + tile do share).
function attachRemote(track, publication, participant) {
  if (track.kind !== Track.Kind.Audio && track.kind !== Track.Kind.Video)
    return;

  const isScreen =
    track.kind === Track.Kind.Video &&
    publication?.source === Track.Source.ScreenShare;
  const realIdentity = participant.identity;
  const tileId = isScreen ? `${realIdentity}::screen` : realIdentity;

  if (isScreen) {
    addRemoteScreenShare(participant);
  } else {
    // Garante que o tile existe (defesa caso ParticipantConnected tenha
    // chegado depois — não deveria, mas custa pouco).
    addRemote(participant);
  }

  if (track.kind === Track.Kind.Video) {
    if (publication?.setVideoQuality) {
      try {
        publication.setVideoQuality(VideoQuality.HIGH);
      } catch (_) {
        /* não-fatal */
      }
    }
    const entry = videoBindings.get(tileId) || {};
    entry.videoTrack = track;
    videoBindings.set(tileId, entry);
    if (entry.el) {
      try {
        track.attach(entry.el);
        entry.el.play?.().catch(() => {});
      } catch (_) {}
    }
    updateRemote(tileId, { hasVideo: true });

    if (!statsInterval) {
      statsInterval = setInterval(refreshStats, 2000);
      refreshStats();
    }
  } else if (track.kind === Track.Kind.Audio) {
    // Audio track precisa de um <audio> attached pra tocar. Criamos um
    // hidden audio element por audio track — sem isso o doutor não OUVE
    // o paciente mesmo com o tile renderizado.
    const audioEl = track.attach();
    audioEl.classList.add('pp-telemed-room__remote-audio');
    audioEl.setAttribute('autoplay', '');
    // 2026-05-21 — `playsinline` obrigatório no iOS (Safari mobile recusa
    // autoplay de mídia sem ele). Sem isso, o paciente em iPhone às vezes
    // só ouvia depois de tocar na tela.
    audioEl.setAttribute('playsinline', '');
    audioEl.style.display = 'none';
    // LGPD/UX: se o usuário ainda não foi admitido (paciente em waiting
    // room), o áudio remoto começa MUTADO. Sem isso, o paciente escutava
    // a conversa do consultório antes de o doutor aceitá-lo — vazamento
    // de privacidade clínica. applyAdmit() desmuta após o grace period.
    if (!admitted.value) audioEl.muted = true;
    document.body.appendChild(audioEl);
    audioElementsForSink.add(audioEl);
    applyAudioSink(audioEl);
    const id = participant.identity;
    const entry = videoBindings.get(id) || {};
    if (!entry.audioElements) entry.audioElements = new Map();
    entry.audioElements.set(track.sid, audioEl);
    videoBindings.set(id, entry);
    // micMuted recalculado a cada subscribe — se a publication chegou já
    // mutada (paciente entrou com mic off no preflight), ícone aparece
    // imediato. Default false (sem ser ::screen).
    updateRemote(realIdentity, {
      hasAudio: true,
      micMuted: publication?.isMuted === true,
    });
  }
}

// Reage a mute/unmute remoto. O LiveKit dispara TrackMuted/Unmuted pra
// QUALQUER track — filtramos por source pra atualizar só o estado de mic
// (vídeo muted = câmera off; tratamos via hasVideo separadamente).
function onRemoteTrackMuted(publication, participant) {
  if (!participant?.identity) return;
  if (publication?.source === Track.Source.Microphone) {
    updateRemote(participant.identity, { micMuted: true });
  }
}

function onRemoteTrackUnmuted(publication, participant) {
  if (!participant?.identity) return;
  if (publication?.source === Track.Source.Microphone) {
    updateRemote(participant.identity, { micMuted: false });
  }
}

// Desmuta todos os elementos de áudio remoto. Chamado pelo applyAdmit
// após o grace period — garante que o paciente só comece a ouvir DEPOIS
// que entrou de fato (não enquanto carrega vídeo/track).
function unmuteAllRemoteAudio() {
  audioElementsForSink.forEach(el => {
    el.muted = false;
  });
}

function detachRemote(track, publication, participant) {
  const realIdentity = participant?.identity;
  if (!realIdentity) return;

  // Screen share tem id sintético — espelha a lógica de attachRemote.
  const isScreen =
    track.kind === Track.Kind.Video &&
    publication?.source === Track.Source.ScreenShare;
  const id = isScreen ? `${realIdentity}::screen` : realIdentity;
  const entry = videoBindings.get(id);
  if (!entry) return;

  if (track.kind === Track.Kind.Video && entry.videoTrack === track) {
    try {
      track.detach();
    } catch (_) {}
    entry.videoTrack = null;
    videoBindings.set(id, entry);
    if (isScreen) {
      // Tile sintético do screen share existe SÓ enquanto o share está ativo.
      // Quando o publisher para de compartilhar, removemos do array reativo —
      // diferente da câmera, que pode ficar como avatar/inicial.
      removeRemote(id);
    } else {
      updateRemote(id, { hasVideo: false });
    }
  } else if (track.kind === Track.Kind.Audio) {
    const el = entry.audioElements?.get(track.sid);
    if (el) {
      try {
        track.detach();
      } catch (_) {}
      audioElementsForSink.delete(el);
      el.remove();
      entry.audioElements.delete(track.sid);
    }
    updateRemote(id, { hasAudio: (entry.audioElements?.size || 0) > 0 });
  }
}

// Aplica o sinkId selecionado em um <audio> remoto. Tolerante a navegadores
// sem suporte (Safari): no-op. Tolerante a deviceId inválido: catch silencioso.
function applyAudioSink(audioEl) {
  if (!supportsAudioOutputSelection || !selectedAudioOutputDevice.value) return;
  try {
    audioEl.setSinkId(selectedAudioOutputDevice.value).catch(() => {});
  } catch (_) {
    /* Browser sem suporte ou deviceId fora de política — não-fatal. */
  }
}

async function changeAudioOutputDevice(deviceId) {
  selectedAudioOutputDevice.value = deviceId;
  if (!supportsAudioOutputSelection) return;
  audioElementsForSink.forEach(el => applyAudioSink(el));
}

async function sendChat() {
  const text = chatInput.value.trim();
  if (!text || !room) return;
  // Paciente respeita lock; doutor (host) sempre pode mandar.
  if (!isDoctor.value && !chatAllowed.value) return;
  const payload = encoder.encode(JSON.stringify({ type: 'chat', text }));
  await room.localParticipant.publishData(payload, { reliable: true });
  appendMessage({ author: 'Você', text, fromMe: true });
  chatInput.value = '';
}

// Doutor (host) toggla chat lock. Envia data channel broadcast (sem target —
// todos pacientes recebem) e atualiza estado local. Sem destinationIdentities
// pra alcançar TODOS os pacientes na sala.
async function toggleChatLock() {
  if (!room || !isDoctor.value) return;
  chatAllowed.value = !chatAllowed.value;
  try {
    const payload = encoder.encode(
      JSON.stringify({ type: 'chat_lock', enabled: chatAllowed.value })
    );
    await room.localParticipant.publishData(payload, { reliable: true });
  } catch (e) {
    console.warn('[telemed] toggleChatLock falhou:', e);
  }
}

function handleData(payload, participant) {
  try {
    const data = JSON.parse(decoder.decode(payload));

    // Admit do doutor pro paciente (Google Meet pattern). EXIGE:
    //   - sender com identity `doctor-*` (paciente não pode auto-admitir
    //     nem admitir outro paciente via console)
    //   - target == minha identity (ignora broadcasts inválidos)
    // Sem essas duas checagens, qualquer paciente injetando
    // {type:'admit'} via DevTools entrava sozinho na sala.
    if (data.type === 'admit') {
      const senderId = participant?.identity || '';
      if (!senderId.startsWith('doctor-')) return;
      const myId = room?.localParticipant?.identity;
      if (data.target && data.target === myId) applyAdmit();
      return;
    }

    if (data.type === 'chat') {
      appendMessage({
        author: participant?.name || participant?.identity || 'Participante',
        text: data.text,
        fromMe: false,
      });
      if (!chatOpen.value) unreadChat.value += 1;
      return;
    }

    // chat_lock pode vir só do doutor (host). Ignora se enviado por outro
    // paciente via DevTools — mesma defesa do admit. Pacientes atualizam
    // o estado local pra refletir o que o host configurou.
    if (data.type === 'chat_lock') {
      const senderId = participant?.identity || '';
      if (!senderId.startsWith('doctor-')) return;
      chatAllowed.value = !!data.enabled;
      return;
    }

    // Pin "pra todos" (spotlight broadcast). Mesma defesa: só aceito de
    // doutor pra não permitir paciente forçar foco em si mesmo via DevTools.
    // identity vazia = unpin (clear spotlight global).
    if (data.type === 'pin') {
      const senderId = participant?.identity || '';
      if (!senderId.startsWith('doctor-')) return;
      const target = data.identity || '';
      if (!target) {
        // unpin global — só limpa se o pin atual era global (não pisa em
        // cima de pin local do usuário).
        if (pinIsGlobal.value) {
          pinnedIdentity.value = '';
          pinIsGlobal.value = false;
        }
        return;
      }
      pinnedIdentity.value =
        target === getLocalIdentity() ? LOCAL_PIN_KEY : target;
      pinIsGlobal.value = true;
      return;
    }

    // Encerramento iniciado pelo doutor — paciente é desconectado e o
    // wrapper navega pra home (UX: paciente não precisa apertar Sair se o
    // doutor já encerrou). Só aceito vindo de identity `doctor-*` pra
    // paciente não forçar saída de outro paciente via DevTools. Idempotente:
    // múltiplos broadcasts (raro) caem no guard `hasEmittedLeave`.
    if (data.type === 'call_ended') {
      const senderId = participant?.identity || '';
      if (!senderId.startsWith('doctor-')) return;
      if (isDoctor.value) return; // doutor não se auto-encerra via broadcast
      leaveBecauseHostEnded();
    }
  } catch (e) {
    console.warn('[telemed] data inválido:', e);
  }
}

// Saída forçada do paciente quando o doutor encerra. Diferente de `leave()`
// (clique do próprio paciente), aqui emitimos `'ended-by-host'` pro wrapper
// — ele decide a rota (home, no caso do portal do paciente). Mantém o
// fluxo de session-event (`'left'`) intacto pra automação de status no
// backend.
function leaveBecauseHostEnded() {
  if (hasEmittedLeave) return;
  emitSessionLeft();
  disconnect();
  hasEmittedLeave = true;
  emit('endedByHost');
}

// Cap pra evitar growth ilimitado em sessões longas (consulta de 50min
// com chat ativo poderia gerar 200+ mensagens). Mantemos só as últimas N.
const MAX_CHAT_MESSAGES = 200;

function appendMessage(msg) {
  msgCounter += 1;
  messages.value.push({ id: msgCounter, ...msg });
  if (messages.value.length > MAX_CHAT_MESSAGES) {
    messages.value.splice(0, messages.value.length - MAX_CHAT_MESSAGES);
  }
  nextTick(() => {
    if (chatList.value) chatList.value.scrollTop = chatList.value.scrollHeight;
  });
  if (chatOpen.value) unreadChat.value = 0;
}

async function toggleMic() {
  if (!room) return;
  micOn.value = !micOn.value;
  try {
    // Em waiting room o track ainda não foi publicado — opera no preview
    // (track standalone). Após admit, o caminho normal de setMicrophoneEnabled
    // já cobre.
    if (admitted.value) {
      await room.localParticipant.setMicrophoneEnabled(micOn.value);
    } else if (previewAudioTrack) {
      if (micOn.value) await previewAudioTrack.unmute();
      else await previewAudioTrack.mute();
    }
  } catch (e) {
    console.warn('[telemed] toggleMic falhou:', e);
  }
}

// 2026-05-22 — Lock de reentrância (`camToggleInFlight` declarado no topo
// do script). setCameraEnabled é async (~300-800ms no caminho LiveKit,
// mais o reapplyBlurIfActive que carrega WASM). Sem lock, clicar rápido
// OFF/ON/OFF/ON criava race: track antigo era stopado enquanto
// applyBlurState chamava setProcessor nele → BlurProcessor (WASM
// MediaPipe) travava a thread principal e o vídeo ficava preto pros dois
// lados sem recovery. Relato 2026-05-22 "câmera travou e ficou preta".
async function toggleCam() {
  if (!room) return;
  if (camToggleInFlight) return; // ignora clicks até o anterior completar
  camToggleInFlight = true;
  const target = !camOn.value;
  camOn.value = target;
  try {
    if (admitted.value) {
      await room.localParticipant.setCameraEnabled(target);
      // Race guard: usuário pode ter clicado de novo no meio. Se camOn
      // mudou, NÃO aplica blur — o próximo toggle vai cuidar disso.
      if (target && camOn.value === true) await reapplyBlurIfActive();
    } else if (previewVideoTrack) {
      if (target) await previewVideoTrack.unmute();
      else await previewVideoTrack.mute();
    }
  } catch (e) {
    console.warn('[telemed] toggleCam falhou:', e);
  } finally {
    camToggleInFlight = false;
  }
}

function onActiveSpeakers(speakers) {
  const speakingIds = new Set();
  let localIsSpeaking = false;
  speakers.forEach(p => {
    if (!p) return;
    if (p === room?.localParticipant) localIsSpeaking = true;
    else speakingIds.add(p.identity);
  });
  localSpeaking.value = localIsSpeaking;
  // Atualiza tiles em batch — re-cria array pra trigger reactivity.
  remoteParticipants.value = remoteParticipants.value.map(p => ({
    ...p,
    speaking: speakingIds.has(p.id),
  }));
  // Compat: mantém activeSpeaker pra outros consumidores que possam
  // depender (chip antigo removido do template, mas variável fica
  // exportada por hábito; remover quando confirmar zero uso).
  const remote = speakers.find(p => p && p !== room?.localParticipant);
  activeSpeaker.value = remote
    ? remote.name || remote.identity || 'Participante'
    : '';
}

async function switchCamera() {
  if (!room || videoDevices.value.length < 2) return;
  const currentId = room.localParticipant
    .getTrackPublication?.(Track.Source.Camera)
    ?.track?.mediaStreamTrack?.getSettings?.()?.deviceId;
  const next =
    videoDevices.value.find(d => d.deviceId !== currentId) ||
    videoDevices.value[0];
  try {
    await room.switchActiveDevice('videoinput', next.deviceId);
    // Atualiza facingMode pra desativar o espelhamento se trocou pra traseira.
    // `getSettings().facingMode` retorna 'user'/'environment' (mobile) ou
    // undefined (desktop, onde mantemos default 'user' = espelhado).
    const fm = room.localParticipant
      .getTrackPublication?.(Track.Source.Camera)
      ?.track?.mediaStreamTrack?.getSettings?.()?.facingMode;
    if (fm) cameraFacing.value = fm;
    // switchActiveDevice troca o track interno — reaplica o processor.
    await reapplyBlurIfActive();
  } catch (e) {
    console.warn('[telemed] switchCamera falhou:', e);
  }
}

async function toggleScreen() {
  if (!room) return;
  try {
    await room.localParticipant.setScreenShareEnabled(!screenOn.value);
    screenOn.value = !screenOn.value;
  } catch (e) {
    console.warn('[telemed] toggleScreen falhou:', e);
  }
}

async function refreshStats() {
  if (!room) return;
  try {
    for (const participant of room.remoteParticipants.values()) {
      for (const pub of participant.trackPublications.values()) {
        if (pub.kind !== Track.Kind.Video || !pub.track) continue;
        const report = await pub.track.getRTCStatsReport?.();
        if (!report) continue;
        let frameWidth = 0;
        let frameHeight = 0;
        let fps = 0;
        let bytesReceived = 0;
        let codec = '';
        report.forEach(s => {
          if (s.type === 'inbound-rtp' && s.kind === 'video') {
            frameWidth = s.frameWidth || frameWidth;
            frameHeight = s.frameHeight || frameHeight;
            fps = Math.round(s.framesPerSecond || 0);
            bytesReceived = s.bytesReceived || 0;
          }
          if (s.type === 'codec' && s.mimeType) {
            codec = s.mimeType.replace('video/', '');
          }
        });
        const now = performance.now();
        let kbps = 0;
        if (lastBytesReceived && lastStatsAt) {
          const deltaSec = (now - lastStatsAt) / 1000;
          kbps = Math.round(
            ((bytesReceived - lastBytesReceived) * 8) / 1000 / deltaSec
          );
        }
        lastBytesReceived = bytesReceived;
        lastStatsAt = now;
        stats.value = {
          width: frameWidth,
          height: frameHeight,
          fps,
          kbps,
          codec,
          layer: layerForResolution(frameHeight),
        };
        return;
      }
    }
  } catch (e) {
    /* não-fatal */
  }
}

// Devolve só o label de resolução. UI usa um ponto colorido (CSS) em vez de
// emojis pra evitar variação tipográfica entre OSes (no Windows o emoji
// 🟢/🟡/🟠/🔴 fica preto-e-branco em fontes antigas).
function layerForResolution(h) {
  if (h >= 1080) return '1080p';
  if (h >= 720) return '720p';
  if (h >= 360) return '360p';
  if (h > 0) return '180p';
  return '—';
}

// Cor associada à layer (verde alto / amarelo médio / laranja / vermelho).
// Casa com o que o emoji indicava antes — agora aplicado via inline style
// num <span> CSS dot.
function layerColor(h) {
  if (h >= 1080) return '#22c55e';
  if (h >= 720) return '#eab308';
  if (h >= 360) return '#f97316';
  if (h > 0) return '#ef4444';
  return '#475569';
}

// ─── Preflight (lobby Meet-style) ─────────────────────────────────────
// Acontece ANTES do `connect()`. Cria tracks de preview localmente (sem
// publicar) pra usuário ver câmera/microfone funcionando e escolher
// dispositivo. Botão "Entrar agora" libera o caminho normal (connect →
// publishLocalTracks com o deviceId selecionado).

async function setupPreflight() {
  state.value = 'preflight';
  if (!checkSecureContext()) return;
  // Cria preview ANTES de enumerar — `enumerateDevices()` só retorna labels
  // depois que getUserMedia foi concedido. Sem isso, usuário veria "Câmera 1
  // / Câmera 2" sem nome real.
  await startPreviewTracks();
  await refreshDeviceList();
}

async function refreshDeviceList() {
  try {
    const devices = await Room.getLocalDevices();
    videoInputs.value = devices.filter(d => d.kind === 'videoinput');
    audioInputs.value = devices.filter(d => d.kind === 'audioinput');
    audioOutputs.value = devices.filter(d => d.kind === 'audiooutput');
    videoDevices.value = videoInputs.value;
    hasMultipleCameras.value = videoInputs.value.length > 1;
    if (!selectedVideoDevice.value && videoInputs.value[0]) {
      selectedVideoDevice.value = videoInputs.value[0].deviceId;
    }
    if (!selectedAudioDevice.value && audioInputs.value[0]) {
      selectedAudioDevice.value = audioInputs.value[0].deviceId;
    }
    if (!selectedAudioOutputDevice.value && audioOutputs.value[0]) {
      // 'default' costuma ser o speaker do SO — bom default que respeita
      // a escolha do usuário no nível do OS.
      const def = audioOutputs.value.find(d => d.deviceId === 'default');
      selectedAudioOutputDevice.value =
        def?.deviceId || audioOutputs.value[0].deviceId;
    }
  } catch (_) {
    /* não-fatal */
  }
}

// (Re)cria os preview tracks respeitando micOn/camOn e o device selecionado.
// Chamada inicialmente em setupPreflight() e quando usuário troca de device.
async function startPreviewTracks() {
  // Stopa anteriores antes — evita duas streams concorrendo pela mesma câmera.
  if (previewVideoTrack) {
    try {
      previewVideoTrack.stop();
    } catch (_) {}
    previewVideoTrack = null;
  }
  if (previewAudioTrack) {
    try {
      previewAudioTrack.stop();
    } catch (_) {}
    previewAudioTrack = null;
  }

  if (camOn.value) {
    try {
      previewVideoTrack = await createLocalVideoTrack({
        // h720 (1280×720) por consistência com o capture da sala —
        // ver comentário no `new Room(...)`. Pedir 1080p aqui também
        // causa o mesmo "crop apertado" em webcams nativas 720p.
        resolution: VideoPresets.h720.resolution,
        deviceId: selectedVideoDevice.value || undefined,
      });
      // Captura resolução real (LiveKit pode degradar de 1080 → 720 se a
      // webcam não suportar) e facingMode.
      const settings =
        previewVideoTrack.mediaStreamTrack?.getSettings?.() || {};
      previewResolution.value = {
        width: settings.width || 0,
        height: settings.height || 0,
      };
      if (settings.facingMode) cameraFacing.value = settings.facingMode;
      nextTick(() => {
        const el = preflightVideo.value || localVideo.value;
        if (el && previewVideoTrack) {
          previewVideoTrack.attach(el);
          el.play?.().catch(() => {});
        }
      });
      // Track novo (troca de device ou primeira inicialização) — reaplica
      // o blur caso o usuário tenha ativado no preflight.
      await reapplyBlurIfActive();
    } catch (err) {
      console.warn('[telemed] preview camera falhou:', err);
      camOn.value = false;
      mediaError.value = mapMediaError(err);
    }
  } else {
    previewResolution.value = { width: 0, height: 0 };
  }

  if (micOn.value) {
    try {
      previewAudioTrack = await createLocalAudioTrack({
        echoCancellation: { ideal: true },
        noiseSuppression: { ideal: true },
        autoGainControl: { ideal: true },
        deviceId: selectedAudioDevice.value || undefined,
      });
    } catch (err) {
      console.warn('[telemed] preview mic falhou:', err);
      micOn.value = false;
      if (!mediaError.value) mediaError.value = mapMediaError(err);
    }
  }
}

async function changeVideoDevice(deviceId) {
  selectedVideoDevice.value = deviceId;
  await startPreviewTracks();
}

async function changeAudioDevice(deviceId) {
  selectedAudioDevice.value = deviceId;
  await startPreviewTracks();
}

// Toggle no preflight stopa/reabre a stream pra de fato liberar o LED da
// câmera enquanto o usuário decide. No connected, mute/unmute na track
// publicada (lógica existente em toggleMic/toggleCam).
async function togglePreflightCam() {
  camOn.value = !camOn.value;
  await startPreviewTracks();
}

async function togglePreflightMic() {
  micOn.value = !micOn.value;
  await startPreviewTracks();
}

// Usuário clicou "Entrar agora" — sai do preflight e conecta na sala.
// Não para os preview tracks aqui: `connect()` chama `publishLocalTracks`
// que recria via setXxxEnabled (caminho que sempre funcionou pra render do
// outro lado). Os preview tracks são stopados em `disconnect()`.
async function enterRoom() {
  if (mediaError.value && mediaError.value.type === 'insecure') return;
  state.value = 'connecting';
  // Para os preview tracks pra liberar a câmera/mic — connect() vai
  // recriar via setMicrophoneEnabled/setCameraEnabled com os devices
  // selecionados.
  if (previewVideoTrack) {
    try {
      previewVideoTrack.stop();
    } catch (_) {}
    previewVideoTrack = null;
  }
  if (previewAudioTrack) {
    try {
      previewAudioTrack.stop();
    } catch (_) {}
    previewAudioTrack = null;
  }
  await connect();
}

function disconnect() {
  if (statsInterval) {
    clearInterval(statsInterval);
    statsInterval = null;
  }
  // 2026-05-22 — Cancela timer do tooltip de gravação pra evitar callback
  // disparar depois do componente ser desmontado (Vue warn + leak).
  if (recordHintTimer) {
    clearTimeout(recordHintTimer);
    recordHintTimer = null;
  }
  recordHintVisible.value = false;
  stopDurationTimer();
  // Limpa audio elements anexados ao body — sem isso ficam órfãos tocando
  // após sair da sala (raro mas observado em refresh rápido).
  videoBindings.forEach(entry => {
    entry.audioElements?.forEach(el => {
      try {
        audioElementsForSink.delete(el);
        el.remove();
      } catch (_) {}
    });
  });
  videoBindings.clear();
  audioElementsForSink.clear();
  remoteParticipants.value = [];
  // Remove o listener de hot-plug pra evitar leak entre sessões.
  if (
    typeof navigator !== 'undefined' &&
    navigator.mediaDevices?.removeEventListener
  ) {
    try {
      navigator.mediaDevices.removeEventListener(
        'devicechange',
        refreshDevices
      );
    } catch (_) {}
  }
  // Para preview tracks (libera câmera/mic do SO) se paciente saiu sem
  // ser admitido. Quando admitido, esses tracks viraram tracks publicados
  // e o room.disconnect cuida.
  if (previewVideoTrack) {
    try {
      previewVideoTrack.stop();
    } catch (_) {}
    previewVideoTrack = null;
  }
  if (previewAudioTrack) {
    try {
      previewAudioTrack.stop();
    } catch (_) {}
    previewAudioTrack = null;
  }
  if (room) {
    // Remove os listeners ANTES do disconnect() — sem isso, o Disconnected
    // emitido pelo próprio room.disconnect() reentrava no handler com
    // `room` ainda truthy e estado já 'disconnected', causando emitLeave
    // duplicado em alguns navegadores.
    if (roomListeners.length) {
      roomListeners.forEach(([event, handler]) => {
        try {
          room.off(event, handler);
        } catch (_) {}
      });
      roomListeners = [];
    }
    try {
      room.disconnect();
    } catch (_) {}
    room = null;
  }
}

function leave() {
  // Doutor saindo = chamada encerrada pra todos. Broadcast SÍNCRONO via
  // data channel ANTES do disconnect() — paciente precisa receber a
  // mensagem pra navegar pra home (sem isso, ele só nota porque o
  // ParticipantDisconnected dele dispara, mas aí a saída fica sem UX
  // clara: o vídeo congela e o tile desaparece silenciosamente).
  //
  // `publishData` é reliable, mas `room.disconnect()` corta o socket logo
  // depois — então usamos a Promise pra "tentar mandar antes de cortar".
  // Se falhar (rede ruim), o paciente cai no fallback do ParticipantDis-
  // connected: vê tile vazio e fica num estado meio limbo. Aceitável pro
  // MVP — quando a rede está tão ruim, o paciente provavelmente já caiu.
  if (isDoctor.value && room) {
    try {
      const payload = encoder.encode(JSON.stringify({ type: 'call_ended' }));
      // Não await — se demorar, paciente recebe via fallback (Disconnected).
      // Doutor não pode esperar a propagação antes de sair.
      room.localParticipant
        .publishData(payload, { reliable: true })
        .catch(() => {});
    } catch (_) {
      /* não-fatal — disconnect prossegue */
    }
  }
  // 2026-05-22 — Se doutor está saindo COM gravação ativa, dispara stop
  // ANTES do disconnect. Fire-and-forget: o backend tem failsafe (left!
  // do doutor já chama stop_recording_if_active), mas mandar daqui também
  // garante que o pipeline de transcrição comece antes — o webhook do
  // Egress chega no Rails em paralelo com o emitSessionLeft.
  if (
    isDoctor.value &&
    recordingActive.value &&
    typeof props.recordStopper === 'function'
  ) {
    try {
      props.recordStopper().catch(() => {});
    } catch (_) {
      /* não-fatal — left! do backend para a gravação como fallback */
    }
    recordingActive.value = false;
  }
  emitSessionLeft();
  disconnect();
  emitLeaveOnce();
}

// ─── Helpers de UI ────────────────────────────────────────────────────

// Retorna a primeira letra do nome (maiúscula). "João Silva" → "J".
// Vazio/null → "?". Usado nos avatars (remote tile + local PIP).
function initial(name) {
  if (!name) return '?';
  const trimmed = String(name).trim();
  if (!trimmed) return '?';
  return trimmed.charAt(0).toUpperCase();
}

// Cor estável a partir do nome — mesma identity sempre tem mesma cor de
// avatar (igual Meet). Distribuição em 6 cores agradáveis.
function avatarColor(name) {
  const palette = [
    '#0ea5e9',
    '#8b5cf6',
    '#ec4899',
    '#f59e0b',
    '#10b981',
    '#ef4444',
  ];
  if (!name) return palette[0];
  // Soma simples dos charCodes — não precisa ser hash criptográfico,
  // só estável e bem distribuído nas 6 cores. Evita bitwise (no-bitwise).
  let hash = 0;
  for (let i = 0; i < name.length; i += 1) {
    hash = (hash + name.charCodeAt(i)) % 1000003;
  }
  return palette[hash % palette.length];
}

// HTTPS ou localhost. getUserMedia exige secure context — em http://hostname:port
// (não-localhost), o browser retorna `undefined` em mediaDevices.
function checkSecureContext() {
  if (typeof window === 'undefined') return true;
  if (window.isSecureContext) return true;
  // Diagnóstico explícito pra o caso clássico: HTTP em hostname customizado.
  mediaError.value = {
    type: 'insecure',
    title: 'Conexão não segura',
    message:
      'Câmera e microfone exigem HTTPS. Acesse a sala por uma URL https:// ' +
      'ou localhost. Em desenvolvimento, libere via ' +
      'chrome://flags/#unsafely-treat-insecure-origin-as-secure.',
  };
  return false;
}

// Converte exceções do getUserMedia em mensagem amigável.
function mapMediaError(err) {
  const name = err?.name || '';
  if (name === 'NotAllowedError' || name === 'PermissionDeniedError') {
    return {
      type: 'denied',
      title: 'Permissão negada',
      message:
        'Você bloqueou o acesso à câmera/microfone. Clique no ícone de ' +
        'cadeado/câmera na barra do navegador e libere o acesso pra esta página.',
    };
  }
  if (name === 'NotFoundError' || name === 'DevicesNotFoundError') {
    return {
      type: 'no_device',
      title: 'Câmera ou microfone não encontrado',
      message:
        'Verifique se sua câmera e microfone estão conectados e reconhecidos ' +
        'pelo sistema operacional.',
    };
  }
  if (name === 'NotReadableError' || name === 'TrackStartError') {
    return {
      type: 'in_use',
      title: 'Dispositivo em uso',
      message:
        'Sua câmera ou microfone está sendo usado por outro programa ' +
        '(ex: outra aba ou um aplicativo de chamadas). Feche os outros ' +
        'aplicativos e tente novamente.',
    };
  }
  return {
    type: 'generic',
    title: 'Não foi possível acessar a câmera',
    message: err?.message || 'Tente recarregar a página.',
  };
}

// Tenta reaver câmera/mic após o usuário corrigir o problema (liberou
// permissão, fechou app concorrente, etc).
async function retryMedia() {
  mediaError.value = null;
  if (!checkSecureContext()) return;
  if (admitted.value) {
    await publishLocalTracks();
  } else {
    await createPreviewTracks();
  }
}

// Guard de idempotência — ver hasEmittedLeave.
function emitLeaveOnce() {
  if (hasEmittedLeave) return;
  hasEmittedLeave = true;
  emit('leave');
}

// Idempotência da automação de status. O wrapper passa pra useTelemedicineSession
// que tem seu próprio guard, mas duplicamos aqui pra evitar nem fazer o emit
// (poupa um round-trip Vue + log noise).
function emitSessionJoined() {
  if (hasEmittedSessionJoined) return;
  hasEmittedSessionJoined = true;
  // Sprint L — propaga consent. Em wrappers do doutor (que não mostram
  // checkbox), `recordingConsent` permanece false e o backend trata como
  // "sem novo consent" (não invalida consent antigo do paciente).
  emit('sessionEvent', { kind: 'joined', consented: recordingConsent.value });
}

function emitSessionLeft() {
  if (hasEmittedSessionLeft) return;
  hasEmittedSessionLeft = true;
  emit('sessionEvent', { kind: 'left' });
}
</script>

<!-- eslint-disable vue/no-bare-strings-in-template -->
<!-- Strings em PT-BR hardcoded propositais nesta sala de telemed (MVP
     Sprint K). Pendente i18n quando o portal for traduzido. -->
<template>
  <div class="pp-telemed-room">
    <!-- Preflight (pré-consulta): preview de câmera à esquerda, painel de
         configuração à direita (3 selects de dispositivo + card de segurança
         + CTA primária). Mobile empilha vertical. -->
    <div v-if="state === 'preflight'" class="pp-telemed-preflight">
      <div class="pp-telemed-preflight__shell">
        <!-- Coluna esquerda: preview do vídeo + overlay glassmorphism com
             toggles de mic/cam. -->
        <section class="pp-telemed-preflight__preview-col">
          <div
            class="pp-telemed-preflight__preview"
            :class="{ 'pp-telemed-preflight__preview--off': !camOn }"
          >
            <video
              ref="preflightVideo"
              autoplay
              muted
              playsinline
              class="pp-telemed-preflight__video"
              :class="{
                'pp-telemed-preflight__video--mirror':
                  cameraFacing !== 'environment',
                'pp-telemed-preflight__video--hidden': !camOn,
              }"
            />
            <div v-if="!camOn" class="pp-telemed-preflight__camoff">
              <div
                class="pp-telemed-room__avatar"
                :style="{ background: avatarColor(localName || headerTitle) }"
              >
                {{ initial(localName || headerTitle) }}
              </div>
              <p>Câmera desligada</p>
            </div>
            <div
              v-if="camOn && previewResolution.height > 0"
              class="pp-telemed-preflight__quality"
            >
              {{ layerForResolution(previewResolution.height) }}
            </div>

            <div class="pp-telemed-preflight__overlay-controls">
              <button
                class="pp-telemed-preflight__ctrl"
                :class="{ 'pp-telemed-preflight__ctrl--off': !micOn }"
                :title="micOn ? 'Silenciar' : 'Ativar microfone'"
                type="button"
                @click="togglePreflightMic"
              >
                <IconMic v-if="micOn" :size="20" />
                <IconMicOff v-else :size="20" />
              </button>
              <button
                class="pp-telemed-preflight__ctrl"
                :class="{ 'pp-telemed-preflight__ctrl--off': !camOn }"
                :title="camOn ? 'Desligar câmera' : 'Ligar câmera'"
                type="button"
                @click="togglePreflightCam"
              >
                <IconVideo v-if="camOn" :size="20" />
                <IconVideoOff v-else :size="20" />
              </button>
            </div>
          </div>
        </section>

        <!-- Coluna direita: painel de configuração. -->
        <section class="pp-telemed-preflight__panel">
          <header class="pp-telemed-preflight__header">
            <h1 class="pp-telemed-preflight__title">Pré-consulta</h1>
            <p class="pp-telemed-preflight__subtitle">
              Ajuste sua câmera e microfone antes de entrar na sala de espera.
            </p>
            <p v-if="roomCode" class="pp-telemed-preflight__code">
              Código da sala: <strong>{{ roomCode }}</strong>
            </p>
          </header>

          <div
            v-if="mediaError"
            class="pp-telemed-room__media-error pp-telemed-preflight__error"
            role="alert"
          >
            <div class="pp-telemed-room__media-error-icon">
              <IconVideoOff :size="20" />
            </div>
            <div class="pp-telemed-room__media-error-text">
              <strong>{{ mediaError.title }}</strong>
              <p>{{ mediaError.message }}</p>
            </div>
            <button
              class="pp-telemed-room__media-error-btn"
              type="button"
              @click="retryMedia"
            >
              Tentar novamente
            </button>
          </div>

          <div class="pp-telemed-preflight__fields">
            <TelemedDeviceSelect
              label="Câmera"
              :model-value="selectedVideoDevice"
              :options="videoInputs"
              empty-text="Nenhuma câmera encontrada"
              fallback-label="Câmera padrão"
              @update:model-value="changeVideoDevice"
            >
              <template #icon>
                <IconVideo :size="14" />
              </template>
            </TelemedDeviceSelect>

            <TelemedDeviceSelect
              label="Microfone"
              :model-value="selectedAudioDevice"
              :options="audioInputs"
              empty-text="Nenhum microfone encontrado"
              fallback-label="Microfone padrão"
              @update:model-value="changeAudioDevice"
            >
              <template #icon>
                <IconMic :size="14" />
              </template>
            </TelemedDeviceSelect>

            <TelemedDeviceSelect
              label="Saída de áudio"
              :model-value="selectedAudioOutputDevice"
              :options="audioOutputs"
              :disabled="!supportsAudioOutputSelection"
              :empty-text="
                supportsAudioOutputSelection
                  ? 'Nenhuma saída encontrada'
                  : 'Seu navegador usa a saída padrão do sistema'
              "
              fallback-label="Saída padrão"
              @update:model-value="changeAudioOutputDevice"
            >
              <template #icon>
                <svg
                  width="14"
                  height="14"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                  <path d="M15.54 8.46a5 5 0 010 7.07" />
                  <path d="M19.07 4.93a10 10 0 010 14.14" />
                </svg>
              </template>
            </TelemedDeviceSelect>
          </div>

          <!-- Card de Segurança / Consent LGPD. Substitui o checkbox solto
               do design antigo por um agrupamento visualmente coeso. -->
          <div class="pp-telemed-preflight__security">
            <h3 class="pp-telemed-preflight__security-title">
              <IconShield :size="16" />
              Configurações de segurança
            </h3>
            <label class="pp-telemed-preflight__consent">
              <input
                v-model="recordingConsent"
                type="checkbox"
                class="pp-telemed-preflight__consent-checkbox"
              />
              <span class="pp-telemed-preflight__consent-text">
                Li e aceito os
                <!-- eslint-disable-next-line vue/max-attributes-per-line -->
                <a href="#" @click.prevent="showConsentTerms = true"
                  >termos de privacidade e proteção de dados (LGPD)</a
                >. Compreendo que o áudio desta consulta será gravado conforme a
                Resolução CFM 2.314/2022.
              </span>
            </label>
          </div>

          <div class="pp-telemed-preflight__actions">
            <button
              class="pp-telemed-preflight__enter"
              type="button"
              :disabled="
                (mediaError && mediaError.type === 'insecure') ||
                !recordingConsent
              "
              @click="enterRoom"
            >
              <span>{{ enterCtaLabel }}</span>
              <svg
                width="20"
                height="20"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <line x1="5" y1="12" x2="19" y2="12" />
                <polyline points="12 5 19 12 12 19" />
              </svg>
            </button>
            <button
              class="pp-telemed-preflight__cancel"
              type="button"
              @click="leave"
            >
              Cancelar
            </button>
          </div>
        </section>
      </div>
    </div>

    <!-- Sprint L — Modal com texto completo do termo de consent -->
    <div
      v-if="showConsentTerms"
      class="pp-telemed-consent-modal"
      role="dialog"
      aria-modal="true"
      @click.self="showConsentTerms = false"
    >
      <div class="pp-telemed-consent-modal__box">
        <h3>Termo de Consentimento — Gravação de Áudio da Teleconsulta</h3>
        <div class="pp-telemed-consent-modal__body">
          <p>
            <strong>Esta teleconsulta gravará apenas o áudio</strong> da
            conversa entre você e o(a) profissional. Não será gravada imagem de
            vídeo.
          </p>
          <p>
            <strong>1. Finalidade:</strong> O áudio será utilizado para
            elaboração da evolução clínica (prontuário escrito) com apoio de
            inteligência artificial, e como registro auditável conforme
            Resolução CFM nº 2.314/2022.
          </p>
          <p>
            <strong>2. Base legal:</strong> Tratamento de dados pessoais
            sensíveis de saúde com seu consentimento expresso (LGPD nº
            13.709/2018, art. 11, I).
          </p>
          <p>
            <strong>3. Retenção do áudio:</strong> O arquivo de áudio fica
            disponível por tempo limitado conforme política da clínica
            (tipicamente as 15 consultas mais recentes). Após esse período, o
            áudio é excluído permanentemente.
          </p>
          <p>
            <strong>4. Retenção da evolução clínica:</strong> A evolução escrita
            gerada a partir do áudio (prontuário) é preservada por
            <strong>20 anos</strong>, conforme exigência do CFM, mesmo após o
            áudio ser excluído.
          </p>
          <p>
            <strong>5. Seus direitos:</strong> Você pode solicitar a exclusão
            antecipada do áudio a qualquer momento, sem prejuízo do atendimento.
            Atos clínicos já registrados na evolução não são afetados pela
            revogação.
          </p>
          <p>
            Ao marcar a caixa de seleção e clicar em "Entrar agora", você
            declara estar ciente destas condições e autoriza a gravação do
            áudio.
          </p>
        </div>
        <button
          class="pp-telemed-preflight__enter"
          type="button"
          @click="showConsentTerms = false"
        >
          Fechar
        </button>
      </div>
    </div>

    <div v-else-if="state === 'connecting'" class="pp-telemed-room__overlay">
      <div class="pp-telemed-room__spinner" />
      <p class="pp-telemed-room__status">Conectando à sala…</p>
    </div>

    <div v-else-if="state === 'error'" class="pp-telemed-room__overlay">
      <p class="pp-telemed-room__status pp-telemed-room__status--error">
        {{ errorMessage }}
      </p>
      <button class="pp-telemed-room__btn" @click="$emit('leave')">
        Voltar
      </button>
    </div>

    <template
      v-else-if="
        state === 'connected' ||
        state === 'disconnected' ||
        state === 'reconnecting'
      "
    >
      <!-- Body full-bleed: stage de vídeo preto ocupando 100% + chat sidebar
           opcional à direita. Header e toolbar agora flutuam SOBRE o vídeo. -->
      <div class="pp-telemed-room__body">
        <main class="pp-telemed-room__main">
          <!-- Header overlay (gradient escuro topo). Logo Klivy + nome do outro
               participante + badge "Em andamento - MM:SS". Direita: status da
               conexão. Volta no canto esquerdo (botão circular sutil). -->
          <header class="pp-telemed-room__header">
            <div class="pp-telemed-room__header-left">
              <button
                class="pp-telemed-room__back"
                aria-label="Voltar"
                @click="leave"
              >
                <IconChevronLeft :size="18" />
              </button>
              <span class="pp-telemed-room__brand">Klivy</span>
              <span class="pp-telemed-room__brand-sep" />
              <span class="pp-telemed-room__participant">{{
                headerTitle
              }}</span>
              <span
                class="pp-telemed-room__status-pill"
                :class="{
                  'pp-telemed-room__status-pill--warn':
                    state === 'reconnecting',
                }"
              >
                <span class="pp-telemed-room__status-dot-pulse" />
                <span v-if="state === 'reconnecting'">Reconectando…</span>
                <span v-else>Em andamento · {{ liveDurationLabel }}</span>
              </span>
            </div>
            <div class="pp-telemed-room__header-right">
              <span
                v-if="roomCode"
                class="pp-telemed-room__code"
                :title="`Código da sala: ${roomCode}`"
              >
                {{ roomCode }}
              </span>
              <!-- Pílula de qualidade da conexão. Estado e label reagem
                   ao `ConnectionQualityChanged` do LiveKit. As 3 barrinhas
                   animam em loop discreto pra dar a sensação de
                   "monitoramento ativo" (request UX) — em estado warn/bad
                   o loop fica mais agitado e a cor muda. -->
              <span
                class="pp-telemed-room__conn"
                :class="{
                  'pp-telemed-room__conn--warn': connectionState === 'warn',
                  'pp-telemed-room__conn--bad': connectionState === 'bad',
                }"
                :title="connectionLabel"
              >
                <span class="pp-telemed-room__conn-bars" aria-hidden="true">
                  <span class="pp-telemed-room__conn-bar" />
                  <span class="pp-telemed-room__conn-bar" />
                  <span class="pp-telemed-room__conn-bar" />
                </span>
                {{ connectionLabel }}
              </span>
              <!-- 2026-05-22 — Badge "REC + IA" no header. Aparece pros DOIS
                   participantes (doutor e paciente) quando a gravação está
                   ativa. É a confirmação visível pedida pelo doutor: se ele
                   vê o badge piscando aqui, a gravação está rolando de fato
                   no LiveKit Egress + a transcrição/evolução vão rodar no
                   pipeline pós-encerramento. -->
              <span
                v-if="recordingActive"
                class="pp-telemed-room__rec-badge"
                role="status"
                aria-live="polite"
                title="Esta consulta está sendo gravada e será transcrita pela IA"
              >
                <span class="pp-telemed-room__rec-badge-dot" aria-hidden="true" />
                <span class="pp-telemed-room__rec-badge-text">REC</span>
                <span class="pp-telemed-room__rec-badge-ai">IA</span>
              </span>
              <span v-if="devMode" class="pp-telemed-room__dev">DEV</span>
            </div>
          </header>

          <!-- Banner de erro de mídia (HTTPS, permissão negada, sem device).
               Aparece ACIMA do stage pra não confundir com waiting room. -->
          <div
            v-if="mediaError"
            class="pp-telemed-room__media-error"
            role="alert"
          >
            <div class="pp-telemed-room__media-error-icon">
              <IconVideoOff :size="24" />
            </div>
            <div class="pp-telemed-room__media-error-text">
              <strong>{{ mediaError.title }}</strong>
              <p>{{ mediaError.message }}</p>
            </div>
            <button
              class="pp-telemed-room__media-error-btn"
              type="button"
              @click="retryMedia"
            >
              Tentar novamente
            </button>
          </div>

          <div
            class="pp-telemed-room__stage"
            :class="{
              'pp-telemed-room__stage--pinned-self': isLocalPinned,
              'pp-telemed-room__stage--pinned': hasPin,
            }"
          >
            <!-- Waiting: sem participantes remotos. -->
            <div
              v-if="remoteParticipants.length === 0"
              class="pp-telemed-room__waiting"
            >
              <div class="pp-telemed-room__waiting-icon">
                <IconClock :size="40" />
              </div>
              <p>Aguardando o outro participante entrar na sala…</p>
            </div>

            <!-- Tiles dos participantes remotos. Cada tile aparece QUANDO
                 ParticipantConnected dispara — independente de tracks. Sem
                 vídeo → avatar com inicial. Speaking → border azul + glow. -->
            <div
              v-else
              class="pp-telemed-room__tiles"
              :data-count="remoteParticipants.length"
            >
              <div
                v-for="p in remoteParticipants"
                :key="p.id"
                class="pp-telemed-room__tile"
                :class="{
                  'pp-telemed-room__tile--speaking': p.speaking,
                  'pp-telemed-room__tile--pinned': isParticipantPinned(p.id),
                  'pp-telemed-room__tile--screen': p.isScreenShare,
                }"
              >
                <video
                  :ref="el => bindRemoteVideo(p.id, el)"
                  autoplay
                  playsinline
                  class="pp-telemed-room__tile-video"
                  :class="{
                    'pp-telemed-room__tile-video--hidden': !p.hasVideo,
                    'pp-telemed-room__tile-video--contain': p.isScreenShare,
                  }"
                />
                <div
                  v-if="!p.hasVideo"
                  class="pp-telemed-room__avatar"
                  :style="{ background: avatarColor(p.name) }"
                >
                  {{ initial(p.name) }}
                </div>
                <!-- Ícone de mic-off CENTRALIZADO sobre o tile. Padrão Meet:
                     além da pílula no nome (sutil), tem um indicador visual
                     grande que o usuário vê de relance. Não aparece em
                     screen share (tile não tem mic associado). -->
                <div
                  v-if="!p.isScreenShare && p.micMuted"
                  class="pp-telemed-room__tile-mute-overlay"
                  aria-hidden="true"
                >
                  <IconMicOff :size="22" />
                </div>
                <div class="pp-telemed-room__tile-name">
                  <IconMicOff
                    v-if="!p.isScreenShare && p.micMuted"
                    :size="12"
                    class="pp-telemed-room__tile-mic-off"
                  />
                  <span>{{ p.name }}</span>
                </div>
                <!-- Pin trigger no canto superior direito — aparece no hover
                     do tile ou se já está fixado. O menu propriamente dito é
                     renderizado via Teleport pro body (final do template). -->
                <button
                  type="button"
                  class="pp-telemed-room__pin-btn"
                  :class="{
                    'pp-telemed-room__pin-btn--active': isParticipantPinned(
                      p.id
                    ),
                  }"
                  :title="
                    isParticipantPinned(p.id)
                      ? 'Fixado em destaque'
                      : 'Fixar em destaque'
                  "
                  :aria-expanded="pinMenuOpenFor === p.id"
                  @click.stop="togglePinMenu(p.id, $event)"
                >
                  <svg
                    width="22"
                    height="22"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <path d="M12 17v5" />
                    <path
                      d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"
                    />
                  </svg>
                </button>
                <!-- Badge "pinned" no canto superior esquerdo. -->
                <span
                  v-if="isParticipantPinned(p.id)"
                  class="pp-telemed-room__pin-badge"
                  :title="
                    pinIsGlobal ? 'Fixado pra todos' : 'Fixado só pra você'
                  "
                >
                  <svg
                    width="12"
                    height="12"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2.4"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    aria-hidden="true"
                  >
                    <path d="M12 17v5" />
                    <path
                      d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"
                    />
                  </svg>
                  <span>{{ pinIsGlobal ? 'Fixado · todos' : 'Fixado' }}</span>
                </span>
              </div>
            </div>

            <!-- Overlay "Aguardando admissão" — paciente em waiting room. -->
            <div v-if="isWaiting" class="pp-telemed-room__admit-overlay">
              <div class="pp-telemed-room__admit-card">
                <div class="pp-telemed-room__admit-spinner" />
                <h2>Aguardando o profissional aceitar…</h2>
                <p>
                  Você está na sala de espera. Você pode ajustar a câmera e o
                  microfone abaixo — quando o profissional permitir, a consulta
                  começa automaticamente.
                </p>
              </div>
            </div>

            <!-- Cards de admit (doutor) — empilhados no canto inferior
                 direito, acima do PIP. Um card por paciente pendente.
                 Substituiu o banner topo-central da versão anterior. -->
            <div
              v-if="isDoctor && pendingPatients.size > 0"
              class="pp-telemed-room__admit-stack"
              role="region"
              aria-label="Pedidos de entrada"
            >
              <div
                v-for="[identity, info] in pendingPatients"
                :key="identity"
                class="pp-telemed-room__admit-card2"
              >
                <header class="pp-telemed-room__admit-card2-head">
                  <span class="pp-telemed-room__admit-card2-tag">
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="currentColor"
                      aria-hidden="true"
                    >
                      <path
                        d="M12 22a2 2 0 0 0 2-2h-4a2 2 0 0 0 2 2zm6-6V11c0-3.07-1.64-5.64-4.5-6.32V4a1.5 1.5 0 0 0-3 0v.68C7.63 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z"
                      />
                    </svg>
                    Entrada solicitada
                  </span>
                  <span class="pp-telemed-room__admit-card2-time">
                    <svg
                      width="12"
                      height="12"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      aria-hidden="true"
                    >
                      <circle cx="12" cy="12" r="10" />
                      <polyline points="12 6 12 12 16 14" />
                    </svg>
                    {{ formatPendingDuration(info.since) }}
                  </span>
                </header>
                <div class="pp-telemed-room__admit-card2-body">
                  <div
                    class="pp-telemed-room__admit-card2-avatar"
                    :style="{ background: avatarColor(info.name) }"
                  >
                    {{ initial(info.name) }}
                    <span class="pp-telemed-room__admit-card2-dot" />
                  </div>
                  <div class="pp-telemed-room__admit-card2-info">
                    <h3 class="pp-telemed-room__admit-card2-name">
                      {{ info.name }}
                    </h3>
                    <p class="pp-telemed-room__admit-card2-sub">
                      Aguardando na sala de espera
                    </p>
                  </div>
                  <button
                    type="button"
                    class="pp-telemed-room__admit-card2-deny"
                    title="Recusar"
                    aria-label="Recusar"
                    @click="dismissPending(identity)"
                  >
                    <svg
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2.4"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      aria-hidden="true"
                    >
                      <line x1="18" y1="6" x2="6" y2="18" />
                      <line x1="6" y1="6" x2="18" y2="18" />
                    </svg>
                  </button>
                  <button
                    type="button"
                    class="pp-telemed-room__admit-card2-accept"
                    @click="admitPatient(identity)"
                  >
                    <svg
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="currentColor"
                      aria-hidden="true"
                    >
                      <path
                        d="M17 10.5V7a1 1 0 0 0-1-1H4a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-3.5l4 4v-11l-4 4z"
                      />
                    </svg>
                    Aceitar
                  </button>
                </div>
              </div>
            </div>

            <div
              v-if="showStats && remoteCount > 0"
              class="pp-telemed-room__stats"
              title="Clique pra ocultar"
              @click="showStats = false"
            >
              <div class="pp-telemed-room__stats-line">
                <span
                  class="pp-telemed-room__stats-dot"
                  :style="{ background: layerColor(stats.height) }"
                />
                <span>
                  {{ stats.layer }} · {{ stats.width }}×{{ stats.height }}
                </span>
              </div>
              <div>
                {{ stats.fps }}fps · {{ stats.kbps }}kbps · {{ stats.codec }}
              </div>
            </div>
            <button
              v-if="!showStats && remoteCount > 0"
              class="pp-telemed-room__stats-toggle"
              title="Mostrar estatísticas"
              @click="showStats = true"
            >
              <span class="pp-telemed-room__stats-dot" />
            </button>

            <!-- PIP local — avatar com inicial quando câmera off (igual Meet),
                 border azul + glow quando eu estiver falando. Quando o local
                 está pinado, esse container vira o stage (CSS class --as-stage). -->
            <div
              class="pp-telemed-room__local"
              :class="{
                'pp-telemed-room__local--off': !camOn,
                'pp-telemed-room__local--mirror':
                  cameraFacing !== 'environment',
                'pp-telemed-room__local--speaking': localSpeaking,
                'pp-telemed-room__local--as-stage': isLocalPinned,
              }"
            >
              <video ref="localVideo" autoplay muted playsinline />
              <div
                v-if="!camOn"
                class="pp-telemed-room__avatar pp-telemed-room__avatar--pip"
                :style="{ background: avatarColor(localName) }"
              >
                {{ initial(localName) }}
              </div>
              <div class="pp-telemed-room__local-name">
                <IconMicOff
                  v-if="!micOn"
                  :size="12"
                  class="pp-telemed-room__tile-mic-off"
                />
                <span>Você</span>
              </div>
              <!-- Pin trigger no PIP local. Menu vive teleportado no body
                   (final do template) pra escapar do overflow:hidden do PIP. -->
              <button
                type="button"
                class="pp-telemed-room__pin-btn pp-telemed-room__pin-btn--local"
                :class="{
                  'pp-telemed-room__pin-btn--active': isLocalPinned,
                }"
                :title="
                  isLocalPinned ? 'Fixado em destaque' : 'Fixar em destaque'
                "
                :aria-expanded="pinMenuOpenFor === LOCAL_PIN_KEY"
                @click.stop="togglePinMenu(LOCAL_PIN_KEY, $event)"
              >
                <svg
                  width="22"
                  height="22"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path d="M12 17v5" />
                  <path
                    d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"
                  />
                </svg>
              </button>
            </div>
          </div>
        </main>

        <!-- Chat sidebar — painel branco fixo à direita. Quando chatOpen,
             comprime o vídeo. System message centralizada como pill. Cada
             mensagem mostra autor + hora acima da bubble; bubbles com
             rounded-tl-none (recebidas) ou rounded-tr-none (enviadas). -->
        <aside v-if="chatOpen" class="pp-telemed-room__chat">
          <header class="pp-telemed-room__chat-head">
            <strong>Chat da consulta</strong>
            <button
              class="pp-telemed-room__chat-close"
              aria-label="Fechar chat"
              @click="chatOpen = false"
            >
              <IconClose :size="18" />
            </button>
          </header>

          <div v-if="isDoctor" class="pp-telemed-room__chat-toggle">
            <span class="pp-telemed-room__chat-toggle-label">
              Permitir que os participantes enviem mensagens
            </span>
            <button
              type="button"
              role="switch"
              :aria-checked="chatAllowed"
              class="pp-telemed-room__switch"
              :class="{ 'pp-telemed-room__switch--on': chatAllowed }"
              @click="toggleChatLock"
            >
              <span class="pp-telemed-room__switch-thumb" />
            </button>
          </div>

          <div
            v-if="!isDoctor && !chatAllowed"
            class="pp-telemed-room__chat-locked"
          >
            <IconMessage :size="16" />
            <span>O host desativou as mensagens.</span>
          </div>

          <div ref="chatList" class="pp-telemed-room__chat-list">
            <div class="pp-telemed-room__chat-system">
              <span>A chamada foi iniciada</span>
            </div>

            <div
              v-if="messages.length === 0"
              class="pp-telemed-room__chat-empty"
            >
              <div class="pp-telemed-room__chat-empty-icon">
                <IconChatBubble :size="48" />
              </div>
              <p class="pp-telemed-room__chat-empty-title">
                Ainda sem mensagens
              </p>
              <p class="pp-telemed-room__chat-empty-text">
                As mensagens não ficam salvas após o fim da chamada.
              </p>
            </div>
            <div
              v-for="m in messages"
              :key="m.id"
              class="pp-telemed-room__chat-row"
              :class="{ 'pp-telemed-room__chat-row--mine': m.fromMe }"
            >
              <div class="pp-telemed-room__chat-meta">
                {{ m.fromMe ? 'Você' : m.author }}
              </div>
              <div
                class="pp-telemed-room__chat-msg"
                :class="{ 'pp-telemed-room__chat-msg--mine': m.fromMe }"
              >
                {{ m.text }}
              </div>
            </div>
          </div>
          <form class="pp-telemed-room__chat-form" @submit.prevent="sendChat">
            <div class="pp-telemed-room__chat-input-wrap">
              <input
                v-model="chatInput"
                type="text"
                :placeholder="
                  !isDoctor && !chatAllowed
                    ? 'Mensagens desativadas pelo host'
                    : 'Digite uma mensagem…'
                "
                maxlength="500"
                :disabled="!isDoctor && !chatAllowed"
              />
              <button
                type="submit"
                class="pp-telemed-room__chat-send"
                aria-label="Enviar"
                :disabled="!chatInput.trim() || (!isDoctor && !chatAllowed)"
              >
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path d="M22 2L11 13" />
                  <path d="M22 2l-7 20-4-9-9-4 20-7z" />
                </svg>
              </button>
            </div>
          </form>
        </aside>
      </div>

      <!-- Toolbar flutuante (glassmorphism). Pill central com botões
           circulares + botão "Encerrar" vermelho na direita. Sobrepõe o
           vídeo, então fica posicionada absolute no main. -->
      <footer class="pp-telemed-room__controls">
        <div class="pp-telemed-room__controls-pill">
          <button
            class="pp-telemed-room__ctrl"
            :class="{ off: !micOn }"
            :title="micOn ? 'Silenciar' : 'Ativar microfone'"
            @click="toggleMic"
          >
            <IconMic v-if="micOn" :size="20" />
            <IconMicOff v-else :size="20" />
          </button>
          <button
            class="pp-telemed-room__ctrl"
            :class="{ off: !camOn }"
            :title="camOn ? 'Desligar câmera' : 'Ligar câmera'"
            @click="toggleCam"
          >
            <IconVideo v-if="camOn" :size="20" />
            <IconVideoOff v-else :size="20" />
          </button>
          <button
            v-if="hasMultipleCameras && isMobile"
            class="pp-telemed-room__ctrl"
            title="Trocar câmera"
            @click="switchCamera"
          >
            <IconSwitchCamera :size="20" />
          </button>
          <!-- Desfoque de fundo. Click no botão alterna o menu (popover acima);
               toggle dentro do menu liga/desliga o blur; slider ajusta a
               intensidade quando ligado. Estado active = blur on (cor Klivy). -->
          <div class="pp-telemed-room__blur-wrap">
            <button
              class="pp-telemed-room__ctrl"
              :class="{ 'pp-telemed-room__ctrl--active': blurEnabled }"
              :title="
                blurEnabled
                  ? `Desfoque ativo (intensidade ${blurIntensity})`
                  : 'Desfoque de fundo'
              "
              :aria-expanded="blurMenuOpen"
              aria-haspopup="dialog"
              @click="toggleBlurMenu"
            >
              <IconBlur :size="20" />
            </button>
            <div
              v-if="blurMenuOpen"
              v-on-click-outside="closeBlurMenu"
              class="pp-telemed-room__blur-menu"
              role="dialog"
              aria-label="Desfoque de fundo"
            >
              <div class="pp-telemed-room__blur-menu-head">
                <span class="pp-telemed-room__blur-menu-title">
                  Desfoque de fundo
                </span>
                <button
                  type="button"
                  role="switch"
                  :aria-checked="blurEnabled"
                  :disabled="blurApplying"
                  class="pp-telemed-room__switch"
                  :class="{ 'pp-telemed-room__switch--on': blurEnabled }"
                  @click="toggleBlur"
                >
                  <span class="pp-telemed-room__switch-thumb" />
                </button>
              </div>
              <div v-if="blurEnabled" class="pp-telemed-room__blur-menu-body">
                <label class="pp-telemed-room__blur-menu-label">
                  <span>Intensidade</span>
                  <span class="pp-telemed-room__blur-menu-value">
                    {{ blurIntensity }}
                  </span>
                </label>
                <input
                  type="range"
                  min="5"
                  max="50"
                  step="1"
                  class="pp-telemed-room__blur-slider"
                  :style="{
                    '--telemed-slider-progress':
                      ((blurIntensity - 5) / 45) * 100 + '%',
                  }"
                  :value="blurIntensity"
                  @input="setBlurIntensity($event.target.value)"
                />
                <div class="pp-telemed-room__blur-slider-ticks">
                  <span>Leve</span>
                  <span>Forte</span>
                </div>
              </div>
              <p class="pp-telemed-room__blur-menu-hint">
                Processado no seu computador. Pode usar mais bateria.
              </p>
            </div>
          </div>
          <!-- 2026-05-22 — Botão Gravar (só doutor).
               OFF: bolinha vermelha preenchida = "clique pra começar a gravar".
               ON:  quadradinho vermelho preenchido pulsando = "REC, clique pra parar".
               Mimetiza o padrão universal de câmeras (record ⏺ / stop ⏹).
               Tooltip "balão de gibi" aparece 7s ao entrar na sala lembrando
               de gravar (auto-dismiss; some ao clicar no botão também). -->
          <div v-if="isDoctor" class="pp-telemed-room__rec-wrap">
            <button
              class="pp-telemed-room__ctrl pp-telemed-room__ctrl--rec"
              :class="{ 'pp-telemed-room__ctrl--rec-on': recordingActive }"
              :disabled="recordingToggling"
              :title="recordButtonTitle"
              :aria-pressed="recordingActive"
              :aria-label="recordButtonTitle"
              @click="toggleRecording"
            >
              <!-- OFF: bolinha vermelha preenchida (record icon). -->
              <svg
                v-if="!recordingActive"
                class="pp-telemed-room__rec-icon"
                width="18"
                height="18"
                viewBox="0 0 24 24"
                aria-hidden="true"
              >
                <circle cx="12" cy="12" r="7" fill="#dc2626" />
              </svg>
              <!-- ON: quadradinho vermelho preenchido (stop icon). -->
              <svg
                v-else
                class="pp-telemed-room__rec-icon pp-telemed-room__rec-icon--on"
                width="18"
                height="18"
                viewBox="0 0 24 24"
                aria-hidden="true"
              >
                <rect x="5.5" y="5.5" width="13" height="13" rx="2" fill="#dc2626" />
              </svg>
              <!-- Spinner enquanto o toggle está em flight (start_recording
                   pode levar 1-2s no LiveKit). -->
              <span
                v-if="recordingToggling"
                class="pp-telemed-room__rec-spinner"
                aria-hidden="true"
              />
            </button>
            <transition name="pp-telemed-room__rec-hint">
              <div
                v-if="recordHintVisible"
                class="pp-telemed-room__rec-hint"
                role="tooltip"
                @click="dismissRecordHint"
              >
                <span class="pp-telemed-room__rec-hint-text">
                  Não esqueça de gravar essa consulta
                </span>
                <span class="pp-telemed-room__rec-hint-tail" />
              </div>
            </transition>
            <transition name="pp-telemed-room__rec-err">
              <div
                v-if="recordingError"
                class="pp-telemed-room__rec-err"
                role="alert"
              >
                {{ recordingError }}
              </div>
            </transition>
          </div>
          <button
            class="pp-telemed-room__ctrl"
            :class="{ 'pp-telemed-room__ctrl--share-on': screenOn }"
            :title="screenOn ? 'Parar compartilhamento' : 'Compartilhar tela'"
            @click="toggleScreen"
          >
            <IconScreenShare :size="20" />
          </button>
          <span class="pp-telemed-room__ctrl-sep" />
          <button
            class="pp-telemed-room__ctrl"
            :class="{ 'pp-telemed-room__ctrl--active': chatOpen }"
            title="Chat"
            @click="chatOpen = !chatOpen"
          >
            <IconMessage :size="20" />
            <span v-if="unreadChat" class="pp-telemed-room__badge">
              {{ unreadChat }}
            </span>
          </button>
        </div>
        <button
          class="pp-telemed-room__leave"
          title="Sair da consulta"
          @click="leave"
        >
          <svg
            width="22"
            height="22"
            viewBox="0 0 24 24"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              d="M12 9c-1.6 0-3.15.25-4.6.72v3.1c0 .39-.23.74-.56.9-.98.49-1.88 1.11-2.66 1.85-.18.18-.43.28-.7.28-.28 0-.53-.11-.71-.29L.29 13.08a.965.965 0 0 1-.29-.7c0-.28.11-.53.29-.71C3.34 8.78 7.46 7 12 7s8.66 1.78 11.71 4.67c.18.18.29.43.29.71 0 .28-.11.53-.29.71l-2.48 2.48c-.18.18-.43.29-.71.29-.27 0-.52-.1-.7-.28-.78-.74-1.68-1.36-2.66-1.85a.997.997 0 0 1-.56-.9v-3.1C15.15 9.25 13.6 9 12 9z"
            />
          </svg>
          <span>Encerrar</span>
        </button>
      </footer>
    </template>

    <!-- Menu de Pin compartilhado (teleportado pro body pra escapar de
         qualquer overflow:hidden). Renderizado apenas quando aberto;
         posição calculada inline no momento do clique no botão trigger. -->
    <Teleport to="body">
      <div
        v-if="pinMenuOpenFor"
        v-on-click-outside="closePinMenu"
        class="pp-telemed-room__pin-menu"
        role="menu"
        :style="pinMenuStyle"
      >
        <button
          v-if="
            pinMenuOpenFor === LOCAL_PIN_KEY
              ? isLocalPinned
              : isParticipantPinned(pinMenuOpenFor)
          "
          type="button"
          class="pp-telemed-room__pin-menu-item"
          @click="unpin"
        >
          Desafixar
        </button>
        <template v-else>
          <button
            type="button"
            class="pp-telemed-room__pin-menu-item"
            @click="pinFor(pinMenuOpenFor, false)"
          >
            Fixar pra mim
          </button>
          <button
            v-if="isDoctor"
            type="button"
            class="pp-telemed-room__pin-menu-item pp-telemed-room__pin-menu-item--primary"
            @click="pinFor(pinMenuOpenFor, true)"
          >
            Fixar pra todos
          </button>
        </template>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
/* ───────────────────────────────────────────────────────────────────────
   Sala de telemedicina — redesign 2026-05-21 (Klivy minimalista).
   Stage preto full-bleed; header e toolbar flutuam SOBRE o vídeo (overlay
   com gradient discreto). Chat sidebar empurra o stage à esquerda (não
   sobrepõe). Cor de marca: #1552F1 (Klivy primary).
   ─────────────────────────────────────────────────────────────────────── */
.pp-telemed-room {
  position: fixed;
  inset: 0;
  background: #000;
  color: #f8fafc;
  display: flex;
  flex-direction: column;
  z-index: 1000;
  font-feature-settings: 'cv11', 'ss01';
}

/* Overlay de loading/erro — fundo preto translúcido coerente com o stage. */
.pp-telemed-room__overlay {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  background: rgba(0, 0, 0, 0.85);
  backdrop-filter: blur(8px);
  z-index: 50;
}
.pp-telemed-room__spinner {
  width: 36px;
  height: 36px;
  border: 3px solid rgba(255, 255, 255, 0.18);
  border-top-color: #1552f1;
  border-radius: 50%;
  animation: spin 0.9s linear infinite;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
.pp-telemed-room__status {
  font-size: 14px;
  color: #cbd5e1;
}
.pp-telemed-room__status--error {
  color: #fca5a5;
  max-width: 80%;
  text-align: center;
}
.pp-telemed-room__btn {
  margin-top: 12px;
  padding: 10px 20px;
  background: #1552f1;
  color: #fff;
  border: 0;
  border-radius: 10px;
  font-weight: 600;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-telemed-room__btn:hover {
  background: #0c3fcc;
}

/* ─── Body (split: stage preto | chat sidebar) ────────────────────── */
.pp-telemed-room__body {
  flex: 1;
  display: flex;
  min-height: 0;
}
.pp-telemed-room__main {
  position: relative;
  flex: 1;
  min-width: 0;
  background: #000;
  overflow: hidden;
}

/* ─── Header overlay (gradient escuro topo) ─────────────────────────
   Sobrepõe o vídeo. Gradient suave do preto pra transparente garante
   legibilidade sem cobrir muito. */
.pp-telemed-room__header {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 16px 24px;
  background: linear-gradient(
    to bottom,
    rgba(0, 0, 0, 0.55) 0%,
    rgba(0, 0, 0, 0.25) 60%,
    transparent 100%
  );
  pointer-events: none;
}
.pp-telemed-room__header > * {
  pointer-events: auto;
}
.pp-telemed-room__header-left,
.pp-telemed-room__header-right {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
}
.pp-telemed-room__back {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.12);
  border: 0;
  color: #fff;
  cursor: pointer;
  backdrop-filter: blur(6px);
  transition: background 120ms ease;
}
.pp-telemed-room__back:hover {
  background: rgba(255, 255, 255, 0.22);
}
.pp-telemed-room__brand {
  font-size: 18px;
  font-weight: 700;
  color: #fff;
  letter-spacing: -0.01em;
}
.pp-telemed-room__brand-sep {
  display: inline-block;
  width: 1px;
  height: 22px;
  background: rgba(255, 255, 255, 0.25);
}
.pp-telemed-room__participant {
  font-size: 14px;
  font-weight: 600;
  color: rgba(255, 255, 255, 0.95);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 220px;
}
.pp-telemed-room__status-pill {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 5px 12px;
  background: rgba(34, 197, 94, 0.18);
  color: #86efac;
  border: 1px solid rgba(34, 197, 94, 0.35);
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
  backdrop-filter: blur(8px);
  white-space: nowrap;
}
.pp-telemed-room__status-pill--warn {
  background: rgba(251, 191, 36, 0.18);
  color: #fcd34d;
  border-color: rgba(251, 191, 36, 0.35);
}
.pp-telemed-room__status-dot-pulse {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
  box-shadow: 0 0 0 0 currentColor;
  animation: telemed-pulse 1.8s ease-out infinite;
}
@keyframes telemed-pulse {
  0% {
    box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.55);
  }
  70% {
    box-shadow: 0 0 0 8px rgba(34, 197, 94, 0);
  }
  100% {
    box-shadow: 0 0 0 0 rgba(34, 197, 94, 0);
  }
}
.pp-telemed-room__conn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 5px 12px;
  background: rgba(0, 0, 0, 0.4);
  color: #fff;
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 10px;
  font-size: 12px;
  font-weight: 500;
  backdrop-filter: blur(8px);
  white-space: nowrap;
  /* Variável CSS controla a cor das barras pra warn/bad sem repetir
     o keyframe inteiro. */
  --conn-bar-color: #4ade80;
  --conn-bar-duration: 1.4s;
}
.pp-telemed-room__conn--warn {
  --conn-bar-color: #fbbf24;
  --conn-bar-duration: 0.9s;
  color: #fef3c7;
}
.pp-telemed-room__conn--bad {
  --conn-bar-color: #f87171;
  --conn-bar-duration: 0.6s;
  color: #fecaca;
}

/* 3 barras estilo "wifi/equalizador" que sobem e descem em loop discreto.
   Cada barra com delay diferente — efeito de onda. `transform-origin: bottom`
   pra crescer a partir da base (visualmente parece "pulso"). */
.pp-telemed-room__conn-bars {
  display: inline-flex;
  align-items: flex-end;
  gap: 2px;
  height: 12px;
}
.pp-telemed-room__conn-bar {
  display: inline-block;
  width: 3px;
  height: 100%;
  background: var(--conn-bar-color);
  border-radius: 1px;
  transform-origin: bottom;
  animation: telemed-conn-bar var(--conn-bar-duration) ease-in-out infinite;
}
.pp-telemed-room__conn-bar:nth-child(1) {
  animation-delay: 0s;
}
.pp-telemed-room__conn-bar:nth-child(2) {
  animation-delay: 0.18s;
}
.pp-telemed-room__conn-bar:nth-child(3) {
  animation-delay: 0.36s;
}
@keyframes telemed-conn-bar {
  0%,
  100% {
    transform: scaleY(0.4);
    opacity: 0.55;
  }
  50% {
    transform: scaleY(1);
    opacity: 1;
  }
}
/* Respeita prefers-reduced-motion — sem animar pra quem desliga animações
   no SO/browser. Mantém só a cor pra ainda comunicar o estado. */
@media (prefers-reduced-motion: reduce) {
  .pp-telemed-room__conn-bar {
    animation: none;
    transform: scaleY(0.8);
    opacity: 1;
  }
}
.pp-telemed-room__code {
  font-family: ui-monospace, Menlo, Monaco, monospace;
  font-size: 11px;
  font-weight: 500;
  color: rgba(255, 255, 255, 0.65);
  letter-spacing: 0.6px;
  padding: 4px 10px;
  background: rgba(0, 0, 0, 0.35);
  border-radius: 8px;
  backdrop-filter: blur(6px);
}
.pp-telemed-room__dev {
  font-size: 10px;
  font-weight: 700;
  background: #fbbf24;
  color: #422006;
  padding: 3px 8px;
  border-radius: 999px;
}

.pp-telemed-room__stage {
  position: absolute;
  inset: 0;
  overflow: hidden;
}
/* Tiles dos participantes remotos. Quando 1 participante, ocupa full
   bleed (sem padding/borda) pra dar o efeito "vídeo gigante". Com 2+,
   vira grid clássico. */
.pp-telemed-room__tiles {
  position: absolute;
  inset: 0;
  display: grid;
  grid-template-columns: 1fr;
}
.pp-telemed-room__tiles[data-count='2'],
.pp-telemed-room__tiles[data-count='3'],
.pp-telemed-room__tiles[data-count='4'] {
  gap: 8px;
  padding: 8px;
}
.pp-telemed-room__tiles[data-count='2'] {
  grid-template-columns: 1fr 1fr;
}
.pp-telemed-room__tiles[data-count='3'],
.pp-telemed-room__tiles[data-count='4'] {
  grid-template-columns: 1fr 1fr;
  grid-template-rows: 1fr 1fr;
}
.pp-telemed-room__tile {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  background: #0a0a0a;
  overflow: hidden;
  border: 2px solid transparent;
  transition:
    border-color 160ms ease,
    box-shadow 160ms ease;
}
.pp-telemed-room__tiles[data-count='2'] .pp-telemed-room__tile,
.pp-telemed-room__tiles[data-count='3'] .pp-telemed-room__tile,
.pp-telemed-room__tiles[data-count='4'] .pp-telemed-room__tile {
  border-radius: 16px;
}
.pp-telemed-room__tile--speaking {
  border-color: #1552f1;
  box-shadow: 0 0 0 3px rgba(21, 82, 241, 0.4);
}
.pp-telemed-room__tile-video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
/* Screen share: contain (não corta a tela compartilhada — usuário precisa
   ver o conteúdo todo). Fundo preto preenche aspect-ratio mismatch. */
.pp-telemed-room__tile-video--contain {
  object-fit: contain;
  background: #000;
}
.pp-telemed-room__tile-video--hidden {
  display: none;
}
/* Screen share tile: borda mais discreta (não é "alguém falando"); fundo
   preto pra contraste com a UI compartilhada. */
.pp-telemed-room__tile--screen {
  background: #000;
}
.pp-telemed-room__tile-name {
  position: absolute;
  left: 16px;
  bottom: 16px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 5px 12px;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 500;
  backdrop-filter: blur(6px);
}
.pp-telemed-room__tile-mic-off {
  color: #f87171;
}

/* Overlay grande de mic-off no centro do tile. Padrão Meet/Zoom: avisa de
   forma clara que o participante está mudo, mesmo no canto da galeria.
   Posicionamento absoluto, semi-transparente pra não competir com o vídeo
   se ele estiver visível atrás. */
.pp-telemed-room__tile-mute-overlay {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  backdrop-filter: blur(8px);
  -webkit-backdrop-filter: blur(8px);
  pointer-events: none;
  z-index: 1;
}

.pp-telemed-room__avatar {
  display: flex;
  align-items: center;
  justify-content: center;
  width: min(22vw, 140px);
  height: min(22vw, 140px);
  border-radius: 50%;
  font-size: min(9vw, 56px);
  font-weight: 600;
  color: #fff;
  letter-spacing: 0.5px;
  user-select: none;
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.4);
}
.pp-telemed-room__avatar--pip {
  width: 56px;
  height: 56px;
  font-size: 22px;
  box-shadow: none;
}

/* Waiting state — fundo cinza claro suave (não preto puro pra não parecer
   freezada), ícone redondo em cinza azulado, texto cinza médio. */
.pp-telemed-room__waiting {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  background: #e8edf3;
  color: #64748b;
  text-align: center;
  padding: 20px;
  font-size: 14px;
}
.pp-telemed-room__waiting p {
  margin: 0;
  font-weight: 500;
}
.pp-telemed-room__waiting-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 84px;
  height: 84px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.85);
  color: #64748b;
  box-shadow: 0 4px 20px rgba(15, 23, 42, 0.08);
}

.pp-telemed-room__speaker {
  position: absolute;
  top: 80px;
  right: 24px;
  background: rgba(34, 197, 94, 0.85);
  color: #fff;
  padding: 6px 12px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
  z-index: 18;
  backdrop-filter: blur(4px);
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.pp-telemed-room__stats {
  position: absolute;
  top: 80px;
  left: 24px;
  background: rgba(0, 0, 0, 0.65);
  color: #fff;
  padding: 6px 10px;
  border-radius: 8px;
  font-family: ui-monospace, Menlo, Monaco, monospace;
  font-size: 11px;
  line-height: 1.4;
  z-index: 18;
  cursor: pointer;
  backdrop-filter: blur(6px);
}
.pp-telemed-room__stats-toggle {
  position: absolute;
  top: 80px;
  left: 24px;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  border: 0;
  width: 28px;
  height: 28px;
  border-radius: 8px;
  cursor: pointer;
  z-index: 18;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  backdrop-filter: blur(6px);
}
.pp-telemed-room__stats-line {
  display: flex;
  align-items: center;
  gap: 6px;
}
.pp-telemed-room__stats-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #22c55e;
  flex-shrink: 0;
}

/* PIP local — bottom-right elevado pra não chocar com a toolbar (que fica
   floating bottom 24). Tamanho um pouco maior pra dar presença; rounded-xl
   + shadow-popover. Cresce sutilmente no hover. */
.pp-telemed-room__local {
  position: absolute;
  right: 24px;
  bottom: 112px;
  width: 220px;
  height: 156px;
  border-radius: 14px;
  background: #1e293b;
  overflow: hidden;
  border: 2px solid rgba(255, 255, 255, 0.18);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 15;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.45);
  transition:
    transform 200ms ease,
    border-color 160ms ease,
    box-shadow 160ms ease;
}
.pp-telemed-room__local:hover {
  transform: scale(1.03);
}
.pp-telemed-room__local video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.pp-telemed-room__local--mirror video {
  transform: scaleX(-1);
}
.pp-telemed-room__local--off {
  background: #1e293b;
}
.pp-telemed-room__local--speaking {
  border-color: #1552f1;
  box-shadow:
    0 12px 32px rgba(0, 0, 0, 0.45),
    0 0 0 3px rgba(21, 82, 241, 0.5);
}
.pp-telemed-room__local-name {
  position: absolute;
  left: 10px;
  bottom: 10px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 10px;
  background: rgba(0, 0, 0, 0.6);
  color: #fff;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 500;
  backdrop-filter: blur(6px);
  pointer-events: none;
}

/* ─── Pin (spotlight) ─────────────────────────────────────────────────
   Botão circular pequeno no canto superior direito de cada tile (remoto)
   e do PIP local. Esconde no idle, aparece no hover ou se já está pinado.
   Menu de opções abre como dropdown direcionado pra dentro (não pra fora
   do container) pra não ser cortado pelo overflow:hidden do tile.

   Posicionado CENTRALIZADO no tile/PIP. Background preto translúcido leve
   (~25%) com blur — sutil, não chama atenção. Só aparece em hover sobre o
   tile/PIP; quando o mouse sai, some completamente. Estado "fixado" não
   muda o botão — o sinal de fixado é o badge no canto, não o botão. */
.pp-telemed-room__pin-btn {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%) scale(0.85);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 56px;
  height: 56px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.25);
  color: #fff;
  border: 0;
  cursor: pointer;
  opacity: 0;
  pointer-events: none;
  z-index: 6;
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  transition:
    opacity 180ms ease,
    background 140ms ease,
    transform 140ms ease;
}
.pp-telemed-room__pin-btn svg {
  width: 26px;
  height: 26px;
}
.pp-telemed-room__pin-btn--local svg {
  width: 22px;
  height: 22px;
}
.pp-telemed-room__pin-btn--local {
  width: 48px;
  height: 48px;
}
/* Único trigger de visibilidade: hover sobre o tile/PIP. Sem hover, some.
   pointer-events: none quando hidden evita clique fantasma em botão
   "invisível" sobreposto ao vídeo. */
.pp-telemed-room__tile:hover .pp-telemed-room__pin-btn,
.pp-telemed-room__local:hover .pp-telemed-room__pin-btn {
  opacity: 1;
  pointer-events: auto;
  transform: translate(-50%, -50%) scale(1);
}
.pp-telemed-room__pin-btn:hover {
  background: rgba(0, 0, 0, 0.5);
}

/* Menu de opções — teleportado pro body, posição fixed setada inline pelo
   JS. Estilos aqui só cuidam de aparência (border, padding, items). */
.pp-telemed-room__pin-menu {
  min-width: 200px;
  padding: 6px;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 12px;
  box-shadow: 0 16px 40px rgba(7, 16, 42, 0.22);
  display: flex;
  flex-direction: column;
  gap: 2px;
  z-index: 1100;
  animation: telemed-pin-menu-in 140ms ease-out;
}
@keyframes telemed-pin-menu-in {
  from {
    opacity: 0;
    transform: translateY(-4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
.pp-telemed-room__pin-menu-item {
  display: block;
  width: 100%;
  padding: 8px 12px;
  background: transparent;
  border: 0;
  border-radius: 6px;
  text-align: left;
  font-size: 13px;
  font-weight: 500;
  color: #1c1b1b;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-telemed-room__pin-menu-item:hover {
  background: #f1f5f9;
}
.pp-telemed-room__pin-menu-item--primary {
  color: #1552f1;
  font-weight: 600;
}
.pp-telemed-room__pin-menu-item--primary:hover {
  background: rgba(21, 82, 241, 0.08);
}

/* Badge mostrando estado fixado no canto superior esquerdo do tile. */
.pp-telemed-room__pin-badge {
  position: absolute;
  top: 12px;
  left: 12px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px;
  background: rgba(21, 82, 241, 0.92);
  color: #fff;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.02em;
  backdrop-filter: blur(6px);
  z-index: 5;
  pointer-events: none;
}

/* Tile pinado — border azul Klivy primary pra reforçar destaque. */
.pp-telemed-room__tile--pinned {
  border-color: #1552f1;
  box-shadow: 0 0 0 3px rgba(21, 82, 241, 0.3);
}

/* ─── Layout swap: local em destaque (pinned-self) ─────────────────────
   Quando o usuário fixa a si mesmo, o PIP local cresce pra ocupar o stage
   inteiro e os tiles remotos viram thumbnails na lateral (acima de onde o
   PIP estava). Funciona pra 1-on-1 (caso comum em telemed) e degrada ok
   pra 2+ remotos (cada um vira um card menor). */
.pp-telemed-room__local--as-stage {
  position: absolute;
  inset: 0;
  right: 0;
  bottom: 0;
  width: 100%;
  height: 100%;
  border-radius: 0;
  border: 0;
  box-shadow: none;
  z-index: 1;
  transition: none;
}
.pp-telemed-room__local--as-stage:hover {
  transform: none;
}

/* Quando o local é o pinado, troca os tiles remotos pra um stack vertical
   pequeno no canto inferior direito (onde o PIP normalmente fica). */
.pp-telemed-room__stage--pinned-self .pp-telemed-room__tiles {
  position: absolute;
  bottom: 112px;
  right: 24px;
  top: auto;
  left: auto;
  width: 220px;
  height: auto;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 0;
  grid-template-columns: none !important;
  grid-template-rows: none !important;
  z-index: 14;
}
.pp-telemed-room__stage--pinned-self .pp-telemed-room__tile {
  width: 220px;
  height: 156px;
  border-radius: 14px;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.45);
}
/* Em pinned-self, esconde o nome do PIP local (ele agora é o stage,
   nome embaixo fica redundante e poluído). */
.pp-telemed-room__local--as-stage .pp-telemed-room__local-name {
  bottom: 100px;
  left: 24px;
  font-size: 13px;
  padding: 5px 14px;
}
/* Stage com pin (qualquer pin) — esconde a tarja "Você" do PIP local
   quando ele tá em modo PIP normal (sem destaque). Pra não conflitar
   visualmente com o badge do pinado. */

/* Banner de erro de mídia — flutuante no topo do stage (overlay). */
.pp-telemed-room__media-error {
  position: absolute;
  top: 80px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 19;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  background: #fef3c7;
  border: 1px solid #fde68a;
  border-radius: 12px;
  color: #78350f;
  max-width: calc(100% - 48px);
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.25);
}
.pp-telemed-room__media-error-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: #fde68a;
  color: #b45309;
  flex-shrink: 0;
}
.pp-telemed-room__media-error-text {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.pp-telemed-room__media-error-text strong {
  font-size: 13px;
  font-weight: 700;
}
.pp-telemed-room__media-error-text p {
  margin: 0;
  font-size: 12px;
  line-height: 1.4;
}
.pp-telemed-room__media-error-btn {
  padding: 8px 14px;
  background: #b45309;
  color: #fff;
  border: 0;
  border-radius: 8px;
  font-size: 12px;
  font-weight: 700;
  cursor: pointer;
  flex-shrink: 0;
  transition: background 120ms ease;
}
.pp-telemed-room__media-error-btn:hover {
  background: #92400e;
}

/* ─── Chat sidebar ────────────────────────────────────────────────────
   Painel branco fixo de 400px à direita. Sistema message centralizada
   como pill cinza; bubbles com autor+hora acima; sent em Klivy primary. */
.pp-telemed-room__chat {
  width: 400px;
  flex-shrink: 0;
  background: #fff;
  border-left: 1px solid #e5e7eb;
  display: flex;
  flex-direction: column;
  min-height: 0;
  color: #0f172a;
  box-shadow: -10px 0 30px rgba(7, 16, 42, 0.08);
}
.pp-telemed-room__chat-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 18px 20px;
  border-bottom: 1px solid #e5e7eb;
  font-size: 16px;
  font-weight: 600;
  color: #0f172a;
}
.pp-telemed-room__chat-close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  color: #64748b;
  border: 0;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  cursor: pointer;
  padding: 0;
  transition:
    background 120ms ease,
    color 120ms ease;
}
.pp-telemed-room__chat-close:hover {
  background: #f1f5f9;
  color: #0f172a;
}

.pp-telemed-room__chat-toggle {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 20px;
  border-bottom: 1px solid #f1f5f9;
}
.pp-telemed-room__chat-toggle-label {
  flex: 1;
  font-size: 12px;
  color: #475569;
  line-height: 1.4;
}
.pp-telemed-room__switch {
  position: relative;
  width: 36px;
  height: 20px;
  border-radius: 999px;
  background: #cbd5e1;
  border: 0;
  cursor: pointer;
  flex-shrink: 0;
  transition: background 160ms ease;
  padding: 0;
}
.pp-telemed-room__switch--on {
  background: #1552f1;
}
.pp-telemed-room__switch-thumb {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 16px;
  height: 16px;
  background: #fff;
  border-radius: 50%;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
  transition: left 160ms ease;
}
.pp-telemed-room__switch--on .pp-telemed-room__switch-thumb {
  left: 18px;
}

.pp-telemed-room__chat-locked {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 20px;
  background: #fef3c7;
  color: #78350f;
  font-size: 12px;
  border-bottom: 1px solid #fde68a;
}

.pp-telemed-room__chat-list {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 18px;
  background: #ffffff;
}

/* System message centralizada (pill cinza) — "A chamada foi iniciada". */
.pp-telemed-room__chat-system {
  display: flex;
  justify-content: center;
}
.pp-telemed-room__chat-system span {
  display: inline-block;
  padding: 5px 14px;
  background: #ebe7e7;
  color: #64748b;
  font-size: 11px;
  font-weight: 500;
  border-radius: 999px;
}

.pp-telemed-room__chat-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  flex: 1;
  padding: 32px 20px;
  color: #94a3b8;
}
.pp-telemed-room__chat-empty-icon {
  margin-bottom: 12px;
  color: #cbd5e1;
}
.pp-telemed-room__chat-empty-title {
  margin: 0 0 6px;
  font-size: 14px;
  font-weight: 600;
  color: #475569;
}
.pp-telemed-room__chat-empty-text {
  margin: 0;
  font-size: 12px;
  color: #94a3b8;
  line-height: 1.5;
  max-width: 240px;
}

/* Linha = autor/hora + bubble. Recebida alinha à esquerda, enviada à
   direita. Bubble com canto chanfrado no lado do remetente. */
.pp-telemed-room__chat-row {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  max-width: 85%;
  gap: 4px;
}
.pp-telemed-room__chat-row--mine {
  align-items: flex-end;
  align-self: flex-end;
}
.pp-telemed-room__chat-meta {
  font-size: 11px;
  font-weight: 500;
  color: #64748b;
  padding: 0 4px;
}
.pp-telemed-room__chat-msg {
  padding: 10px 14px;
  border-radius: 16px;
  border-top-left-radius: 4px;
  background: #ebe7e7;
  color: #1c1b1b;
  font-size: 14px;
  line-height: 1.5;
  word-wrap: break-word;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}
.pp-telemed-room__chat-msg--mine {
  background: #1552f1;
  color: #fff;
  border-top-left-radius: 16px;
  border-top-right-radius: 4px;
}

.pp-telemed-room__chat-form {
  padding: 14px 20px 20px;
  border-top: 1px solid #e5e7eb;
  background: #fcf9f8;
}
.pp-telemed-room__chat-input-wrap {
  position: relative;
  display: flex;
  align-items: center;
}
.pp-telemed-room__chat-form input {
  flex: 1;
  min-width: 0;
  padding: 12px 48px 12px 16px;
  background: #fff;
  color: #0f172a;
  border: 1px solid #e5e7eb;
  border-radius: 12px;
  font-size: 14px;
  line-height: 1.4;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
}
.pp-telemed-room__chat-form input::placeholder {
  color: #94a3b8;
}
.pp-telemed-room__chat-form input:focus {
  outline: 0;
  border-color: #1552f1;
  box-shadow: 0 0 0 3px rgba(21, 82, 241, 0.12);
}
.pp-telemed-room__chat-form input:disabled {
  background: #f1f5f9;
  cursor: not-allowed;
}
.pp-telemed-room__chat-send {
  position: absolute;
  right: 8px;
  top: 50%;
  transform: translateY(-50%);
  width: 32px;
  height: 32px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  color: #1552f1;
  border: 0;
  border-radius: 8px;
  cursor: pointer;
  transition:
    background 120ms ease,
    color 120ms ease;
}
.pp-telemed-room__chat-send:hover:not(:disabled) {
  background: rgba(21, 82, 241, 0.1);
}
.pp-telemed-room__chat-send:disabled {
  color: #cbd5e1;
  cursor: not-allowed;
}

@media (max-width: 768px) {
  .pp-telemed-room__chat {
    position: absolute;
    inset: 0;
    width: 100%;
    border-left: 0;
    z-index: 30;
  }
}

/* Sala de espera (paciente) — overlay escuro com card branco no centro.
   Backdrop blur para focar o card sem perder noção do vídeo. */
.pp-telemed-room__admit-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.65);
  backdrop-filter: blur(10px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 25;
  padding: 20px;
}
.pp-telemed-room__admit-card {
  width: 100%;
  max-width: 380px;
  padding: 32px 28px;
  background: #fff;
  border-radius: 24px;
  box-shadow: 0 24px 60px -12px rgba(0, 0, 0, 0.45);
  text-align: center;
  color: #0f172a;
}
.pp-telemed-room__admit-card h2 {
  margin: 18px 0 8px;
  font-size: 20px;
  font-weight: 700;
  color: #0f172a;
}
.pp-telemed-room__admit-card p {
  font-size: 14px;
  color: #475569;
  line-height: 1.55;
  margin: 0;
}
.pp-telemed-room__admit-spinner {
  width: 44px;
  height: 44px;
  margin: 0 auto;
  border: 3px solid rgba(21, 82, 241, 0.15);
  border-top-color: #1552f1;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

/* ─── Cards de admit (doutor) ─────────────────────────────────────────
   Stack vertical no canto inferior direito (acima do PIP local). Cada
   pedido vira um card branco com pill "Entrada solicitada", tempo
   decorrido, avatar do paciente + nome e dois botões (recusar/aceitar). */
.pp-telemed-room__admit-stack {
  position: absolute;
  right: 24px;
  bottom: 288px;
  z-index: 22;
  display: flex;
  flex-direction: column;
  gap: 12px;
  width: 360px;
  max-width: calc(100vw - 48px);
  pointer-events: none;
}
.pp-telemed-room__admit-card2 {
  pointer-events: auto;
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 18px;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 18px;
  box-shadow: 0 16px 40px rgba(7, 16, 42, 0.18);
  color: #1c1b1b;
  animation: telemed-admit-card-in 220ms cubic-bezier(0.22, 0.61, 0.36, 1);
}
@keyframes telemed-admit-card-in {
  from {
    opacity: 0;
    transform: translateX(20px);
  }
  to {
    opacity: 1;
    transform: translateX(0);
  }
}
.pp-telemed-room__admit-card2-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.pp-telemed-room__admit-card2-tag {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 5px 12px;
  background: #dde1ff;
  color: #0038b6;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
.pp-telemed-room__admit-card2-time {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: #64748b;
  font-weight: 500;
}
.pp-telemed-room__admit-card2-body {
  display: flex;
  align-items: center;
  gap: 12px;
}
.pp-telemed-room__admit-card2-avatar {
  position: relative;
  width: 48px;
  height: 48px;
  border-radius: 50%;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  font-size: 18px;
  font-weight: 600;
  flex-shrink: 0;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.08);
}
.pp-telemed-room__admit-card2-dot {
  position: absolute;
  right: -2px;
  bottom: -2px;
  width: 12px;
  height: 12px;
  background: #22c55e;
  border: 2px solid #fff;
  border-radius: 50%;
}
.pp-telemed-room__admit-card2-info {
  flex: 1;
  min-width: 0;
}
.pp-telemed-room__admit-card2-name {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  color: #1c1b1b;
  line-height: 1.3;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.pp-telemed-room__admit-card2-sub {
  margin: 2px 0 0;
  font-size: 13px;
  color: #64748b;
  line-height: 1.4;
}
.pp-telemed-room__admit-card2-deny,
.pp-telemed-room__admit-card2-accept {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: 0;
  cursor: pointer;
  transition:
    background 140ms ease,
    transform 100ms ease;
  flex-shrink: 0;
}
.pp-telemed-room__admit-card2-deny:active,
.pp-telemed-room__admit-card2-accept:active {
  transform: scale(0.95);
}
.pp-telemed-room__admit-card2-deny {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  background: #ef4444;
  color: #fff;
}
.pp-telemed-room__admit-card2-deny:hover {
  background: #dc2626;
}
.pp-telemed-room__admit-card2-accept {
  gap: 6px;
  padding: 0 16px;
  height: 40px;
  border-radius: 12px;
  background: #22c55e;
  color: #fff;
  font-size: 14px;
  font-weight: 600;
}
.pp-telemed-room__admit-card2-accept:hover {
  background: #16a34a;
}

@media (max-width: 640px) {
  .pp-telemed-room__admit-stack {
    right: 16px;
    bottom: 220px;
    width: calc(100vw - 32px);
  }
  .pp-telemed-room__admit-card2 {
    padding: 14px;
  }
  .pp-telemed-room__admit-card2-accept span {
    display: none;
  }
}

/* ─── Toolbar flutuante (glassmorphism) ───────────────────────────────
   Pill central com botões circulares + botão "Encerrar" vermelho ao lado.
   Auto-hide: a pill some pra baixo quando o mouse sai da zona inferior
   da viewport (toolbarRevealed=false → classe não aplicada). O botão
   Encerrar permanece visível 100% do tempo (única ação essencial). */
.pp-telemed-room__controls {
  position: absolute;
  left: 50%;
  bottom: 24px;
  transform: translateX(-50%);
  z-index: 18;
  display: flex;
  align-items: center;
  gap: 14px;
  padding-bottom: env(safe-area-inset-bottom);
}
.pp-telemed-room__controls-pill {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  background: rgba(2, 2, 2, 0.048);
  border: 1px solid rgba(255, 255, 255, 0.103);
  border-radius: 999px;
  box-shadow: 0 0px 40px rgb(7 16 42 / 29%);
  backdrop-filter: blur(12px);
}
.pp-telemed-room__ctrl {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: #00000071;
  color: #fdfdfd;
  border: 0;
  cursor: pointer;
  transition:
    background 120ms ease,
    color 120ms ease,
    transform 80ms ease;
}
.pp-telemed-room__ctrl:hover {
  background: rgb(39 129 246 / 1);
}
.pp-telemed-room__ctrl:active {
  transform: scale(0.94);
}
.pp-telemed-room__ctrl.off {
  background: #fee2e2;
  color: #b91c1c;
}
.pp-telemed-room__ctrl.off:hover {
  background: #fecaca;
}
.pp-telemed-room__ctrl--active {
  background: #1552f1;
  color: #fff;
}
.pp-telemed-room__ctrl--active:hover {
  background: #0c3fcc;
}
.pp-telemed-room__ctrl--share-on {
  background: rgba(21, 82, 241, 0.12);
  color: #1552f1;
}
.pp-telemed-room__ctrl--share-on:hover {
  background: rgba(21, 82, 241, 0.18);
}
.pp-telemed-room__ctrl-sep {
  display: inline-block;
  width: 1px;
  height: 24px;
  background: rgba(15, 23, 42, 0.12);
  margin: 0 2px;
}

/* 2026-05-22 — Botão de gravação manual (toolbar do doutor) + tooltip
   "balão de gibi" apontando pra ele.
   OFF: SVG <circle> preenchido em vermelho = "iniciar gravação".
   ON:  SVG <rect> preenchido em vermelho + halo pulsante = "REC, parar". */
.pp-telemed-room__rec-wrap {
  position: relative;
  display: inline-flex;
}
.pp-telemed-room__ctrl--rec {
  position: relative;
}
.pp-telemed-room__rec-icon {
  display: block;
  transition: transform 140ms ease, opacity 140ms ease;
}
.pp-telemed-room__ctrl--rec:hover .pp-telemed-room__rec-icon {
  transform: scale(1.08);
}
/* Estado ON: borda + halo de pulso vermelho. O preenchimento do quadrado
   já indica "stop" — o pulse reforça que está GRAVANDO agora. */
.pp-telemed-room__ctrl--rec-on {
  background: rgba(220, 38, 38, 0.12);
  box-shadow: 0 0 0 1px rgba(220, 38, 38, 0.35) inset;
}
.pp-telemed-room__ctrl--rec-on:hover {
  background: rgba(220, 38, 38, 0.18);
}
.pp-telemed-room__rec-icon--on {
  animation: pp-telemed-room__rec-pulse 1.4s ease-in-out infinite;
  border-radius: 4px;
}
@keyframes pp-telemed-room__rec-pulse {
  0%, 100% {
    filter: drop-shadow(0 0 0 rgba(220, 38, 38, 0.6));
  }
  50% {
    filter: drop-shadow(0 0 6px rgba(220, 38, 38, 0.85));
  }
}

/* Spinner overlay enquanto o toggle está em flight. Centralizado sobre
   o ícone — sinaliza "aguarde, mandando comando pro LiveKit". */
.pp-telemed-room__rec-spinner {
  position: absolute;
  inset: 0;
  display: block;
  border: 2px solid rgba(220, 38, 38, 0.25);
  border-top-color: #dc2626;
  border-radius: 50%;
  animation: pp-telemed-room__rec-spin 700ms linear infinite;
  pointer-events: none;
}
@keyframes pp-telemed-room__rec-spin {
  to { transform: rotate(360deg); }
}

/* Badge "● REC · IA" no header. Confirmação visível de que a gravação
   está ATIVA pros dois lados. Pulsa pra chamar atenção mas sem distrair. */
.pp-telemed-room__rec-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px 4px 8px;
  border-radius: 999px;
  background: rgba(220, 38, 38, 0.12);
  border: 1px solid rgba(220, 38, 38, 0.35);
  color: #b91c1c;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.04em;
  line-height: 1;
  user-select: none;
}
.pp-telemed-room__rec-badge-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #dc2626;
  animation: pp-telemed-room__rec-pulse 1.4s ease-in-out infinite;
}
.pp-telemed-room__rec-badge-text {
  letter-spacing: 0.08em;
}
.pp-telemed-room__rec-badge-ai {
  padding: 2px 5px;
  border-radius: 6px;
  background: #dc2626;
  color: #fff;
  font-size: 10px;
  letter-spacing: 0.08em;
}

/* Tooltip "balão de gibi": fundo vermelho, texto branco, com seta apontando
   pra baixo (direção do botão). Posicionado acima do botão. */
.pp-telemed-room__rec-hint {
  position: absolute;
  bottom: calc(100% + 14px);
  left: 50%;
  transform: translateX(-50%);
  background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
  color: #fff;
  padding: 10px 14px;
  border-radius: 14px;
  font-size: 13px;
  font-weight: 600;
  line-height: 1.3;
  white-space: nowrap;
  box-shadow: 0 8px 20px -6px rgba(220, 38, 38, 0.55),
              0 2px 6px rgba(15, 23, 42, 0.15);
  cursor: pointer;
  z-index: 30;
  user-select: none;
}
.pp-telemed-room__rec-hint-text {
  display: block;
}
.pp-telemed-room__rec-hint-tail {
  position: absolute;
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  width: 0;
  height: 0;
  border-left: 8px solid transparent;
  border-right: 8px solid transparent;
  border-top: 8px solid #dc2626;
}
/* Entrada/saída suaves. */
.pp-telemed-room__rec-hint-enter-active,
.pp-telemed-room__rec-hint-leave-active {
  transition: opacity 180ms ease, transform 180ms ease;
}
.pp-telemed-room__rec-hint-enter-from,
.pp-telemed-room__rec-hint-leave-to {
  opacity: 0;
  transform: translate(-50%, 6px);
}

/* Toast de erro ACIMA do botão (mesma posição do balão de gibi) quando
   start/stop falha (consent ausente, participants_not_ready, etc.).
   2026-05-22 — Antes ficava ABAIXO do botão, mas a toolbar vive no
   bottom da tela e o toast caía fora do viewport. Subir resolve. */
.pp-telemed-room__rec-err {
  position: absolute;
  bottom: calc(100% + 14px);
  left: 50%;
  transform: translateX(-50%);
  background: #fff;
  color: #991b1b;
  padding: 10px 14px 10px 12px;
  border-radius: 12px;
  border: 1.5px solid #dc2626;
  font-size: 13px;
  font-weight: 600;
  line-height: 1.35;
  white-space: normal;
  width: max-content;
  max-width: 280px;
  text-align: left;
  z-index: 30;
  box-shadow:
    0 12px 28px -8px rgba(220, 38, 38, 0.35),
    0 2px 6px rgba(15, 23, 42, 0.15);
  display: flex;
  align-items: flex-start;
  gap: 8px;
}
.pp-telemed-room__rec-err::before {
  content: '⚠';
  font-size: 16px;
  line-height: 1.2;
  flex-shrink: 0;
}
.pp-telemed-room__rec-err-enter-active,
.pp-telemed-room__rec-err-leave-active {
  transition: opacity 180ms ease, transform 180ms ease;
}
.pp-telemed-room__rec-err-enter-from,
.pp-telemed-room__rec-err-leave-to {
  opacity: 0;
  transform: translate(-50%, 6px);
}

/* Mobile (toolbar empilhada vertical): tooltip ainda apontando pra cima. */
@media (max-width: 640px) {
  .pp-telemed-room__rec-hint {
    font-size: 12px;
    padding: 8px 12px;
    max-width: 240px;
    white-space: normal;
    text-align: center;
  }
}

/* (Bloco duplicado removido em 2026-05-22 — definições canônicas
   ficam acima, junto com as variações OFF/ON do botão e do tooltip.) */

/* ─── Desfoque de fundo (popover) ─────────────────────────────────────
   Wrapper relativo ao redor do botão pra ancorar o menu. Menu sobe acima
   da toolbar (bottom: 100%) com gap pra não colar no botão. */
.pp-telemed-room__blur-wrap {
  position: relative;
  display: inline-flex;
}
.pp-telemed-room__blur-menu {
  position: absolute;
  bottom: calc(100% + 14px);
  left: 50%;
  transform: translateX(-50%);
  width: 280px;
  padding: 16px;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 14px;
  box-shadow: 0 16px 40px rgba(7, 16, 42, 0.18);
  z-index: 30;
  animation: telemed-blur-menu-in 160ms ease-out;
}
@keyframes telemed-blur-menu-in {
  from {
    opacity: 0;
    transform: translate(-50%, 6px);
  }
  to {
    opacity: 1;
    transform: translate(-50%, 0);
  }
}
.pp-telemed-room__blur-menu-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.pp-telemed-room__blur-menu-title {
  font-size: 14px;
  font-weight: 600;
  color: #1c1b1b;
}
.pp-telemed-room__blur-menu-body {
  margin-top: 14px;
  padding-top: 14px;
  border-top: 1px solid #f1f5f9;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.pp-telemed-room__blur-menu-label {
  display: flex;
  align-items: center;
  justify-content: space-between;
  font-size: 12px;
  font-weight: 600;
  color: #434656;
  letter-spacing: 0.02em;
  text-transform: uppercase;
}
.pp-telemed-room__blur-menu-value {
  font-family: ui-monospace, Menlo, Monaco, monospace;
  font-size: 13px;
  font-weight: 600;
  color: #1552f1;
  letter-spacing: 0;
  text-transform: none;
}
/* Slider — track com fill dinâmico via CSS var (preenchido = Klivy primary
   até o thumb, cinza depois). Thumb grande com aura sutil no hover/active
   pra dar feedback de "arraste". CSS var é atualizada inline no template
   pra refletir blurIntensity em tempo real sem precisar de re-render Vue. */
.pp-telemed-room__blur-slider {
  --telemed-slider-progress: 0%;
  width: 100%;
  height: 6px;
  appearance: none;
  -webkit-appearance: none;
  background: linear-gradient(
    to right,
    #1552f1 0%,
    #1552f1 var(--telemed-slider-progress),
    #e5e7eb var(--telemed-slider-progress),
    #e5e7eb 100%
  );
  border-radius: 999px;
  outline: none;
  cursor: grab;
  transition: background 60ms linear;
}
.pp-telemed-room__blur-slider:active {
  cursor: grabbing;
}

/* WebKit thumb. */
.pp-telemed-room__blur-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  appearance: none;
  width: 18px;
  height: 18px;
  background: #1552f1;
  border: 3px solid #fff;
  border-radius: 50%;
  box-shadow: 0 2px 8px rgba(21, 82, 241, 0.4);
  cursor: grab;
  transition:
    transform 120ms ease,
    box-shadow 120ms ease;
}
.pp-telemed-room__blur-slider::-webkit-slider-thumb:hover {
  transform: scale(1.15);
  box-shadow:
    0 2px 12px rgba(21, 82, 241, 0.45),
    0 0 0 8px rgba(21, 82, 241, 0.12);
}
.pp-telemed-room__blur-slider:active::-webkit-slider-thumb {
  cursor: grabbing;
  transform: scale(1.2);
  box-shadow:
    0 2px 14px rgba(21, 82, 241, 0.5),
    0 0 0 10px rgba(21, 82, 241, 0.18);
}

/* Firefox thumb. */
.pp-telemed-room__blur-slider::-moz-range-thumb {
  width: 18px;
  height: 18px;
  background: #1552f1;
  border: 3px solid #fff;
  border-radius: 50%;
  box-shadow: 0 2px 8px rgba(21, 82, 241, 0.4);
  cursor: grab;
  transition:
    transform 120ms ease,
    box-shadow 120ms ease;
}
.pp-telemed-room__blur-slider::-moz-range-thumb:hover {
  transform: scale(1.15);
  box-shadow:
    0 2px 12px rgba(21, 82, 241, 0.45),
    0 0 0 8px rgba(21, 82, 241, 0.12);
}
.pp-telemed-room__blur-slider:active::-moz-range-thumb {
  cursor: grabbing;
  transform: scale(1.2);
  box-shadow:
    0 2px 14px rgba(21, 82, 241, 0.5),
    0 0 0 10px rgba(21, 82, 241, 0.18);
}
.pp-telemed-room__blur-slider::-moz-range-track {
  background: transparent;
}
.pp-telemed-room__blur-slider-ticks {
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  color: #94a3b8;
  font-weight: 500;
}
.pp-telemed-room__blur-menu-hint {
  margin: 14px 0 0;
  font-size: 11px;
  line-height: 1.4;
  color: #94a3b8;
}
.pp-telemed-room__leave {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 12px 22px;
  background: #dc2626;
  color: #fff;
  border: 0;
  border-radius: 999px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  box-shadow: 0 10px 30px rgba(220, 38, 38, 0.32);
  transition:
    background 120ms ease,
    transform 80ms ease;
}
.pp-telemed-room__leave:hover {
  background: #b91c1c;
}
.pp-telemed-room__leave:active {
  transform: scale(0.97);
}
.pp-telemed-room__badge {
  position: absolute;
  top: -2px;
  right: -2px;
  min-width: 14px;
  height: 14px;
  padding: 0 4px;
  background: #ef4444;
  color: #fff;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 700;
  border: 2px solid #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

/* Mobile — toolbar diminui, PIP encolhe, header esconde detalhes. */
@media (max-width: 640px) {
  .pp-telemed-room__controls {
    bottom: 16px;
    gap: 8px;
  }
  .pp-telemed-room__controls-pill {
    padding: 8px 10px;
    gap: 6px;
  }
  .pp-telemed-room__ctrl {
    width: 40px;
    height: 40px;
  }
  .pp-telemed-room__leave {
    padding: 10px 16px;
    font-size: 13px;
  }
  .pp-telemed-room__leave span {
    display: none;
  }
  .pp-telemed-room__local {
    width: 130px;
    height: 90px;
    bottom: 96px;
    right: 16px;
  }
  .pp-telemed-room__header {
    padding: 12px 16px;
  }
  .pp-telemed-room__participant {
    max-width: 120px;
    font-size: 13px;
  }
  .pp-telemed-room__brand {
    font-size: 16px;
  }
  .pp-telemed-room__code,
  .pp-telemed-room__conn {
    display: none;
  }
}

/* ─── Preflight (Pré-consulta) ─────────────────────────────────────────
   Tela cheia clara. Split horizontal: preview à esquerda (3/5), painel de
   configuração à direita (2/5). Mobile empilha vertical. */
.pp-telemed-preflight {
  position: fixed;
  inset: 0;
  background: #f6f3f2;
  overflow-y: auto;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 32px 24px;
  z-index: 1000;
  color: #1c1b1b;
}
.pp-telemed-preflight__shell {
  width: 100%;
  max-width: 1180px;
  display: grid;
  grid-template-columns: minmax(0, 3fr) minmax(360px, 2fr);
  gap: 64px;
  align-items: center;
}

.pp-telemed-preflight__preview-col {
  width: 100%;
}

.pp-telemed-preflight__preview {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  background: #121a34;
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 4px 20px rgba(7, 16, 42, 0.08);
}
.pp-telemed-preflight__preview--off {
  background: #1e293b;
}
.pp-telemed-preflight__video {
  width: 100%;
  height: 100%;
  object-fit: cover;
  transition: opacity 200ms ease;
}
.pp-telemed-preflight__video--mirror {
  transform: scaleX(-1);
}
.pp-telemed-preflight__video--hidden {
  visibility: hidden;
}
.pp-telemed-preflight__camoff {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 14px;
  background: #1e293b;
  color: #cbd5e1;
}
.pp-telemed-preflight__camoff p {
  margin: 0;
  font-size: 14px;
  font-weight: 500;
}
.pp-telemed-preflight__quality {
  position: absolute;
  top: 14px;
  right: 14px;
  padding: 4px 12px;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  backdrop-filter: blur(6px);
}

/* Toggles flutuantes sobre o preview — glassmorphism translúcido branco;
   estado off vira vermelho saturado pra sinalizar bloqueio claro. */
.pp-telemed-preflight__overlay-controls {
  position: absolute;
  bottom: 20px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  gap: 16px;
  z-index: 2;
}
.pp-telemed-preflight__ctrl {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 48px;
  height: 48px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.2);
  border: 1px solid rgba(255, 255, 255, 0.3);
  color: #fff;
  cursor: pointer;
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  transition:
    background 160ms ease,
    color 160ms ease,
    transform 100ms ease,
    border-color 160ms ease;
}
.pp-telemed-preflight__ctrl:hover {
  background: rgba(255, 255, 255, 0.3);
  transform: scale(1.05);
}
.pp-telemed-preflight__ctrl:active {
  transform: scale(0.95);
}
.pp-telemed-preflight__ctrl--off {
  background: rgba(186, 26, 26, 0.92);
  border-color: rgba(186, 26, 26, 0.55);
  color: #fff;
}
.pp-telemed-preflight__ctrl--off:hover {
  background: rgba(186, 26, 26, 1);
}

/* ─── Painel de configuração (direita) ──────────────────────────────── */
.pp-telemed-preflight__panel {
  width: 100%;
  max-width: 460px;
  display: flex;
  flex-direction: column;
  gap: 28px;
  justify-self: start;
}

.pp-telemed-preflight__header {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.pp-telemed-preflight__title {
  margin: 0;
  font-size: 28px;
  font-weight: 700;
  letter-spacing: -0.01em;
  color: #1c1b1b;
  line-height: 1.2;
}
.pp-telemed-preflight__subtitle {
  margin: 0;
  font-size: 14px;
  line-height: 1.5;
  color: #64748b;
}
.pp-telemed-preflight__code {
  margin: 4px 0 0;
  font-size: 12px;
  color: #64748b;
}
.pp-telemed-preflight__code strong {
  font-family: ui-monospace, Menlo, Monaco, monospace;
  letter-spacing: 0.4px;
  color: #1c1b1b;
}

.pp-telemed-preflight__error {
  position: relative;
  top: auto;
  left: auto;
  transform: none;
  max-width: 100%;
  border-radius: 12px;
}

.pp-telemed-preflight__fields {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* Card de segurança / consent — destaque visual leve em branco. */
.pp-telemed-preflight__security {
  padding: 18px 20px;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 14px;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.03);
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.pp-telemed-preflight__security-title {
  margin: 0;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: #1c1b1b;
}
.pp-telemed-preflight__security-title :deep(svg) {
  color: #1552f1;
}
.pp-telemed-preflight__consent {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  cursor: pointer;
  margin: 0;
  padding: 0;
  background: transparent;
  border: 0;
}
.pp-telemed-preflight__consent-checkbox {
  flex-shrink: 0;
  width: 20px;
  height: 20px;
  margin-top: 2px;
  accent-color: #1552f1;
  cursor: pointer;
}
.pp-telemed-preflight__consent-text {
  font-size: 14px;
  line-height: 1.5;
  color: #434656;
}
.pp-telemed-preflight__consent-text a {
  color: #1552f1;
  font-weight: 600;
  text-decoration: none;
}
.pp-telemed-preflight__consent-text a:hover {
  text-decoration: underline;
}

.pp-telemed-preflight__actions {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.pp-telemed-preflight__enter {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  padding: 16px 24px;
  background: #1552f1;
  color: #fff;
  border: 0;
  border-radius: 14px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  box-shadow: 0 4px 14px rgba(21, 82, 241, 0.25);
  transition:
    background 160ms ease,
    box-shadow 160ms ease,
    transform 100ms ease;
}
.pp-telemed-preflight__enter:hover:not(:disabled) {
  background: #0c3fcc;
  box-shadow: 0 6px 20px rgba(21, 82, 241, 0.32);
}
.pp-telemed-preflight__enter:hover:not(:disabled) svg {
  transform: translateX(2px);
}
.pp-telemed-preflight__enter:active:not(:disabled) {
  transform: scale(0.99);
}
.pp-telemed-preflight__enter svg {
  transition: transform 160ms ease;
}
.pp-telemed-preflight__enter:disabled {
  background: #cbd5e1;
  color: #fff;
  cursor: not-allowed;
  box-shadow: none;
}
.pp-telemed-preflight__cancel {
  width: 100%;
  padding: 12px 24px;
  background: transparent;
  color: #64748b;
  border: 0;
  border-radius: 14px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-telemed-preflight__cancel:hover {
  background: rgba(15, 23, 42, 0.04);
  color: #1c1b1b;
}

/* Tablet & mobile — empilha vertical, preview encolhe pra caber. */
@media (max-width: 960px) {
  .pp-telemed-preflight__shell {
    grid-template-columns: 1fr;
    gap: 32px;
    align-items: start;
  }
  .pp-telemed-preflight__panel {
    max-width: 100%;
  }
}
@media (max-width: 640px) {
  .pp-telemed-preflight {
    padding: 16px;
  }
  .pp-telemed-preflight__shell {
    gap: 24px;
  }
  .pp-telemed-preflight__title {
    font-size: 24px;
  }
  .pp-telemed-preflight__overlay-controls {
    bottom: 14px;
    gap: 12px;
  }
  .pp-telemed-preflight__ctrl {
    width: 42px;
    height: 42px;
  }
  .pp-telemed-preflight__security {
    padding: 16px;
  }
  .pp-telemed-preflight__enter {
    padding: 14px 20px;
    font-size: 15px;
  }
}

.pp-telemed-consent-modal {
  position: fixed;
  inset: 0;
  z-index: 200;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
}
.pp-telemed-consent-modal__box {
  background: white;
  color: #222;
  padding: 24px;
  border-radius: 8px;
  max-width: 560px;
  max-height: 80vh;
  overflow-y: auto;
  font-size: 14px;
  line-height: 1.5;
}
.pp-telemed-consent-modal__box h3 {
  margin-top: 0;
  font-size: 18px;
}
.pp-telemed-consent-modal__body p {
  margin: 8px 0;
}
.pp-telemed-consent-modal__box .pp-telemed-preflight__enter {
  margin-top: 12px;
  background: #2563eb;
  color: white;
  padding: 8px 16px;
  border-radius: 6px;
  border: 0;
  cursor: pointer;
}
</style>
