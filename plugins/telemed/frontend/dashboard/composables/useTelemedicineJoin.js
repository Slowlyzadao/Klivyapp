// Composable que centraliza "pedir token + abrir sala" pro lado clínica.
// Componentes que renderizam um agenda_event (popup, card de detalhe,
// futuras integrações em prontuário) consomem este composable em vez de
// duplicar a chamada de API e o roteamento.
//
// Padrão de uso:
//   const { joining, error, join } = useTelemedicineJoin();
//   await join(event);
//
// O `join` faz tudo:
//   1. Chama o endpoint admin pra pegar token JWT
//   2. Guarda o payload (url, token, dev_mode) em sessionStorage com a
//      chave `klivy:telemed:<eventId>` — a página /agenda/telemed/:id
//      lê dali. Por que sessionStorage e não querystring? Pra evitar token
//      JWT visível na URL (cache de browser, logs do servidor, capturas
//      de tela). sessionStorage some quando a aba fecha, é por-aba (não
//      vaza entre janelas) e o token tem TTL curto (10min) de qualquer jeito.
//   3. Abre uma nova janela apontando pra rota da sala.
//
// Erros são reportados via `error.value` (string traduzida) e via `useAlert`.
/* eslint-disable no-console */
// no-console disable: erro de issueToken é raro e útil em debug — não impacta
// UI (mensagem amigável já passa pelo useAlert).
import { ref } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AgendaTelemedicineAPI from '@plugins/telemed/frontend/dashboard/api/agendaTelemedicine';

const TOKEN_STORAGE_PREFIX = 'klivy:telemed:';
const REASON_TO_PT = {
  too_early: 'A sala ainda não abriu. Aguarde o horário.',
  window_closed: 'A janela de entrada já foi encerrada.',
  event_cancelled: 'Esta consulta foi cancelada.',
  event_not_joinable: 'Esta consulta não está num status que permita entrar.',
  event_missing_times: 'O agendamento não tem horário definido.',
  telemedicine_not_enabled: 'Esta consulta não está marcada como teleconsulta.',
  telemedicine_issue_failed: 'Não foi possível abrir a sala. Tente novamente.',
};

export function useTelemedicineJoin() {
  const store = useStore();
  const router = useRouter();
  const joining = ref(false);
  const error = ref(null);

  // Storage key sempre indexada pelo event_id NUMÉRICO. Se a navegação usou
  // slug (`pppp-eeee-aaaa`), extrai o segmento do meio. Sem isso, write
  // (com id numérico) e read (com slug) usariam keys diferentes.
  function normalizeId(idOrSlug) {
    if (typeof idOrSlug !== 'string') return idOrSlug;
    if (!idOrSlug.includes('-')) return idOrSlug;
    const parts = idOrSlug.split('-');
    return parts.length === 3 ? parts[1] : idOrSlug;
  }
  function storageKey(eventId) {
    return `${TOKEN_STORAGE_PREFIX}${normalizeId(eventId)}`;
  }

  async function join(event) {
    if (!event?.id) return;
    joining.value = true;
    error.value = null;
    try {
      const { data } = await AgendaTelemedicineAPI.issueToken(event.id);
      const payload = data?.data || data;
      if (!payload?.token || !payload?.url) {
        throw new Error('Resposta do servidor sem token.');
      }

      // Guarda token na sessionStorage indexado pelo event.id (não pelo slug
      // — sessionStorage é só interno, key é estável independente da URL).
      sessionStorage.setItem(storageKey(event.id), JSON.stringify(payload));

      // Abre em nova aba — preserva o calendário aberto e a sessão do dentista.
      // Sprint K — usa slug `pppp-eeee-aaaa` (estilo Google Meet) na URL se
      // o backend retornou. Fallback pro id puro mantém compat com clientes
      // antigos que ainda não tem slug no payload.
      const accountId =
        store.getters.getCurrentAccount?.id ||
        store.getters.getCurrentAccountId ||
        router.currentRoute?.value?.params?.accountId;
      const eventIdOrSlug = payload.room_code || event.id;
      const route = router.resolve({
        name: 'agenda_telemed_room',
        params: { accountId, eventId: eventIdOrSlug },
      });
      window.open(route.href, '_blank', 'noopener,noreferrer');
    } catch (err) {
      const code = err?.response?.data?.code;
      const msg =
        REASON_TO_PT[code] ||
        err?.response?.data?.error ||
        'Não foi possível abrir a sala.';
      error.value = msg;
      useAlert(msg);
      console.error('[useTelemedicineJoin]', err);
    } finally {
      joining.value = false;
    }
  }

  function consumeToken(eventId) {
    // Lê e remove (one-shot) — evita reuso do mesmo token se a aba for refresh.
    const raw = sessionStorage.getItem(storageKey(eventId));
    if (!raw) return null;
    sessionStorage.removeItem(storageKey(eventId));
    try {
      return JSON.parse(raw);
    } catch {
      return null;
    }
  }

  return { joining, error, join, consumeToken };
}
