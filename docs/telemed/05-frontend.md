# 05 — Frontend (Vue 3)

## 5.1 Mapa de componentes

```
plugins/telemed/frontend/
├── dashboard/                              # visão clínica
│   ├── api/
│   │   ├── teleconsultas.js                # TeleconsultasAPI + ProposedEvolutionsAPI
│   │   └── agendaTelemedicine.js           # AgendaTelemedicineAPI (sala)
│   ├── components/
│   │   └── TelemedicineJoinButton.vue
│   ├── composables/
│   │   ├── useLiveDuration.js
│   │   ├── useTeleconsultaList.js          # paginação + filtros
│   │   └── useTelemedicineJoin.js          # pedir token + abrir sala
│   ├── features/teleconsulta/              # CRUD da aba Teleconsulta
│   │   ├── TeleconsultaListPage.vue        # lista com abas
│   │   ├── TeleconsultaDetailPage.vue      # detalhe (gravação + transcrição + evolução)
│   │   ├── TeleconsultaDetailHeader.vue    # banner do paciente
│   │   ├── TeleconsultaCard.vue            # card da lista
│   │   ├── TeleconsultaRecordingPlayer.vue # player áudio R2
│   │   ├── TeleconsultaTranscript.vue      # transcrição com karaokê + busca
│   │   ├── TeleconsultaSummary.vue         # resumo executivo (markdown-it)
│   │   ├── TeleconsultaProcedureRegister.vue  # 14 campos editáveis
│   │   ├── TeleconsultaEvolutionEditor.vue # painel Pontos de Atenção
│   │   ├── TeleconsultaPagination.vue
│   │   ├── TeleconsultaScheduleNewCard.vue
│   │   └── utils/formatters.js             # date-fns wrappers
│   ├── pages/
│   │   └── TelemedRoomPage.vue             # wrapper sala dentista
│   └── routes/routes.js
├── patient/                                # visão paciente (Patient Portal)
│   ├── api/telemedicine.js
│   ├── components/TelemedicineJoinCard.vue # inline no detalhe da consulta
│   └── pages/TelemedicineRoomPage.vue      # wrapper sala paciente
├── shared/                                 # código reutilizado
│   ├── components/
│   │   ├── TelemedicineRoom.vue            # sala LiveKit (puro)
│   │   └── TelemedDeviceSelect.vue         # dropdown mic/cam/speaker
│   └── composables/
│       └── useTelemedicineSession.js       # reportar joined/left
└── styles/
    ├── teleconsulta-index.scss
    └── teleconsulta-detail.scss
```

---

## 5.2 Componente central: `TelemedicineRoom.vue`

`plugins/telemed/frontend/shared/components/TelemedicineRoom.vue`

**Princípio**: componente puro, sem fetchs próprios. Recebe tudo por props, comunica por events.

### Props principais

| Prop | Tipo | Descrição |
|------|------|-----------|
| `url` | String | URL do servidor LiveKit (ex: `wss://livekit.exemplo.com`) |
| `token` | String | JWT emitido pelo backend |
| `role` | String | `'doctor'` ou `'patient'` |
| `requiresAdmit` | Boolean | True se paciente entrou fora da janela e precisa ser admitido |
| `roomCode` | String | Slug `klivy-acc<id>-ev<id>` |
| `initialAdmissions` | Array | Identities já admitidas (pra reidratar após F5) |

### Events emitidos

| Event | Payload | Quando |
|-------|---------|--------|
| `leave` | `{ reason }` | Usuário fechou ou doutor encerrou |
| `session-event` | `{ kind: 'joined' \| 'left', consented? }` | Hooks pra reportar no backend |
| `ended-by-host` | — | Doutor encerrou (paciente vê) |

### Imports LiveKit

```js
import {
  Room, RoomEvent, Track, VideoPresets, VideoQuality,
  ConnectionQuality, createLocalVideoTrack, createLocalAudioTrack,
} from 'livekit-client';
```

