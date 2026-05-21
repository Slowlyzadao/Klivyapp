import { ref, watch, effectScope } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { createAgendaState } from './useAgenda.js';
import { useAgendaInit } from './useAgendaInit.js';
import { useAgendaCrud } from './useAgendaCrud.js';
import { createDefaultNewEvent } from '../utils/agenda-date.js';

// Singleton agenda state shared by AgendaDashboard, ContactInfo (botão
// "Agendar consulta") e o outlet do modal montado em Dashboard.vue. Manter
// uma única instância garante que abrir o modal a partir de qualquer ponto
// reflete no mesmo `showNewEventModal`/`newEvent` — sem duplicar componente
// nem state. createAgendaState() permanece exportado para testes ou rotas
// que ainda queiram um state isolado, mas a aplicação real usa este module.
let _agenda = null;
let _newEvent = null;
let _wlScheduleEntry = null;
let _returnPatientId = null;
let _autoCreatePatient = null;
let _hideBlockTab = null;
let _initScope = null;
let _fetchInitialDataFn = null;

function ensureSingleton() {
  if (_agenda) return;
  _agenda = createAgendaState();
  _agenda.init();
  _newEvent = ref(createDefaultNewEvent());
  _wlScheduleEntry = ref(null);
  _returnPatientId = ref(null);
  // Sinal usado pelo AgendaEventModal: quando true, o modal abre o
  // sub-modal "+ Novo paciente" automaticamente após mount, pré-preenchido
  // com nome/telefone do contato (ver `open()` abaixo). Permanece local no
  // frontend — não é enviado ao backend.
  _autoCreatePatient = ref(false);
  // Quando true, o modal esconde a tab "Bloqueio". Bloqueio é trava de
  // horário (férias, treinamento) e não faz sentido quando o agendamento
  // está sendo criado para um contato/conversa específico — o agente quer
  // Consulta ou Compromisso, não bloquear a agenda toda.
  _hideBlockTab = ref(false);

  // Reseta os flags `_autoCreatePatient` e `_hideBlockTab` sempre que o
  // modal fecha (X, save bem-sucedido, confirmDelete, etc). Sem isso, os
  // flags vazariam para a próxima abertura — ex: usuário abre via
  // Conversas, fecha, depois clica em "+ Novo Evento" na Agenda e cairia
  // com tabs filtradas indevidamente. effectScope detached porque o watch
  // precisa sobreviver à desmontagem de qualquer consumidor individual.
  const closeWatchScope = effectScope(true);
  closeWatchScope.run(() => {
    watch(
      () => _agenda.state.showNewEventModal,
      (isOpen) => {
        if (!isOpen) {
          _autoCreatePatient.value = false;
          _hideBlockTab.value = false;
        }
      }
    );
  });
}

// useAgendaInit instala um watch de longo prazo em `agendaState.currentDate`
// + `viewMode`. Rodar dentro de um effectScope detached impede que esse
// watch seja descartado quando o primeiro componente consumidor (qualquer
// um — Conversations ou Agenda) desmontar. O launcher precisa sobreviver
// a navegações entre rotas.
function ensureDataPipeline(store) {
  if (_fetchInitialDataFn) return _fetchInitialDataFn;
  _initScope = effectScope(true);
  _initScope.run(() => {
    const { fetchInitialData } = useAgendaInit({
      store,
      agendaState: _agenda.state,
      checkQueryParams: null,
    });
    _fetchInitialDataFn = fetchInitialData;
  });
  return _fetchInitialDataFn;
}

export function useAgendaEventLauncher() {
  const store = useStore();
  const router = useRouter();
  const route = useRoute();

  ensureSingleton();

  // Handlers do CRUD são reconstruídos por consumidor (cada componente
  // tem seu próprio store/router/route via injection). Como mutam o mesmo
  // singleton state, ter múltiplas vinculações é inofensivo — última a
  // chamar vence, e em prática todos os consumidores compartilham o mesmo
  // store/router (Vuex e Vue Router são singletons no app).
  const crud = useAgendaCrud({
    agenda: _agenda,
    store,
    router,
    route,
    newEvent: _newEvent,
    wlScheduleEntry: _wlScheduleEntry,
    _returnPatientId,
  });

  // Carga inicial (agentes, settings, custom attrs, services, categories,
  // eventos da janela visível) é deferida até o primeiro `open()` ou até
  // a Agenda ser visitada e chamar `ensureLoaded()` explicitamente. Evita
  // disparar 5 requests para usuários que abrem só o painel de Conversas.
  const ensureLoaded = () => ensureDataPipeline(store)();

  // Abre o modal pré-preenchido a partir de qualquer plugin (caso de uso
  // primário: botão "Agendar consulta" em ContactInfo.vue). Aceita os
  // mesmos campos que `useAgendaCrud.openEventModal` (`dayObj`, `hourStr`,
  // `agent`) mais um payload opcional de paciente. O ensureLoaded é
  // disparado em paralelo — modal aparece imediatamente; agendaSettings
  // e customAttributesConfig caem dentro nos próximos ms.
  const open = (payload = {}) => {
    ensureLoaded();

    // Set dos flags ANTES de abrir o modal para garantir que, quando o
    // watch em `show` rodar no modal, as props já estejam atualizadas —
    // evita race condition independentemente de `flush: 'sync'` vs `'pre'`.
    _autoCreatePatient.value = !!(
      payload.source === 'conversation' &&
      !payload.patient_id &&
      payload.contact_id &&
      payload.patient_name
    );
    // Esconde tab Bloqueio quando o agendamento é para um contato vindo
    // de uma conversa. Bloqueio é trava de horário (férias, treinamento)
    // — não faz sentido nesse contexto.
    _hideBlockTab.value = payload.source === 'conversation';

    crud.openEventModal({
      dayObj: payload.dayObj || null,
      hourStr: payload.hourStr || null,
      agent: payload.agent || null,
    });
    if (payload.patient_id) {
      _newEvent.value.patient_id = Number(payload.patient_id);
    }
    if (payload.patient_name) {
      _newEvent.value.selectedPatientName = payload.patient_name;
      _newEvent.value.title = payload.patient_name;
    }
    if (payload.patient_phone) {
      _newEvent.value.selectedPatientPhone = payload.patient_phone;
    }
    if (payload.patient_avatar_url) {
      _newEvent.value.selectedPatientAvatarUrl = payload.patient_avatar_url;
    }
    if (payload.contact_id) {
      _newEvent.value.contact_id = Number(payload.contact_id);
    }
    if (payload.event_type) {
      _newEvent.value.event_type = payload.event_type;
    }
  };

  return {
    agenda: _agenda,
    newEvent: _newEvent,
    wlScheduleEntry: _wlScheduleEntry,
    returnPatientId: _returnPatientId,
    autoCreatePatient: _autoCreatePatient,
    hideBlockTab: _hideBlockTab,

    open,
    ensureLoaded,
    openEditEvent: crud.openEditEvent,
    closeEventModal: crud.closeEventModal,
    saveEvent: crud.saveEvent,
    deleteEvent: crud.deleteEvent,
    cancelDelete: crud.cancelDelete,
    confirmDelete: crud.confirmDelete,
    quickDeleteEvent: crud.quickDeleteEvent,
    checkQueryParams: crud.checkQueryParams,
  };
}
