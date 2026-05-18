class Api::V1::Accounts::BeclinicUnifiedSearchController < Api::V1::Accounts::BaseController
  # GET /api/v1/accounts/:account_id/beclinic_unified_search?q=<query>
  #
  # Busca híbrida estilo WhatsApp Web:
  # - Conversas com contato cujo nome OU phone_number bata com a query
  # - Contatos que NÃO têm nenhuma conversa (para o agente iniciar uma)
  #
  # Resposta:
  #   { conversations: [...], contacts: [...] }
  #
  # Sem `q` ou query muito curta → arrays vazios (UI mostra fallback "digite mais").
  RESULTS_LIMIT = 10
  MIN_QUERY_LENGTH = 2

  def index
    return render_empty if query.length < MIN_QUERY_LENGTH

    @conversations = fetch_conversations
    @contacts = fetch_contacts_without_conversation
  end

  private

  def query
    @query ||= params[:q].to_s.strip
  end

  # Match contra `name` OU `phone_number` (digits-only do lado do banco vs query).
  # Mantemos ILIKE pra continuar pegando matches por nome; a tabela `contacts`
  # já tem índice em `lower(name)` e `phone_number` é curto o bastante pra ILIKE
  # ser rápido na escala atual. Pra dataset grande, considerar pg_trgm + GIN.
  def fetch_conversations
    conversations_query = Current.account.conversations
                                 .where(inbox_id: accessible_inbox_ids)
                                 .joins(:contact)
                                 .where('contacts.name ILIKE :q OR contacts.phone_number ILIKE :q', q: "%#{query}%")
                                 .includes(:contact, :inbox, :assignee, :messages)
                                 .order('conversations.last_activity_at DESC NULLS LAST')
                                 .limit(RESULTS_LIMIT)

    conversations_query.to_a
  end

  def fetch_contacts_without_conversation
    matched_contacts = Current.account.contacts
                              .where('name ILIKE :q OR phone_number ILIKE :q', q: "%#{query}%")

    # NUNCA retornar contatos que já aparecem no bloco "Conversas" — evita
    # duplicação visual (regra crítica do design da feature).
    contact_ids_with_conversation = @conversations.map(&:contact_id).compact.uniq
    matched_contacts = matched_contacts.where.not(id: contact_ids_with_conversation) if contact_ids_with_conversation.any?

    matched_contacts.includes(avatar_attachment: :blob)
                    .order(last_activity_at: :desc)
                    .limit(RESULTS_LIMIT)
                    .to_a
  end

  def accessible_inbox_ids
    @accessible_inbox_ids ||= Current.user.assigned_inboxes.pluck(:id)
  end

  def render_empty
    @conversations = []
    @contacts = []
    render :index
  end
end