Background blur (lazy):

```js
const loadBlur = async () => {
  const { BackgroundProcessor } = await import('@livekit/track-processors');
  // ...
};
```

### Conexão LiveKit

```js
const room = new Room({
  adaptiveStream: true,
  dynacast: true,
  videoCaptureDefaults: {
    resolution: VideoPresets.h720.resolution,
  },
});

room.on(RoomEvent.ParticipantConnected, onParticipantConnected);
room.on(RoomEvent.TrackSubscribed, onTrackSubscribed);
room.on(RoomEvent.DataReceived, onDataReceived);  // chat + admit signaling
room.on(RoomEvent.ConnectionStateChanged, onStateChange);

await room.connect(url, token);
await room.localParticipant.enableCameraAndMicrophone();
```

### Waiting Room (paciente)

Se `requiresAdmit: true`:
1. Preview local (`getUserMedia` direto, sem publicar) → mostra "Aguardando dentista aceitar".
2. Backend emitiu token com `canPublish: false`.
3. Doutor clica "Admitir" → `POST /admit_patient` → backend chama `UpdateParticipant` no LiveKit → flip `canPublish: true`.
4. Cliente detecta via `room.localParticipant.permissionsChanged` → publica mic/cam.

### Encerramento por host

Doutor clica "Encerrar pra todos":
1. Envia `DataPacket` no canal `lossy` com `{ type: 'call_ended' }`.
2. Sai do room.
3. Paciente recebe `RoomEvent.DataReceived` → `emit('ended-by-host')` → redirect home.

---

## 5.3 Dashboard: dois componentes-chave

### 5.3.1 `TeleconsultaDetailPage.vue`

`plugins/telemed/frontend/dashboard/features/teleconsulta/TeleconsultaDetailPage.vue`

Página de detalhe. Layout:

```
┌─────────────────────────────────────────────────────────────┐
│  ← Voltar para a lista                                       │
├─────────────────────────────────────────────────────────────┤
│  [Banner: paciente + status + data + Ver Prontuário]         │
├──────────────────────────────────────┬──────────────────────┤
│  [Player áudio]                       │  [Pontos de Atenção  │
│                                       │   — sticky]          │
│  [Transcrição (karaokê)]             │                      │
│                                       │                      │
│  [Resumo da Teleconsulta]            │                      │
└──────────────────────────────────────┴──────────────────────┘
│  [Registrar Procedimento — bloco full-width]                 │
│   14 campos editáveis + badges "BIA" + Salvar+Assinar        │
└─────────────────────────────────────────────────────────────┘
```

Lógica importante (`<script setup>`):

```js
// Anti-stale sequencer: requests podem responder fora de ordem
let fetchSeq = 0;
const fetchDetail = async () => {
  const mySeq = ++fetchSeq;
  try {
    const { data } = await teleconsultasApi.show(eventId.value);
    if (mySeq !== fetchSeq) return;  // outra chamada veio depois
    detail.value = data.data;
  } catch (e) { /* ... */ }
};

// ActionCable listener (status do recording em tempo real)
const onTelemedRecordingUpdated = payload => {
  if (String(payload.agenda_event_id) !== String(eventId.value)) return;
  if (detail.value.recording) {
    detail.value.recording.status = payload.status;
  }
  if (['transcribed', 'ready', 'failed'].includes(payload.status)) {
    fetchDetail();  // re-fetch pra trazer transcript/SOAP/evolution
  }
};

onMounted(() => emitter.on(BUS_EVENTS.TELEMED_RECORDING_UPDATED, onTelemedRecordingUpdated));
onBeforeUnmount(() => emitter.off(BUS_EVENTS.TELEMED_RECORDING_UPDATED, onTelemedRecordingUpdated));
```

### 5.3.2 `TeleconsultaProcedureRegister.vue`

`plugins/telemed/frontend/dashboard/features/teleconsulta/TeleconsultaProcedureRegister.vue`

