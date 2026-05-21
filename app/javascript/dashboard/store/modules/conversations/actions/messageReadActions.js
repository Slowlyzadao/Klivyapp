import { throwErrorMessage } from 'dashboard/store/utils/api';
import ConversationApi from '../../../../api/inbox/conversation';
import mutationTypes from '../../../mutation-types';

// Map<conversationId, timeoutId> de timers pendentes do
// `UPDATE_MESSAGE_UNREAD_COUNT`. Necessário porque a action `markMessagesRead`
// agenda a mutation com 4s de delay para dar tempo do agente perceber a
// transição visual. Quando o agente navega rapidamente entre conversas
// (ex: 5 conversas em 4s), cada chamada empilhava um setTimeout novo sem
// cancelar os anteriores — closures vivas + N mutations dispondo do mesmo
// trabalho. Cancelar o pendente da mesma conversa antes de agendar novo
// elimina o acúmulo. Map module-scoped é singleton (escopo do bundle JS),
// seguro porque `id` (conversation display_id) é único dentro do
// `Current.account` que o store está representando — troca de account
// reseta o store inteiro.
const pendingUnreadTimeouts = new Map();

export default {
  markMessagesRead: async ({ commit }, data) => {
    try {
      const {
        data: { id, agent_last_seen_at: lastSeen },
      } = await ConversationApi.markMessageRead(data);

      const existing = pendingUnreadTimeouts.get(id);
      if (existing) clearTimeout(existing);

      const timeoutId = setTimeout(() => {
        commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, { id, lastSeen });
        pendingUnreadTimeouts.delete(id);
      }, 4000);

      pendingUnreadTimeouts.set(id, timeoutId);
    } catch (error) {
      // Handle error
    }
  },

  markMessagesUnread: async ({ commit }, { id }) => {
    try {
      const {
        data: { agent_last_seen_at: lastSeen, unread_count: unreadCount },
      } = await ConversationApi.markMessagesUnread({ id });
      commit(mutationTypes.UPDATE_MESSAGE_UNREAD_COUNT, {
        id,
        lastSeen,
        unreadCount,
      });
    } catch (error) {
      throwErrorMessage(error);
    }
  },
};
