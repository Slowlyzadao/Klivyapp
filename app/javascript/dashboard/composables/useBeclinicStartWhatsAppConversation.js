/* global axios */
import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { emitter } from 'shared/helpers/mitt';

// Mensagens de erro retornadas pelo controller `whatsapp/start_conversations`.
// Centralizadas aqui pra todos os pontos que iniciam conversa (lista de
// conversas, busca híbrida, lista de contatos) mostrarem o mesmo texto.
const ERROR_MESSAGES = {
  NUMBER_NOT_ON_WHATSAPP: 'Esse número não tem WhatsApp.',
  NO_WHATSAPP_INBOX: 'Nenhuma inbox WhatsApp configurada nesta conta.',
  INBOX_DISCONNECTED:
    'A inbox WhatsApp está desconectada. Reconecte antes de iniciar conversa.',
  INVALID_PHONE: 'Número inválido. Use DDD + número (ex: 11 91601-9363).',
  FORBIDDEN: 'Você não tem permissão para iniciar conversas.',
};

const FALLBACK_MESSAGE = 'Não foi possível iniciar a conversa.';

/**
 * Inicia (ou reusa) uma conversa WhatsApp para um número e navega até ela.
 *
 * O endpoint backend (`POST /whatsapp/start_conversation`):
 *  - normaliza o telefone (assume +55 quando faltar código do país),
 *  - valida no bridge se o número TEM WhatsApp,
 *  - reusa conversa aberta se já existir (não duplica contato),
 *  - cria contato + conversa novos quando não existir.
 *
 * @returns {{ isStarting: import('vue').Ref<boolean>, startConversation: (phoneNumber: string) => Promise<void> }}
 */
export function useBeclinicStartWhatsAppConversation() {
  const route = useRoute();
  const router = useRouter();
  const isStarting = ref(false);

  const startConversation = async phoneNumber => {
    if (!phoneNumber || isStarting.value) return;

    isStarting.value = true;
    try {
      const accountId = route.params.accountId;
      const { data } = await window.axios.post(
        `/api/v1/accounts/${accountId}/whatsapp/start_conversation`,
        { phone_number: phoneNumber }
      );

      // Limpa qualquer estado de busca aberta no header e navega.
      emitter.emit('clearSearchInput');
      router.push({
        name: 'inbox_conversation',
        params: {
          accountId,
          conversation_id: data.conversation_id,
        },
      });
    } catch (err) {
      const code = err.response?.data?.error;
      useAlert(
        ERROR_MESSAGES[code] || err.response?.data?.message || FALLBACK_MESSAGE
      );
    } finally {
      isStarting.value = false;
    }
  };

  return { isStarting, startConversation };
}