Formulário com 14 campos pré-preenchidos pela IA. Estrutura:

```js
const FIELDS = [
  { key: 'queixa_do_dia',             label: '...', type: 'textarea', section: 'avaliacao' },
  { key: 'avaliacao_clinica',         label: '...', type: 'textarea', section: 'avaliacao' },
  { key: 'procedimento_realizado',    label: '...', type: 'text',     section: 'procedimento', required: true },
  // ... 14 total
];

const SECTIONS = [
  { id: 'avaliacao',      title: 'Avaliação Clínica' },
  { id: 'procedimento',   title: 'Procedimento e Produto' },
  { id: 'acompanhamento', title: 'Acompanhamento' },
];
```

Lógica de "badge IA" (some quando o campo é editado):

```js
const aiOriginal = ref({});  // snapshot do que veio do backend
const local = ref({});       // estado editável

const initFromEvolution = () => {
  const incoming = props.evolution.procedure_fields || {};
  FIELDS.forEach(f => {
    local.value[f.key] = incoming[f.key] ?? '';
    aiOriginal.value[f.key] = incoming[f.key] ?? '';
  });
};

const isFieldAi = key => {
  const orig = aiOriginal.value[key];
  if (orig === undefined || orig === null || orig === '') return false;
  return String(orig) === String(local.value[key] ?? '');
};
```

Checkbox de responsabilidade clínica (bloqueia "Salvar e Assinar" até marcar):

```vue
<label class="tcd-procedure__confirm">
  <input v-model="confirmationChecked" type="checkbox" />
  <span>
    Confirmo que <strong>li integralmente</strong> esta evolução, fiz as
    modificações clínicas necessárias e <strong>concordo</strong> com o
    conteúdo que será aplicado ao prontuário do paciente. Assumo a autoria
    e responsabilidade clínica pelo registro.
  </span>
</label>

<button :disabled="!confirmationChecked" @click="approve">Salvar e Assinar</button>
```

Reseta sozinho quando `props.evolution.id` muda (nova proposta = nova revisão consciente).

Approve fluxo:

```js
const approve = async () => {
  if (!window.confirm('Aplicar esta evolução ao prontuário do paciente?')) return;
  // Se tem mudanças não salvas, salva ANTES de aprovar
  if (hasUnsavedChanges.value) {
    await proposedEvolutionsApi.update(props.evolution.id, {
      procedure_fields: buildPayload(),
    });
  }
  const { data } = await proposedEvolutionsApi.approve(props.evolution.id);
  // Normaliza envelope HTTP → payload de evento
  emit('approved', {
    evolution: data.data,
    clinical_note: data.clinical_note,
  });
};
```

---

## 5.4 API clients

### `dashboard/api/teleconsultas.js`

```js
class TeleconsultasAPI extends ApiClient {
  constructor() { super('telemed/teleconsultas', { accountScoped: true }); }
  list({ tab, page, perPage, professionalId, dateFrom, dateTo })
  show(eventId)
  counts()
  recordingUrl(eventId, kind)  // kind: 'composite_audio' | 'doctor_audio' | ...
  retranscribe(eventId)
  reevolve(eventId)
}

class ProposedEvolutionsAPI extends ApiClient {
  constructor() { super('telemed/proposed_evolutions', { accountScoped: true }); }
  update(id, payload)
  approve(id)
  reject(id, reason)
}

export const teleconsultasApi = new TeleconsultasAPI();
export const proposedEvolutionsApi = new ProposedEvolutionsAPI();
```

### `dashboard/api/agendaTelemedicine.js`

```js
class AgendaTelemedicineAPI extends ApiClient {
  issueToken(eventId)
  reportEvent(eventId, kind)        // kind: 'joined' | 'left'
  confirmCompleted(eventId)
  admitPatient(eventId, identity)
  startRecording(eventId, opts)
  stopRecording(eventId)
}
```

