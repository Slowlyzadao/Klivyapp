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

  # Match contra `name` OU `phone_number/identifier` (digits-only do lado do
  # banco vs query). Mantemos ILIKE pra continuar pegando matches por nome; a
  # tabela `contacts` já tem índice em `lower(name)` e `phone_number` é curto
  # o bastante pra ILIKE ser rápido na escala atual. Pra dataset grande,
  # considerar pg_trgm + GIN.
  #
  # Quando a query parecer telefone, `phone_search_clause` adiciona variantes
  # com/sem o "9" inicial brasileiro pra recuperar contatos guardados na
  # forma alternativa (legado de 12 dígitos vs novo de 13).
  def fetch_conversations
    sql, binds = build_search_clause('contacts')

    conversations_query = Current.account.conversations
                                 .where(inbox_id: accessible_inbox_ids)
                                 .joins(:contact)
                                 .where(sql, binds)
                                 .includes(:contact, :inbox, :assignee, :messages)
                                 .order('conversations.last_activity_at DESC NULLS LAST')
                                 .limit(RESULTS_LIMIT)

    conversations_query.to_a
  end

  def fetch_contacts_without_conversation
    sql, binds = build_search_clause('contacts')

    matched_contacts = Current.account.contacts.where(sql, binds)

    # NUNCA retornar contatos que já aparecem no bloco "Conversas" — evita
    # duplicação visual (regra crítica do design da feature).
    contact_ids_with_conversation = @conversations.map(&:contact_id).compact.uniq
    matched_contacts = matched_contacts.where.not(id: contact_ids_with_conversation) if contact_ids_with_conversation.any?

    matched_contacts.includes(avatar_attachment: :blob)
                    .order(last_activity_at: :desc)
                    .limit(RESULTS_LIMIT)
                    .to_a
  end

  # Constrói cláusula WHERE (sql + binds) que faz match por nome literal e por
  # qualquer variante digit-only do telefone. `table_alias` permite reuso entre
  # JOIN (qualifica `contacts.*`) e query direta na tabela contacts.
  def build_search_clause(table_alias)
    name_col       = "#{table_alias}.name"
    phone_col      = "#{table_alias}.phone_number"
    identifier_col = "#{table_alias}.identifier"

    parts = ["#{name_col} ILIKE :q", "#{phone_col} ILIKE :q"]
    binds = { q: "%#{query}%" }

    Whatsapp::PhoneSearchVariants.digit_variants(query).each_with_index do |variant, idx|
      key = "phone_v#{idx}".to_sym
      parts << "#{phone_col} ILIKE :#{key}"
      parts << "#{identifier_col} ILIKE :#{key}"
      binds[key] = "%#{variant}%"
    end

    [parts.join(' OR '), binds]
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
