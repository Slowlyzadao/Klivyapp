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
  createLocalVideoTrack,
  createLocalAudioTrack,
} from 'livekit-client';
import IconMic from '@plugins/patient_portal/frontend/components/icons/IconMic.vue';
import IconMicOff from '@plugins/patient_portal/frontend/components/icons/IconMicOff.vue';
import IconVideo from '@plugins/patient_portal/frontend/components/icons/IconVideo.vue';
import IconVideoOff from '@plugins/patient_portal/frontend/components/icons/IconVideoOff.vue';
import IconPhoneHangup from '@plugins/patient_portal/frontend/components/icons/IconPhoneHangup.vue';
import IconScreenShare from '@plugins/patient_portal/frontend/components/icons/IconScreenShare.vue';
import IconSwitchCamera from '@plugins/patient_portal/frontend/components/icons/IconSwitchCamera.vue';
import IconMessage from '@plugins/patient_portal/frontend/components/icons/IconMessage.vue';
import IconClose from '@plugins/patient_portal/frontend/components/icons/IconClose.vue';
import IconClock from '@plugins/patient_portal/frontend/components/icons/IconClock.vue';
import IconChevronLeft from '@plugins/patient_portal/frontend/components/icons/IconChevronLeft.vue';
import IconChatBubble from '@plugins/patient_portal/frontend/components/icons/IconChatBubble.vue';

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
});
// 'sessionEvent' (Sprint K — automação de status):
//   - { kind: 'joined' } — emitido UMA vez quando o local participant
//     conecta ao Room (após publishLocalTracks). Wrapper chama API
//     /telemedicine_event { kind: 'joined' }.
//   - { kind: 'left' } — emitido UMA vez quando sai (RoomEvent.Disconnected
//     ou clique em "Sair"). Idempotência via emitSessionEventOnce.
// Nome camelCase exigido pelo lint vue/custom-event-name-casing (Vue 3
// convention); template pode escutar via @session-event ou @sessionEvent.
const emit = defineEmits(['leave', 'sessionEvent']);

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
const recordingConsent = ref(false);
const showConsentTerms = ref(false);

// ─── Pre-flight (lobby antes de entrar na sala, Google Meet pattern) ──
// Lista de devices disponíveis + qual está selecionado. Populados em
// `setupPreflight()` via `Room.getLocalDevices`.
const audioInputs = ref([]);
const videoInputs = ref([]);
const selectedVideoDevice = ref('');
const selectedAudioDevice = ref('');
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

// Google Meet pattern: host (doutor) controla se participantes podem mandar
// mensagem. Quando off, paciente vê input desabilitado e mensagem
// explicativa. Doutor sempre pode mandar (ele É o host). Sincroniza via
// data channel `{type:'chat_lock', enabled:<bool>}` broadcast.
// Default true — chat aberto pra todos, doutor desativa se quiser.
const chatAllowed = ref(true);