### `patient/api/telemedicine.js`

```js
class TelemedicineAPI {
  issueToken(eventId)               // POST /patient_portal/telemed/sessions
  reportEvent(eventId, kind, opts)  // POST /patient_portal/telemed/sessions/event
}
```

---

## 5.5 Composables Vue

### `useTeleconsultaList.js`

Paginação + filtros pra `TeleconsultaListPage`:

```js
export function useTeleconsultaList() {
  const tab = ref('upcoming');
  const items = ref([]);
  const page = ref(1);
  const perPage = ref(20);
  const totalPages = ref(null);
  const isLoading = ref(false);
  const counts = ref({});
  
  let fetchSeq = 0;
  
  const fetch = async () => {
    const mySeq = ++fetchSeq;
    isLoading.value = true;
    try {
      const { data } = await teleconsultasApi.list({ tab: tab.value, page: page.value, ...filters });
      if (mySeq !== fetchSeq) return;
      items.value = data.data;
      totalPages.value = data.meta.total_pages;
    } finally {
      if (mySeq === fetchSeq) isLoading.value = false;
    }
  };
  
  // setTab, applyFilters, goToPage...
  
  return { tab, items, page, perPage, totalPages, isLoading, counts, fetch, setTab, goToPage };
}
```

### `useTelemedicineJoin.js`

Fluxo "pedir token + abrir sala":

```js
export function useTelemedicineJoin() {
  const joining = ref(false);
  const error = ref(null);
  
  const join = async event => {
    joining.value = true;
    try {
      const { data } = await agendaTelemedicineApi.issueToken(event.id);
      // Armazena pra wrapper consumir após popup abrir
      sessionStorage.setItem(`klivy:telemed:${event.id}`, JSON.stringify(data.data));
      window.open(roomUrl(event.id), '_blank', 'width=1280,height=800');
    } catch (e) {
      error.value = translateError(e);
    } finally {
      joining.value = false;
    }
  };
  
  const consumeToken = eventId => {
    const raw = sessionStorage.getItem(`klivy:telemed:${eventId}`);
    if (!raw) return null;
    sessionStorage.removeItem(`klivy:telemed:${eventId}`);
    return JSON.parse(raw);
  };
  
  return { joining, error, join, consumeToken };
}
```

### `useTelemedicineSession.js` (shared)

Reporta `joined`/`left` com idempotência (componente da sala não precisa preocupar com retry):

```js
export function useTelemedicineSession(eventId, api) {
  const joinedReported = ref(false);
  const leftReported = ref(false);
  
  const reportJoined = async (opts = {}) => {
    if (joinedReported.value) return;
    joinedReported.value = true;
    try { await api.reportEvent(eventId, 'joined', opts); }
    catch (e) { /* silent — não impede sala */ }
  };
  
  const reportLeft = async () => {
    if (leftReported.value) return;
    leftReported.value = true;
    try { await api.reportEvent(eventId, 'left'); }
    catch (e) { /* silent */ }
  };
  
  return { reportJoined, reportLeft, reset: () => { joinedReported.value = false; leftReported.value = false; } };
}
```

---

## 5.6 Routes (dashboard)

`plugins/telemed/frontend/dashboard/routes/routes.js`:

```js
export default [
  {
    path: 'teleconsultas',
    name: 'teleconsultas_index',
    component: () => import('../features/teleconsulta/TeleconsultaListPage.vue'),
  },
  {
    path: 'teleconsultas/:eventId',
    name: 'teleconsulta_detail',
    component: () => import('../features/teleconsulta/TeleconsultaDetailPage.vue'),
  },
  {
    path: 'agenda/telemed/:eventId',
    name: 'agenda_telemed_room',
    component: () => import('../pages/TelemedRoomPage.vue'),
    meta: { hideSidebar: true, fullScreen: true },
  },
];
```

As rotas são registradas no router principal do dashboard via plugin loader do Klivy.

---

## 5.7 SCSS / Design tokens

