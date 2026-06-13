class Api::V1::Accounts::AgendaServicesController < Api::V1::Accounts::BaseController
  # ATENÇÃO: `:reorder` é collection action (`patch /agenda_services/reorder`),
  # NÃO pode entrar no `only:` deste filter — `params[:id]` seria a string
  # "reorder", e `agenda_services.find("reorder")` levantaria RecordNotFound
  # → 404 "Resource could not be found" antes da action sequer rodar.
  # Bug descoberto no PR #9 quando o drag-and-drop virou o primeiro cliente real.
  before_action :agenda_service, only: [:show, :update, :destroy, :usage_stats]
  # PR de arquivados (2026-05-14): `restore` e `destroy_permanently` operam em
  # serviços SOFT-DELETADOS — não cabem no `:agenda_service` (escopo `.kept`).
  before_action :agenda_service_any, only: [:restore, :destroy_permanently]
  before_action :check_authorization
  # PR #8 follow-up (2026-05-14): captura IP para AuditLog do PR #8.
  # `Agenda::AuditLog.async_record` lê `Current.request_ip` automaticamente
  # depois desta linha rodar. Sem isso, ficaria nil mesmo em ações HTTP.
  before_action :stamp_request_ip

  PAGINATED_DEFAULT_PER_PAGE = 10
  PAGINATED_MAX_PER_PAGE = 100

  # PR de UI overhaul (2026-05-14): suporte a 2 modos.
  # - Legado (sem `page`): array simples, usado por calendário/sidebar (que
  #   precisam de TODOS os serviços pra montar treatmentOptions/cor/duração).
  # - Paginado (com `page`): { services: [...com counts], meta: {...} }.
  #   Usado pela aba Settings que tem milhares de serviços em contas grandes.
  #
  # PR de arquivados (2026-05-14): suporte ao filtro `?archived=true` no modo
  # paginado — lista os serviços com `deleted_at` preenchido. Permite a UI
  # da aba Settings ter um toggle "Ativos / Arquivados" pra revisar e
  # restaurar registros sem precisar de SQL manual.
  def index
    archived_view = ActiveModel::Type::Boolean.new.cast(params[:archived])
    scope = if archived_view
              Current.account.agenda_services.discarded.order(deleted_at: :desc)
            else
              Current.account.agenda_services.ordered
            end
    scope = apply_search_filter(scope, params[:q]) if params[:q].present?

    if params[:page].present? || params[:per_page].present?
      render_paginated(scope)
    else
      @services = scope
    end
  end

  def show; end

  # PR de UI overhaul (2026-05-14): retorna preview dos serviços sem uso
  # com `id`, `name` e `color` — o modal lista os nomes para o operador
  # validar exatamente o que será arquivado antes de confirmar.
  # Ordenado por nome (case-insensitive) para facilitar a revisão visual.
  def cleanup_unused_preview
    authorize AgendaService, :cleanup_unused?
    # Sem `.kept` — preview espelha o que será deletado pelo `cleanup_unused`:
    # tanto serviços ativos sem uso quanto arquivados sem uso.
    services = Current.account.agenda_services
                      .where(id: unused_service_ids)
                      .order(Arel.sql('lower(name)'))
                      .pluck(:id, :name, :color)
                      .map { |id, name, color| { id: id, name: name, color: color } }
    render json: { count: services.size, services: services }
  end

  # PR de UI overhaul (2026-05-14) + simplificação (2026-05-14):
  # Hard-delete em massa de serviços SEM NENHUM VÍNCULO (zero `agenda_events`
  # vivos + zero `treatment_items` vivos). Como esses registros nunca tiveram
  # uso, não há audit trail a preservar — soft-delete seria só lixo no banco.
  #
  # **IRREVERSÍVEL**. UI exige confirmação explícita via checkbox antes do
  # botão habilitar.
  #
  # Implementação: `delete_all` pula callbacks → AuditLog NÃO é gerado pra
  # esses registros (trade-off deliberado: zero rastro a preservar). Para
  # auditoria fina (soft-delete individual com motivo), usar `DELETE
  # /agenda_services/:id` (action `destroy`).
  #
  # Idempotente: rerun é seguro (segunda chamada não acha mais nada).
  def cleanup_unused
    authorize AgendaService, :cleanup_unused?
    ids = unused_service_ids

    # Importante: SEM `.kept` aqui — `unused_service_ids` agora inclui
    # também serviços arquivados (legacy) sem vínculo. Tudo em um delete só.
    Current.account.agenda_services.where(id: ids).delete_all if ids.any?

    render json: { cleaned_count: ids.size, ids: ids }
  end

  # PR de arquivados (2026-05-14): desfaz soft-delete (deleted_at = nil).
  # Idempotente: se já está restaurado (kept), no-op. Trigger do AuditLog
  # via `after_update_commit` no concern Auditable → registra action `restore`.
  def restore
    return head :ok if @service.deleted_at.nil?

    @service.update!(deleted_at: nil)
    render :show
  end

  # PR de arquivados (2026-05-14): hard-delete individual com confirmação UI.
  # Diferente do `destroy` (soft-delete), este remove fisicamente do banco.
  # **IRREVERSÍVEL** — para usar quando o operador tem certeza de que o
  # registro não precisa de auditoria histórica (ex.: serviços de teste).
  # AuditLog dispara `destroy` automaticamente via concern Auditable.
  def destroy_permanently
    @service.destroy!
    head :ok
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PR #7 da auditoria 2026-05-13: antes de excluir, frontend chama este endpoint
  # pra mostrar ao operador quantos eventos e itens de plano vão ficar órfãos
  # (mantém `procedure_name`/`treatment` no JSONB, mas perdem o FK).
  # Decisão consciente em vez de "tem certeza?" cego.
  def usage_stats
    render json: {
      id: @service.id,
      name: @service.name,
      agenda_events_count: agenda_events_count_for_service,
      treatment_items_count: treatment_items_count_for_service
    }
  end

  def create
    @service = Current.account.agenda_services.create!(service_params)
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def update
    @service.update!(service_params)
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # Hard-delete (PR de simplificação 2026-05-14): o serviço é removido
  # FISICAMENTE do banco. A FK `agenda_events.agenda_service_id` é
  # nullificada via `ON DELETE SET NULL` — eventos antigos preservam o
  # `custom_attributes['treatment']` (NAME) como audit trail histórico.
  # Audit do destroy é capturado automaticamente pelo concern Auditable
  # (after_destroy_commit) com snapshot completo em `before`.
  # UI exige ConfirmDangerModal com contagem de uso antes de aceitar.
  def destroy
    @service.destroy!
    head :ok
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /accounts/:account_id/agenda_services/reorder
  # Reordena os serviços. Body: { ids: [1, 2, 3] }
  #
  # PR #3 da auditoria 2026-05-13:
  # - `.uniq` blinda contra IDs duplicados no payload (B7, C6).
  # - `UPDATE ... CASE WHEN` em SQL único (B8): 500 serviços = 1 round-trip.
  # - Scope `.kept` ignora soft-deletados; cross-tenant é blindado pelo
  #   `Current.account.agenda_services`.
  #
  # PR #9 (drag-and-drop): refatoração crítica para compat com paginação.
  # Antes: `position = idx_no_array` — bagunçava outras páginas se o operador
  # reordenasse só a página 2 (posições 10-19 viravam 0-9, colidindo com a página 1).
  # Agora: preserva os SLOTS de posição dos serviços enviados, redistribuindo
  # apenas entre eles. Reordenar a página 2 mantém os slots [10..19] —
  # só muda quem fica em cada slot. Página 1 intocada.
  def reorder
    ids = params[:ids]
    return head :unprocessable_entity unless ids.is_a?(Array)

    ordered_ids = ids.map(&:to_i).uniq.reject(&:zero?)
    return head :ok if ordered_ids.empty?

    # Slots = posições atuais dos serviços enviados, ordenadas ascendentemente.
    # Filtra IDs inexistentes/cross-tenant (a query naturalmente exclui).
    current = Current.account.agenda_services.kept
                     .where(id: ordered_ids)
                     .order(:position)
                     .pluck(:id, :position)
    return head :ok if current.empty?

    position_slots = current.map(&:last)            # já sorted pela query
    existing_ids = current.map(&:first).to_set
    filtered_ids = ordered_ids.select { |id| existing_ids.include?(id) }
    return head :ok if filtered_ids.empty?

    # Redistribui os slots na nova ordem. filtered_ids[0] vai pro menor slot,
    # filtered_ids[1] pro próximo, etc.
    case_clauses = filtered_ids.each_with_index.map do |id, idx|
      "WHEN #{id} THEN #{position_slots[idx]}"
    end.join(' ')

    Current.account.agenda_services.kept
           .where(id: filtered_ids)
           .update_all("position = CASE id #{case_clauses} ELSE position END")

    head :ok
  end

  private

  def agenda_service
    @service ||= Current.account.agenda_services.kept.find(params[:id])
  end

  # PR de arquivados (2026-05-14): busca em qualquer estado (kept + discarded).
  # Usado por `restore` (que opera em discarded) e `destroy_permanently`
  # (que aceita ambos — soft-deletados são o caso típico, mas hard-delete
  # direto também é válido).
  def agenda_service_any
    @service ||= Current.account.agenda_services.find(params[:id])
  end

  def service_params
    params.require(:agenda_service).permit(
      :name, :duration_minutes, :requires_room, :color, :position
    )
  end

  # PR #7: contadores de uso. Contam apenas registros vivos:
  # - AgendaEvent.kept (exclui soft-deletados)
  # - TreatmentItem ativos (exclui soft-deletados via deleted_at IS NULL)
  # Ambos com FK populada pelo PR #4/#6b — não dependem mais do JSONB.
  def agenda_events_count_for_service
    Current.account.agenda_events
           .kept
           .where(agenda_service_id: @service.id)
           .count
  end

  def treatment_items_count_for_service
    TreatmentItem
      .where(account_id: Current.account.id, agenda_service_id: @service.id)
      .where(deleted_at: nil)
      .count
  end

  # PR #8 follow-up: setado em before_action; lido por Agenda::AuditLog
  # via `Current.try(:request_ip)`. Tolerante a Current sem o accessor
  # (libs/specs antigas) via `respond_to?` check.
  def stamp_request_ip
    Current.request_ip = request.remote_ip if Current.respond_to?(:request_ip=)
  end

  # PR de busca multi-campo (2026-05-14): filtra por nome (LIKE) OU id numérico
  # (match exato). UI exibe o ID em badges visíveis na tabela e em selectors —
  # então buscar por ID faz sentido aqui (operador vê o badge e digita o número).
  # UUID continua fora porque não tem visibilidade na UI.
  def apply_search_filter(scope, query)
    q = query.to_s.strip
    return scope if q.blank?

    clauses = ['lower(name) LIKE ?']
    bindings = ["%#{q.downcase}%"]

    if q.match?(/\A\d+\z/)
      clauses << 'id = ?'
      bindings << q.to_i
    end

    scope.where(clauses.join(' OR '), *bindings)
  end

  # PR de UI overhaul: contadores em coluna virtual via subquery, computados
  # em uma única query SQL. Para 10 rows (página típica), Postgres executa
  # 20 sub-COUNTs indexados — milissegundos.
  def select_with_usage_counts(scope)
    scope.select(<<~SQL.squish)
      agenda_services.*,
      (SELECT COUNT(*) FROM agenda_events
        WHERE agenda_events.agenda_service_id = agenda_services.id
          AND agenda_events.deleted_at IS NULL) AS agenda_events_count,
      (SELECT COUNT(*) FROM treatment_items
        WHERE treatment_items.agenda_service_id = agenda_services.id
          AND treatment_items.deleted_at IS NULL) AS treatment_items_count
    SQL
  end

  def render_paginated(scope)
    page = (params[:page] || 1).to_i.clamp(1, 99_999)
    per_page = (params[:per_page] || PAGINATED_DEFAULT_PER_PAGE).to_i.clamp(1, PAGINATED_MAX_PER_PAGE)
    total_count = scope.count
    total_pages = total_count.zero? ? 0 : (total_count.to_f / per_page).ceil

    @services = select_with_usage_counts(scope).offset((page - 1) * per_page).limit(per_page)
    @meta = {
      current_page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
    render :index_paginated
  end

  # IDs de serviços sem nenhum uso vivo. Usado pelo preview e pelo cleanup.
  # `NOT EXISTS` short-circuita: bate o primeiro hit em `agenda_service_id`
  # (indexado por PR #4/#6b) e abandona — barato mesmo com 1000+ serviços.
  #
  # IMPORTANTE: NÃO usa `.kept` — também inclui serviços ARQUIVADOS
  # (deleted_at preenchido) que não têm nenhum vínculo. Antes a discrepância
  # confundia o operador: aba "Arquivados" mostrava 7, mas cleanup só 4.
  # Após esta mudança, a contagem é consistente: TODOS os serviços lixo
  # (ativos sem uso + arquivados sem uso) são limpos no mesmo botão.
  def unused_service_ids
    Current.account.agenda_services.where(<<~SQL.squish).pluck(:id)
      NOT EXISTS (SELECT 1 FROM agenda_events
                   WHERE agenda_events.agenda_service_id = agenda_services.id
                     AND agenda_events.deleted_at IS NULL)
      AND NOT EXISTS (SELECT 1 FROM treatment_items
                       WHERE treatment_items.agenda_service_id = agenda_services.id
                         AND treatment_items.deleted_at IS NULL)
    SQL
  end
end