const activeSpeaker = ref('');
const screenOn = ref(false);
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
function onRoomDisconnected() {
  state.value = 'disconnected';
  // Reporta saída PRA automação. Idempotente — se já mandamos no botão
  // Sair, esta chamada vira no-op.
  emitSessionLeft();
  emitLeaveOnce();
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
      videoCaptureDefaults: { resolution: VideoPresets.h1080.resolution },
      publishDefaults: {
        videoSimulcastLayers: [VideoPresets.h180, VideoPresets.h360],
        videoEncoding: VideoPresets.h1080.encoding,
        videoCodec: 'vp8',
      },
      audioCaptureDefaults: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
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
      [RoomEvent.DataReceived, handleData],
      [RoomEvent.ActiveSpeakersChanged, onActiveSpeakers],
      [RoomEvent.ParticipantConnected, onParticipantConnected],
      [RoomEvent.ParticipantDisconnected, onParticipantDisconnected],
      // Disconnected pode vir de 2 origens:
      //   (a) usuário clicou Sair (já emitimos no leave())
      //   (b) servidor encerrou (kick, network drop, room fechado)
      [RoomEvent.Disconnected, onRoomDisconnected],
    ];
    roomListeners.forEach(([event, handler]) => room.on(event, handler));

    await room.connect(props.url, props.token);
    state.value = 'connected';

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
    for (const p of room.remoteParticipants.values()) {
      addRemote(p);
      if (isDoctor.value) registerPendingIfPatient(p);
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
async function publishLocalTracks() {
  if (!room) return;
  if (!checkSecureContext()) return;
  let captured = false;
  // Respeita micOn/camOn (usuário pode ter desligado no preflight) e o
  // deviceId selecionado (segundo parâmetro do setXxxEnabled aceita opções
  // de captura). Sem isso, paciente que escolheu "Webcam USB" no preflight
  // entraria com a câmera built-in.
  const audioOpts = selectedAudioDevice.value
    ? { deviceId: selectedAudioDevice.value }
    : undefined;
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
async function createPreviewTracks() {
  if (!checkSecureContext()) return;
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
  } catch (err) {
    console.warn('[telemed] preview camera falhou:', err);
    camOn.value = false;
    mediaError.value = mapMediaError(err);
    captured = true;
  }
  try {
    previewAudioTrack = await createLocalAudioTrack({
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
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

  // Respeita o estado micOn/camOn que o paciente deixou no waiting room
  // (se desligou o mic enquanto esperava, ele segue desligado depois).
  try {
    await room.localParticipant.setMicrophoneEnabled(micOn.value);
  } catch (err) {
    console.warn('[telemed] applyAdmit mic publish falhou:', err);
  }
  try {
    await room.localParticipant.setCameraEnabled(camOn.value);
  } catch (err) {
    console.warn('[telemed] applyAdmit cam publish falhou:', err);
  }
}

// Doutor — registra remote participant como pendente se for identity patient-*.
function registerPendingIfPatient(participant) {
  if (!isDoctor.value) return;
  const id = participant?.identity;
  if (!id || !id.startsWith('patient-')) return;
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

function onParticipantConnected(participant) {
  addRemote(participant);
  registerPendingIfPatient(participant);
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
  remoteParticipants.value = [
    ...remoteParticipants.value,
    {
      id,
      name: participant.name || participant.identity || 'Participante',
      hasVideo: false,
      hasAudio: false,
      micEnabled: false,
      speaking: false,
    },
  ];
}

function removeRemote(identity) {
  remoteParticipants.value = remoteParticipants.value.filter(
    p => p.id !== identity
  );
  const binding = videoBindings.get(identity);
  if (binding?.videoTrack) {
    try {
      binding.videoTrack.detach();
    } catch (_) {}
  }
  videoBindings.delete(identity);
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

// Doutor clicou "Admitir" pra um paciente específico — envia data channel
// com destinationIdentities pra esse identity (não vaza pra outros pacientes).
async function admitPatient(identity) {
  if (!room || !isDoctor.value) return;
  try {
    const payload = encoder.encode(
      JSON.stringify({ type: 'admit', target: identity })
    );
    await room.localParticipant.publishData(payload, {
      reliable: true,
      destinationIdentities: [identity],
    });
    unregisterPending(identity);
  } catch (err) {
    console.error('[telemed] admit falhou:', err);
  }
}

function attachLocalCamera(publication) {
  if (publication.kind !== Track.Kind.Video) return;
  // Captura facingMode no momento da publicação. Em desktop costuma vir
  // undefined — manter o default 'user' (mirror ON, padrão de webcam).
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
  if (publication.kind !== Track.Kind.Video) return;
  publication.track?.detach();
}

// Trata novo track de um remote. Em vez de criar element imperativamente,
// guardamos o track no binding por identity. O <video> declarativo do
// template (v-for nos tiles) chama bindRemoteVideo() quando o ref é
// definido, aí o anexamos.
function attachRemote(track, publication, participant) {
  if (track.kind !== Track.Kind.Audio && track.kind !== Track.Kind.Video)
    return;

  // Garante que o tile existe (defesa caso ParticipantConnected tenha
  // chegado depois — não deveria, mas custa pouco).
  addRemote(participant);

  if (track.kind === Track.Kind.Video) {
    if (publication?.setVideoQuality) {
      try {
        publication.setVideoQuality(VideoQuality.HIGH);
      } catch (_) {
        /* não-fatal */
      }
    }
    const id = participant.identity;
    const entry = videoBindings.get(id) || {};
    entry.videoTrack = track;
    videoBindings.set(id, entry);
    if (entry.el) {
      try {
        track.attach(entry.el);
        entry.el.play?.().catch(() => {});
      } catch (_) {}
    }
    updateRemote(id, { hasVideo: true });

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
    audioEl.style.display = 'none';
    document.body.appendChild(audioEl);
    const id = participant.identity;
    const entry = videoBindings.get(id) || {};
    if (!entry.audioElements) entry.audioElements = new Map();
    entry.audioElements.set(track.sid, audioEl);
    videoBindings.set(id, entry);
    updateRemote(id, { hasAudio: true });
  }
}

function detachRemote(track, publication, participant) {
  const id = participant?.identity;
  if (!id) return;
  const entry = videoBindings.get(id);
  if (!entry) return;

  if (track.kind === Track.Kind.Video && entry.videoTrack === track) {
    try {
      track.detach();
    } catch (_) {}
    entry.videoTrack = null;
    videoBindings.set(id, entry);
    updateRemote(id, { hasVideo: false });
  } else if (track.kind === Track.Kind.Audio) {
    const el = entry.audioElements?.get(track.sid);
    if (el) {
      try {
        track.detach();
      } catch (_) {}
      el.remove();
      entry.audioElements.delete(track.sid);
    }
    updateRemote(id, { hasAudio: (entry.audioElements?.size || 0) > 0 });
  }
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
    }
  } catch (e) {
    console.warn('[telemed] data inválido:', e);
  }
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

async function toggleCam() {
  if (!room) return;
  camOn.value = !camOn.value;
  try {
    if (admitted.value) {
      await room.localParticipant.setCameraEnabled(camOn.value);
    } else if (previewVideoTrack) {
      if (camOn.value) await previewVideoTrack.unmute();
      else await previewVideoTrack.mute();
    }
  } catch (e) {
    console.warn('[telemed] toggleCam falhou:', e);
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
    videoDevices.value = videoInputs.value;
    hasMultipleCameras.value = videoInputs.value.length > 1;
    if (!selectedVideoDevice.value && videoInputs.value[0]) {
      selectedVideoDevice.value = videoInputs.value[0].deviceId;
    }
    if (!selectedAudioDevice.value && audioInputs.value[0]) {
      selectedAudioDevice.value = audioInputs.value[0].deviceId;
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
        resolution: VideoPresets.h1080.resolution,
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
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
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
  // Limpa audio elements anexados ao body — sem isso ficam órfãos tocando
  // após sair da sala (raro mas observado em refresh rápido).
  videoBindings.forEach(entry => {
    entry.audioElements?.forEach(el => {
      try {
        el.remove();
      } catch (_) {}
    });
  });
  videoBindings.clear();
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
    <!-- Preflight (Google Meet lobby): preview da câmera, dropdowns de
         dispositivos, label de resolução, controles mic/cam. Acontece
         ANTES do `connect()` — ninguém entra na sala sem confirmar. -->
    <div v-if="state === 'preflight'" class="pp-telemed-preflight">
      <div class="pp-telemed-preflight__preview">
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
            :class="{ off: !micOn }"
            :title="micOn ? 'Silenciar' : 'Ativar microfone'"
            type="button"
            @click="togglePreflightMic"
          >
            <IconMic v-if="micOn" :size="20" />
            <IconMicOff v-else :size="20" />
          </button>
          <button
            class="pp-telemed-preflight__ctrl"
            :class="{ off: !camOn }"
            :title="camOn ? 'Desligar câmera' : 'Ligar câmera'"
            type="button"
            @click="togglePreflightCam"
          >
            <IconVideo v-if="camOn" :size="20" />
            <IconVideoOff v-else :size="20" />
          </button>
        </div>
      </div>

      <div class="pp-telemed-preflight__panel">
        <h2 class="pp-telemed-preflight__title">Pronto para entrar?</h2>
        <p v-if="roomCode" class="pp-telemed-preflight__code">
          Código da sala: <strong>{{ roomCode }}</strong>
        </p>

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

        <label class="pp-telemed-preflight__row">
          <span class="pp-telemed-preflight__row-label">
            <IconMic :size="16" />
            Microfone
          </span>
          <select
            class="pp-telemed-preflight__select"
            :value="selectedAudioDevice"
            :disabled="audioInputs.length === 0"
            @change="changeAudioDevice($event.target.value)"
          >
            <option v-if="audioInputs.length === 0" value="">
              Nenhum microfone encontrado
            </option>
            <option
              v-for="d in audioInputs"
              :key="d.deviceId"
              :value="d.deviceId"
            >
              {{ d.label || 'Microfone padrão' }}
            </option>
          </select>
        </label>

        <label class="pp-telemed-preflight__row">
          <span class="pp-telemed-preflight__row-label">
            <IconVideo :size="16" />
            Câmera
          </span>
          <select
            class="pp-telemed-preflight__select"
            :value="selectedVideoDevice"
            :disabled="videoInputs.length === 0"
            @change="changeVideoDevice($event.target.value)"
          >
            <option v-if="videoInputs.length === 0" value="">
              Nenhuma câmera encontrada
            </option>
            <option
              v-for="d in videoInputs"
              :key="d.deviceId"
              :value="d.deviceId"
            >
              {{ d.label || 'Câmera padrão' }}
            </option>
          </select>
        </label>

        <!-- Sprint L — Consent obrigatório de gravação (LGPD/CFM 2.314) -->
        <label class="pp-telemed-preflight__consent">
          <input
            v-model="recordingConsent"
            type="checkbox"
            class="pp-telemed-preflight__consent-checkbox"
          />
          <span class="pp-telemed-preflight__consent-text">
            Aceito que o <strong>áudio</strong> desta consulta seja gravado para
            fins de prontuário e compliance, conforme
            <a href="#" @click.prevent="showConsentTerms = true">termos LGPD e CFM 2.314/2022</a>.
          </span>
        </label>

        <div class="pp-telemed-preflight__actions">
          <button
            class="pp-telemed-preflight__cancel"
            type="button"
            @click="leave"
          >
            Cancelar
          </button>
          <button
            class="pp-telemed-preflight__enter"
            type="button"
            :disabled="(mediaError && mediaError.type === 'insecure') || !recordingConsent"
            @click="enterRoom"
          >
            Entrar agora
          </button>
        </div>
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
            conversa entre você e o(a) profissional. Não será gravada imagem
            de vídeo.
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
            (tipicamente as 15 consultas mais recentes). Após esse período,
            o áudio é excluído permanentemente.
          </p>
          <p>
            <strong>4. Retenção da evolução clínica:</strong> A evolução
            escrita gerada a partir do áudio (prontuário) é preservada por
            <strong>20 anos</strong>, conforme exigência do CFM, mesmo após
            o áudio ser excluído.
          </p>
          <p>
            <strong>5. Seus direitos:</strong> Você pode solicitar a exclusão
            antecipada do áudio a qualquer momento, sem prejuízo do
            atendimento. Atos clínicos já registrados na evolução não são
            afetados pela revogação.
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

    <template v-else-if="state === 'connected' || state === 'disconnected'">
      <!-- Header CLARO (Google Meet pattern). Fundo branco, texto escuro,
           shadow discreta. Coerente com o resto do portal do paciente.
           Sob o título, "Código: pppp-eeee-aaaa" pra paciente ler/copiar. -->
      <header class="pp-telemed-room__header">
        <button
          class="pp-telemed-room__back"
          aria-label="Voltar"
          @click="leave"
        >
          <IconChevronLeft :size="18" />
        </button>
        <div class="pp-telemed-room__head-text">
          <div class="pp-telemed-room__title">{{ headerTitle }}</div>
          <div v-if="roomCode" class="pp-telemed-room__code" :title="roomCode">
            {{ roomCode }}
          </div>
        </div>
        <div v-if="devMode" class="pp-telemed-room__dev">DEV</div>
      </header>

      <!-- Body: stage (vídeo, fundo escuro) + chat sidebar opcional.
           Quando chat abre, o stage comprime à esquerda — igual Google Meet.
           Antes era um <aside> position:absolute em cima do vídeo (pop-up). -->
      <div class="pp-telemed-room__body">
        <main class="pp-telemed-room__main">
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

          <div class="pp-telemed-room__stage">
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
                :class="{ 'pp-telemed-room__tile--speaking': p.speaking }"
              >
                <video
                  :ref="el => bindRemoteVideo(p.id, el)"
                  autoplay
                  playsinline
                  class="pp-telemed-room__tile-video"
                  :class="{
                    'pp-telemed-room__tile-video--hidden': !p.hasVideo,
                  }"
                />
                <div
                  v-if="!p.hasVideo"
                  class="pp-telemed-room__avatar"
                  :style="{ background: avatarColor(p.name) }"
                >
                  {{ initial(p.name) }}
                </div>
                <div class="pp-telemed-room__tile-name">
                  <IconMicOff
                    v-if="!p.hasAudio"
                    :size="12"
                    class="pp-telemed-room__tile-mic-off"
                  />
                  <span>{{ p.name }}</span>
                </div>
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

            <!-- Banner do doutor — pacientes aguardando admissão. -->
            <div
              v-if="isDoctor && pendingPatients.size > 0"
              class="pp-telemed-room__admit-banner"
            >
              <div class="pp-telemed-room__admit-banner-head">
                <IconClock
                  :size="16"
                  class="pp-telemed-room__admit-banner-icon"
                />
                <strong>
                  {{ pendingPatients.size }}
                  {{
                    pendingPatients.size === 1
                      ? 'paciente quer entrar'
                      : 'pacientes querem entrar'
                  }}
                </strong>
              </div>
              <div class="pp-telemed-room__admit-banner-list">
                <div
                  v-for="[identity, info] in pendingPatients"
                  :key="identity"
                  class="pp-telemed-room__admit-banner-row"
                >
                  <span class="pp-telemed-room__admit-banner-name">
                    {{ info.name }}
                  </span>
                  <button
                    class="pp-telemed-room__admit-btn"
                    @click="admitPatient(identity)"
                  >
                    Admitir
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
                 border azul + glow quando eu estiver falando. -->
            <div
              class="pp-telemed-room__local"
              :class="{
                'pp-telemed-room__local--off': !camOn,
                'pp-telemed-room__local--mirror':
                  cameraFacing !== 'environment',
                'pp-telemed-room__local--speaking': localSpeaking,
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
            </div>
          </div>
        </main>

        <!-- Chat sidebar (Google Meet pattern). Fica ao lado do vídeo,
             comprimindo a área de stream. Empty state com SVG quando não
             há mensagens. Toggle "permitir participantes" só pro doutor. -->
        <aside v-if="chatOpen" class="pp-telemed-room__chat">
          <header class="pp-telemed-room__chat-head">
            <strong>Mensagens na chamada</strong>
            <button
              class="pp-telemed-room__chat-close"
              aria-label="Fechar chat"
              @click="chatOpen = false"
            >
              <IconClose :size="18" />
            </button>
          </header>

          <!-- Host control: doutor decide se pacientes podem mandar.
               Switch visual (label + pill). Quando off, todos os pacientes
               recebem chat_lock via data channel e input deles fica disabled. -->
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

          <!-- Aviso pro PACIENTE quando o doutor desligou o chat. -->
          <div
            v-if="!isDoctor && !chatAllowed"
            class="pp-telemed-room__chat-locked"
          >
            <IconMessage :size="16" />
            <span>O host desativou as mensagens.</span>
          </div>

          <div ref="chatList" class="pp-telemed-room__chat-list">
            <!-- Empty state (Google Meet pattern). Ícone grande em cinza +
                 texto explicativo. Substitui a lista vazia "branca". -->
            <div
              v-if="messages.length === 0"
              class="pp-telemed-room__chat-empty"
            >
              <div class="pp-telemed-room__chat-empty-icon">
                <IconChatBubble :size="56" />
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
              class="pp-telemed-room__chat-msg"
              :class="{ 'pp-telemed-room__chat-msg--mine': m.fromMe }"
            >
              <div class="pp-telemed-room__chat-author">
                {{ m.fromMe ? 'Você' : m.author }}
              </div>
              <div class="pp-telemed-room__chat-text">{{ m.text }}</div>
            </div>
          </div>
          <form class="pp-telemed-room__chat-form" @submit.prevent="sendChat">
            <input
              v-model="chatInput"
              type="text"
              :placeholder="
                !isDoctor && !chatAllowed
                  ? 'Mensagens desativadas pelo host'
                  : 'Enviar uma mensagem'
              "
              maxlength="500"
              :disabled="!isDoctor && !chatAllowed"
            />
            <button
              type="submit"
              :disabled="!chatInput.trim() || (!isDoctor && !chatAllowed)"
            >
              Enviar
            </button>
          </form>
        </aside>
      </div>

      <!-- Footer CLARO. Botões em cinza claro (off: vermelho discreto).
           Botão Sair mantém vermelho saturado (ação destrutiva). -->
      <footer class="pp-telemed-room__controls">
        <button
          class="pp-telemed-room__ctrl"
          :class="{ off: !micOn }"
          :title="micOn ? 'Silenciar' : 'Ativar microfone'"
          @click="toggleMic"
        >
          <IconMic v-if="micOn" :size="22" />
          <IconMicOff v-else :size="22" />
        </button>
        <button
          class="pp-telemed-room__ctrl"
          :class="{ off: !camOn }"
          :title="camOn ? 'Desligar câmera' : 'Ligar câmera'"
          @click="toggleCam"
        >
          <IconVideo v-if="camOn" :size="22" />
          <IconVideoOff v-else :size="22" />
        </button>
        <button
          v-if="hasMultipleCameras && isMobile"
          class="pp-telemed-room__ctrl"
          title="Trocar câmera"
          @click="switchCamera"
        >
          <IconSwitchCamera :size="22" />
        </button>
        <button
          class="pp-telemed-room__ctrl"
          :class="{ off: screenOn }"
          :title="screenOn ? 'Parar compartilhamento' : 'Compartilhar tela'"
          @click="toggleScreen"
        >
          <IconScreenShare :size="22" />
        </button>
        <button
          class="pp-telemed-room__ctrl"
          :class="{ 'pp-telemed-room__ctrl--active': chatOpen }"
          title="Chat"
          @click="chatOpen = !chatOpen"
        >
          <IconMessage :size="22" />
          <span v-if="unreadChat" class="pp-telemed-room__badge">
            {{ unreadChat }}
          </span>
        </button>
        <button
          class="pp-telemed-room__ctrl pp-telemed-room__ctrl--leave"
          title="Sair da consulta"
          @click="leave"
        >
          <IconPhoneHangup :size="20" />
          <span>Sair</span>
        </button>
      </footer>
    </template>
  </div>
</template>

<style scoped>
/* ─── Root ────────────────────────────────────────────────────────────
   Google Meet pattern: header/footer claros (#fff), stage central preto
   (pra valorizar o vídeo). Grid de 3 linhas garante que footer não suba
   sobre o vídeo e header não invada o stage. */
.pp-telemed-room {
  position: fixed;
  inset: 0;
  background: #f8fafc;
  color: #0f172a;
  display: grid;
  grid-template-rows: auto 1fr auto;
  z-index: 1000;
}

/* Overlay de loading/erro — light. Antes era dark; alinha com o portal. */
.pp-telemed-room__overlay {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 16px;
  background: rgba(248, 250, 252, 0.96);
  z-index: 2;
}
.pp-telemed-room__spinner {
  width: 36px;
  height: 36px;
  border: 3px solid rgba(37, 99, 235, 0.15);
  border-top-color: #2563eb;
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
  color: #475569;
}
.pp-telemed-room__status--error {
  color: #b91c1c;
  max-width: 80%;
  text-align: center;
}
.pp-telemed-room__btn {
  margin-top: 12px;
  padding: 10px 20px;
  background: #2563eb;
  color: #fff;
  border: 0;
  border-radius: 10px;
  font-weight: 600;
  cursor: pointer;
}

/* ─── Header ──────────────────────────────────────────────────────────
   Branco, texto escuro, shadow discreta. Botão voltar agora cinza claro
   (não translúcido sobre dark). */
.pp-telemed-room__header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  background: #fff;
  border-bottom: 1px solid #e5e7eb;
  z-index: 1;
}
.pp-telemed-room__back {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: #f1f5f9;
  border: 0;
  color: #334155;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-telemed-room__back:hover {
  background: #e2e8f0;
}
.pp-telemed-room__head-text {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.pp-telemed-room__title {
  font-size: 14px;
  font-weight: 600;
  color: #0f172a;
  line-height: 1.2;
}
/* Código da sala estilo Google Meet (tkt-vxoc-drv). Monospace pra ressaltar
   formato; cor cinza pra não competir com o título. */
.pp-telemed-room__code {
  margin-top: 2px;
  font-family: ui-monospace, Menlo, Monaco, monospace;
  font-size: 11px;
  font-weight: 500;
  color: #64748b;
  letter-spacing: 0.6px;
}
.pp-telemed-room__dev {
  font-size: 10px;
  font-weight: 700;
  background: #fbbf24;
  color: #422006;
  padding: 3px 8px;
  border-radius: 999px;
}

/* ─── Body (split horizontal: stage | chat) ──────────────────────────
   Grid 2-col: vídeo expande, chat ocupa 360px à direita quando aberto.
   Antes o chat era position:absolute em cima do stage (pop-up). */
.pp-telemed-room__body {
  display: grid;
  grid-template-columns: 1fr auto;
  min-height: 0; /* Permite o filho com overflow scroll funcionar. */
}
.pp-telemed-room__main {
  position: relative;
  min-width: 0;
  display: flex;
  flex-direction: column;
  background: #e2e8f0;
}

.pp-telemed-room__stage {
  flex: 1;
  position: relative;
  overflow: hidden;
}
/* Tiles dos participantes remotos (Google Meet pattern). Stack absoluto
   pra preencher o stage. Grid 1, 2x1 ou 2x2 dependendo do número de
   participantes. Cada tile tem fundo escuro próprio (#1e293b) — quando
   sem vídeo, vê-se o avatar. */
.pp-telemed-room__tiles {
  position: absolute;
  inset: 0;
  display: grid;
  gap: 8px;
  padding: 8px;
  grid-template-columns: 1fr;
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
  background: #1e293b;
  border-radius: 12px;
  overflow: hidden;
  border: 3px solid transparent;
  transition:
    border-color 160ms ease,
    box-shadow 160ms ease;
}
/* Active speaker — border azul + glow externo. Igual Meet. */
.pp-telemed-room__tile--speaking {
  border-color: #3b82f6;
  box-shadow: 0 0 0 4px rgba(59, 130, 246, 0.25);
}
.pp-telemed-room__tile-video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.pp-telemed-room__tile-video--hidden {
  display: none;
}
.pp-telemed-room__tile-name {
  position: absolute;
  left: 12px;
  bottom: 10px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 500;
  backdrop-filter: blur(4px);
}
.pp-telemed-room__tile-mic-off {
  color: #f87171;
}

/* Avatar com inicial (em vez de vídeo). Cor estável por nome via
   avatarColor(). Tamanho responsivo via min(20vw, 120px). */
.pp-telemed-room__avatar {
  display: flex;
  align-items: center;
  justify-content: center;
  width: min(20vw, 120px);
  height: min(20vw, 120px);
  border-radius: 50%;
  font-size: min(8vw, 48px);
  font-weight: 600;
  color: #fff;
  letter-spacing: 0.5px;
  user-select: none;
}
.pp-telemed-room__avatar--pip {
  width: 56px;
  height: 56px;
  font-size: 22px;
}
.pp-telemed-room__remote :deep(.pp-telemed-room__remote-el) {
  max-width: 100%;
  max-height: 100%;
  width: 100%;
  height: 100%;
  object-fit: cover;
}
/* Waiting state — texto/ícone em cinza médio pra contrastar com slate-200
   sem ficar agressivo. Antes era branco sobre preto. */
.pp-telemed-room__waiting {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  gap: 12px;
  color: #475569;
  text-align: center;
  padding: 20px;
  font-size: 14px;
}
.pp-telemed-room__waiting-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 72px;
  height: 72px;
  border-radius: 50%;
  background: #cbd5e1;
  color: #475569;
}

.pp-telemed-room__speaker {
  position: absolute;
  top: 12px;
  right: 12px;
  background: rgba(34, 197, 94, 0.85);
  color: #fff;
  padding: 6px 12px;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 600;
  z-index: 3;
  backdrop-filter: blur(4px);
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.pp-telemed-room__stats {
  position: absolute;
  top: 12px;
  left: 12px;
  background: rgba(0, 0, 0, 0.7);
  color: #fff;
  padding: 6px 10px;
  border-radius: 8px;
  font-family: ui-monospace, Menlo, Monaco, monospace;
  font-size: 11px;
  line-height: 1.4;
  z-index: 3;
  cursor: pointer;
  backdrop-filter: blur(4px);
}
.pp-telemed-room__stats-toggle {
  position: absolute;
  top: 12px;
  left: 12px;
  background: rgba(0, 0, 0, 0.6);
  color: #fff;
  border: 0;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  cursor: pointer;
  z-index: 3;
  display: inline-flex;
  align-items: center;
  justify-content: center;
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

/* PIP local — bottom 16 porque footer agora é externo ao stage (grid row).
   Antes era 100px pra escapar dos controles que estavam por cima do vídeo. */
.pp-telemed-room__local {
  position: absolute;
  right: 16px;
  bottom: 16px;
  width: 200px;
  height: 113px;
  border-radius: 12px;
  background: #1e293b;
  overflow: hidden;
  border: 2px solid rgba(255, 255, 255, 0.2);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2;
}
.pp-telemed-room__local video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
/* Espelha SÓ quando facingMode === 'user' (frontal). Câmera traseira
   filmando o ambiente não deve inverter — texto/objetos ficariam ao
   contrário. Desktop sem facingMode reportado cai no default 'user'. */
.pp-telemed-room__local--mirror video {
  transform: scaleX(-1);
}
.pp-telemed-room__local--off {
  background: #334155;
}
/* Border azul + glow quando eu estiver falando (active speaker local).
   Mesma linguagem visual dos tiles remotos. */
.pp-telemed-room__local--speaking {
  border-color: #3b82f6;
  box-shadow: 0 0 0 4px rgba(59, 130, 246, 0.35);
}
/* Label "Você" no canto do PIP, com indicador de mic mutado. */
.pp-telemed-room__local-name {
  position: absolute;
  left: 8px;
  bottom: 8px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 500;
  backdrop-filter: blur(4px);
  pointer-events: none;
}

/* ─── Banner de erro de mídia ──────────────────────────────────────────
   Aparece acima do stage quando getUserMedia falha (HTTP, permissão
   negada, sem device). Banner amarelo (warning) com ícone + texto +
   botão "Tentar novamente". */
.pp-telemed-room__media-error {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  background: #fef3c7;
  border-bottom: 1px solid #fde68a;
  color: #78350f;
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

/* ─── Chat sidebar (Google Meet pattern) ──────────────────────────────
   Painel branco fixo de 360px à direita do stage. Empilha:
     - header (título + close)
     - toggle host (doutor)
     - lock notice (paciente, se host desligou)
     - lista (ou empty state)
     - form
   Em mobile (< 768px) ocupa a tela toda — o stage some atrás. */
.pp-telemed-room__chat {
  width: 360px;
  background: #fff;
  border-left: 1px solid #e5e7eb;
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.pp-telemed-room__chat-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px;
  border-bottom: 1px solid #e5e7eb;
  font-size: 14px;
  color: #0f172a;
}
.pp-telemed-room__chat-close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  color: #64748b;
  border: 0;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  cursor: pointer;
  padding: 0;
  transition: background 120ms ease;
}
.pp-telemed-room__chat-close:hover {
  background: #f1f5f9;
  color: #0f172a;
}

/* Host toggle (doutor) — switch estilo iOS */
.pp-telemed-room__chat-toggle {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
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
  background: #2563eb;
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

/* Aviso pro paciente quando host travou o chat. */
.pp-telemed-room__chat-locked {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 16px;
  background: #fef3c7;
  color: #78350f;
  font-size: 12px;
  border-bottom: 1px solid #fde68a;
}

.pp-telemed-room__chat-list {
  flex: 1;
  overflow-y: auto;
  padding: 12px 16px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

/* Empty state — ícone grande cinza + título + texto explicativo. */
.pp-telemed-room__chat-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  flex: 1;
  padding: 20px;
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

.pp-telemed-room__chat-msg {
  max-width: 85%;
  padding: 8px 12px;
  border-radius: 12px;
  background: #f1f5f9;
  color: #0f172a;
  align-self: flex-start;
}
.pp-telemed-room__chat-msg--mine {
  background: #2563eb;
  color: #fff;
  align-self: flex-end;
}
.pp-telemed-room__chat-author {
  font-size: 10px;
  opacity: 0.7;
  margin-bottom: 2px;
  text-transform: uppercase;
  letter-spacing: 0.4px;
}
.pp-telemed-room__chat-text {
  font-size: 13px;
  line-height: 1.4;
  word-wrap: break-word;
}
.pp-telemed-room__chat-form {
  display: flex;
  gap: 8px;
  padding: 12px 16px;
  border-top: 1px solid #e5e7eb;
}
.pp-telemed-room__chat-form input {
  flex: 1;
  min-width: 0;
  padding: 10px 12px;
  background: #f8fafc;
  color: #0f172a;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  font-size: 13px;
}
.pp-telemed-room__chat-form input::placeholder {
  color: #94a3b8;
}
.pp-telemed-room__chat-form input:focus {
  outline: 0;
  border-color: #2563eb;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}
.pp-telemed-room__chat-form input:disabled {
  background: #f1f5f9;
  cursor: not-allowed;
}
.pp-telemed-room__chat-form button {
  padding: 8px 14px;
  background: #2563eb;
  color: #fff;
  border: 0;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-telemed-room__chat-form button:hover:not(:disabled) {
  background: #1d4ed8;
}
.pp-telemed-room__chat-form button:disabled {
  background: #cbd5e1;
  cursor: not-allowed;
}

/* Em mobile o chat vira fullscreen (sobrepõe o stage). */
@media (max-width: 768px) {
  .pp-telemed-room__chat {
    position: absolute;
    inset: 0;
    width: 100%;
    border-left: 0;
    z-index: 6;
  }
}

/* Sala de espera (paciente) — light theme.
   Overlay claro com card branco no centro. Backdrop semitransparente
   pra ainda dar pra perceber o vídeo/preview por baixo se quiser. */
.pp-telemed-room__admit-overlay {
  position: absolute;
  inset: 0;
  background: rgba(248, 250, 252, 0.92);
  backdrop-filter: blur(8px);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 4;
  padding: 20px;
}
.pp-telemed-room__admit-card {
  width: 100%;
  max-width: 380px;
  padding: 28px 24px;
  background: #fff;
  border-radius: 20px;
  box-shadow: 0 20px 50px -12px rgba(15, 23, 42, 0.18);
  text-align: center;
  color: #0f172a;
}
.pp-telemed-room__admit-card h2 {
  margin: 16px 0 8px;
  font-size: 18px;
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
  border: 3px solid rgba(37, 99, 235, 0.15);
  border-top-color: #2563eb;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

/* Banner do doutor — pacientes pra admitir */
.pp-telemed-room__admit-banner {
  position: absolute;
  top: 12px;
  left: 50%;
  transform: translateX(-50%);
  min-width: 280px;
  max-width: 90%;
  background: #fff;
  color: #0f172a;
  border-radius: 12px;
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.3);
  z-index: 5;
  overflow: hidden;
}
.pp-telemed-room__admit-banner-head {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 14px;
  background: #fef3c7;
  color: #78350f;
  font-size: 13px;
}
.pp-telemed-room__admit-banner-icon {
  color: #b45309;
}
.pp-telemed-room__admit-banner-list {
  display: flex;
  flex-direction: column;
}
.pp-telemed-room__admit-banner-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  border-top: 1px solid #f1f5f9;
}
.pp-telemed-room__admit-banner-row:first-child {
  border-top: 0;
}
.pp-telemed-room__admit-banner-name {
  font-size: 14px;
  font-weight: 500;
}
.pp-telemed-room__admit-btn {
  background: #16a34a;
  color: #fff;
  border: 0;
  border-radius: 8px;
  padding: 6px 14px;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-telemed-room__admit-btn:hover {
  background: #15803d;
}

/* ─── Footer (controles) ──────────────────────────────────────────────
   Bar branca, border-top discreta. Controles em cinza claro (default),
   vermelho saturado quando em estado "off" (mic mutado, cam desligada) ou
   "active" (chat aberto = azul claro). Botão "Sair" mantém pill vermelho. */
.pp-telemed-room__controls {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 14px 16px;
  padding-bottom: max(14px, env(safe-area-inset-bottom));
  background: #fff;
  border-top: 1px solid #e5e7eb;
}
.pp-telemed-room__ctrl {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  width: 48px;
  height: 48px;
  border-radius: 50%;
  background: #f1f5f9;
  color: #334155;
  border: 0;
  cursor: pointer;
  transition:
    background 120ms ease,
    color 120ms ease,
    transform 80ms ease;
}
.pp-telemed-room__ctrl:hover {
  background: #e2e8f0;
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
  background: #dbeafe;
  color: #1d4ed8;
}
.pp-telemed-room__ctrl--active:hover {
  background: #bfdbfe;
}
.pp-telemed-room__ctrl--leave {
  width: auto;
  padding: 0 18px;
  border-radius: 28px;
  background: #dc2626;
  color: #fff;
  font-size: 14px;
  font-weight: 600;
}
.pp-telemed-room__ctrl--leave:hover {
  background: #b91c1c;
}
.pp-telemed-room__badge {
  position: absolute;
  top: 2px;
  right: 2px;
  min-width: 16px;
  height: 16px;
  padding: 0 4px;
  background: #ef4444;
  color: #fff;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 700;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

/* ─── Preflight (Google Meet lobby) ────────────────────────────────────
   Tela cheia, fundo claro do portal. Split: preview à esquerda (60%) e
   painel de controles à direita (40%). Mobile empilha vertical. */
.pp-telemed-preflight {
  position: fixed;
  inset: 0;
  background: #f8fafc;
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(320px, 1fr);
  gap: 24px;
  padding: 32px;
  align-items: center;
  z-index: 1000;
}
.pp-telemed-preflight__preview {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  background: #0f172a;
  border-radius: 16px;
  overflow: hidden;
  box-shadow: 0 10px 40px -12px rgba(15, 23, 42, 0.4);
}
.pp-telemed-preflight__video {
  width: 100%;
  height: 100%;
  object-fit: cover;
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
  gap: 12px;
  background: #1e293b;
  color: #cbd5e1;
}
.pp-telemed-preflight__camoff p {
  margin: 0;
  font-size: 14px;
}
/* "1080p" / "720p" / "360p" label canto superior direito do preview. */
.pp-telemed-preflight__quality {
  position: absolute;
  top: 12px;
  right: 12px;
  padding: 4px 12px;
  background: rgba(0, 0, 0, 0.55);
  color: #fff;
  border-radius: 999px;
  font-size: 12px;
  font-weight: 500;
  backdrop-filter: blur(4px);
}
/* Controles flutuantes sobre o preview — mic/cam toggle. */
.pp-telemed-preflight__overlay-controls {
  position: absolute;
  bottom: 16px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  gap: 12px;
}
.pp-telemed-preflight__ctrl {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.95);
  color: #334155;
  border: 0;
  cursor: pointer;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
  transition:
    background 120ms ease,
    color 120ms ease,
    transform 80ms ease;
}
.pp-telemed-preflight__ctrl:hover {
  background: #fff;
}
.pp-telemed-preflight__ctrl:active {
  transform: scale(0.94);
}
.pp-telemed-preflight__ctrl.off {
  background: #dc2626;
  color: #fff;
}
.pp-telemed-preflight__ctrl.off:hover {
  background: #b91c1c;
}

.pp-telemed-preflight__panel {
  display: flex;
  flex-direction: column;
  gap: 16px;
  max-width: 420px;
  width: 100%;
  justify-self: center;
}
.pp-telemed-preflight__title {
  margin: 0 0 4px;
  font-size: 22px;
  font-weight: 700;
  color: #0f172a;
}
.pp-telemed-preflight__code {
  margin: 0 0 12px;
  font-size: 13px;
  color: #64748b;
}
.pp-telemed-preflight__code strong {
  font-family: ui-monospace, Menlo, Monaco, monospace;
  letter-spacing: 0.4px;
  color: #0f172a;
}
.pp-telemed-preflight__error {
  border-radius: 12px;
  border: 1px solid #fde68a;
}
.pp-telemed-preflight__row {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.pp-telemed-preflight__row-label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  font-weight: 600;
  color: #475569;
}
.pp-telemed-preflight__select {
  width: 100%;
  padding: 10px 12px;
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  font-size: 13px;
  color: #0f172a;
  cursor: pointer;
  /* Remove arrow nativa em alguns browsers — mantém minimal. */
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 24 24' fill='none' stroke='%2364748b' stroke-width='2.5' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 12px center;
  background-size: 12px;
  padding-right: 36px;
}
.pp-telemed-preflight__select:focus {
  outline: 0;
  border-color: #2563eb;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.12);
}
.pp-telemed-preflight__select:disabled {
  background-color: #f1f5f9;
  cursor: not-allowed;
  color: #94a3b8;
}
.pp-telemed-preflight__actions {
  display: flex;
  gap: 10px;
  margin-top: 8px;
}
.pp-telemed-preflight__cancel {
  flex: 1;
  padding: 12px 16px;
  background: #f1f5f9;
  color: #475569;
  border: 0;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-telemed-preflight__cancel:hover {
  background: #e2e8f0;
}
.pp-telemed-preflight__enter {
  flex: 2;
  padding: 12px 16px;
  background: #2563eb;
  color: #fff;
  border: 0;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 700;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-telemed-preflight__enter:hover:not(:disabled) {
  background: #1d4ed8;
}
.pp-telemed-preflight__enter:disabled {
  background: #cbd5e1;
  cursor: not-allowed;
}

/* Mobile: empilha vertical, preview menor. */
@media (max-width: 900px) {
  .pp-telemed-preflight {
    grid-template-columns: 1fr;
    grid-template-rows: auto auto;
    padding: 16px;
    gap: 16px;
    align-items: start;
  }
  .pp-telemed-preflight__panel {
    max-width: 100%;
  }
}

/* Sprint L — Consent UI no preflight + modal de termos */
.pp-telemed-preflight__consent {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  margin-top: 16px;
  padding: 10px 12px;
  background: rgba(255,255,255,0.04);
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 6px;
  font-size: 12px;
  line-height: 1.4;
  color: rgba(255,255,255,0.85);
  cursor: pointer;
}
.pp-telemed-preflight__consent-checkbox {
  margin-top: 2px;
  cursor: pointer;
  flex-shrink: 0;
}
.pp-telemed-preflight__consent-text a {
  color: #6ab7ff;
  text-decoration: underline;
}
.pp-telemed-preflight__enter:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.pp-telemed-consent-modal {
  position: fixed; inset: 0; z-index: 200;
  background: rgba(0,0,0,0.6);
  display: flex; align-items: center; justify-content: center;
  padding: 16px;
}
.pp-telemed-consent-modal__box {
  background: white; color: #222;
  padding: 24px; border-radius: 8px;
  max-width: 560px; max-height: 80vh; overflow-y: auto;
  font-size: 14px; line-height: 1.5;
}
.pp-telemed-consent-modal__box h3 {
  margin-top: 0; font-size: 18px;
}
.pp-telemed-consent-modal__body p {
  margin: 8px 0;
}
.pp-telemed-consent-modal__box .pp-telemed-preflight__enter {
  margin-top: 12px;
  background: #2563eb; color: white;
  padding: 8px 16px; border-radius: 6px; border: 0;
  cursor: pointer;
}
</style>