### Estrutura

- `styles/teleconsulta-index.scss` — lista (grid de cards, tabs, paginação).
- `styles/teleconsulta-detail.scss` — detalhe (banner, grid 2 cols, player, transcript, procedure register).

### Tokens (do PRD)

```scss
// Primário
$telemed-primary:    #1552F1;
$telemed-primary-12: rgba(21, 82, 241, 0.12);

// IA bg
$telemed-ia-bg:      #EBF0FF;

// Slate (do core Klivy via CSS vars)
// --slate-1 (bg), --slate-12 (text)
```

### Sticky Pontos de Atenção

A coluna direita do detalhe (Pontos de Atenção) usa `position: sticky` pra acompanhar scroll da coluna esquerda (que tem muito mais conteúdo):

```scss
.tcd-grid {
  display: grid;
  grid-template-columns: minmax(0, 7fr) minmax(0, 5fr);
  // align-items: stretch (default) — fundamental pro sticky
}

.tcd-attention-panel {
  position: sticky;
  top: 24px;
  max-height: calc(100vh - 48px);
  overflow-y: auto;
}
```

### Karaokê na transcrição

Segmento ativo (correspondente ao tempo atual do player) ganha highlight visual:

```scss
.tcd-transcript__msg.is-active .tcd-transcript__text {
  background: rgba(21, 82, 241, 0.10);
  border-radius: 8px;
}
```

`current-time` é prop emitida pelo player (`@time-update="playerCurrentTime = $event"`), o componente Transcript faz binary search no `transcript_segments` pra achar o ativo.

---

## 5.8 Patterns de UX importantes

### 5.8.1 Anti-stale concorrência

Toda chamada API que pode race tem `fetchSeq` (sequencer). Aplicado em:
- `useTeleconsultaList.fetch`
- `TeleconsultaDetailPage.fetchDetail`
- `useTelemedicineSession.reportJoined`

### 5.8.2 Unsaved changes guard

Componentes editáveis expõem `hasUnsavedChanges` via `defineExpose`. O parent (`TeleconsultaDetailPage`) usa `onBeforeRouteLeave`:

```js
onBeforeRouteLeave(() => {
  const editorDirty    = editorRef.value?.hasUnsavedChanges?.value;
  const procedureDirty = procedureRef.value?.hasUnsavedChanges?.value;
  if (editorDirty || procedureDirty) {
    return window.confirm('Você tem alterações não salvas. Sair mesmo assim?');
  }
  return true;
});
```

Plus `beforeunload` handler (refresh/fechar aba) registrado dinamicamente quando `hasUnsavedChanges` é true.

### 5.8.3 Empty states

Cada listagem (`TeleconsultaListPage`, `TeleconsultaTranscript`, `TeleconsultaSummary`) tem variação visual quando vazio:
- Loading: skeleton específico (não spinner genérico)
- Empty: ícone + frase explicativa orientando o próximo passo
- Error: cor `#dc2626` + retry button (quando aplicável)

### 5.8.4 Real-time updates via ActionCable

O `DetailPage` se inscreve no canal global da conta:

```js
emitter.on(BUS_EVENTS.TELEMED_RECORDING_UPDATED, onTelemedRecordingUpdated);
```

`BUS_EVENTS` é um bus interno do Klivy core que normaliza eventos vindos do ActionCable global do dashboard. Backend dispara `recording.broadcast_status_change!` → frontend reage sem F5.

---

## 5.9 Acessibilidade

- `aria-label` em todos os botões de ação (`Pausar`, `Ajustar volume`, `Buscar na transcrição`).
- `aria-live="polite"` no contador de busca (`1/28`) pra leitor de tela.
- `aria-modal="true"` nos modais.
- `@media (prefers-reduced-motion: reduce)` desliga animações da scrollbar, karaokê e transições do player.
- Foco visível em todos os controles (sem `outline: none` global — só escopado em focus rings custom).
