class Api::V1::Accounts::AgendaEventsController < Api::V1::Accounts::BaseController
  before_action :agenda_event, except: [:index, :create, :year_stats]

  INDEX_MAX_RESULTS = 500
  YEAR_STATS_MIN_YEAR = 2000
  YEAR_STATS_MAX_YEAR = 2100
  YEAR_STATS_TIMEZONE = 'America/Sao_Paulo'.freeze

  def index
    authorize AgendaEvent
    # `kept` esconde eventos soft-deletados da agenda (eles permanecem visíveis
    # no prontuário do paciente via patients/appointments#index para histórico).
    # Eager-load `:agenda_service` evita N+1 ao serializar o snapshot inline
    # do serviço (PR #6 da auditoria). Sem isso, cada um dos até 500 eventos
    # do index dispara um SELECT em `agenda_services`.
    scope = policy_scope(Current.account.agenda_events.kept)
            .includes(:user, :agenda_service, contact: :patient)
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
    scope = scope.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    scope = scope.where(status: params[:status]) if params[:status].present?

    # Filtragem por período: overlap real (não containment).
    # Um evento aparece na janela se as faixas se cruzam — isso captura
    # corretamente eventos que cruzam a borda (ex.: domingo 23:30 → segunda 00:30).
    if params[:starts_at].present? && params[:ends_at].present?
      scope = scope.where('starts_at < ? AND ends_at > ?', params[:ends_at], params[:starts_at])
    elsif Rails.env.production?
      Rails.logger.warn("[Agenda] index sem range para account=#{Current.account.id}; aplicando cap=#{INDEX_MAX_RESULTS}")
    end

    @agenda_events = scope.order(:starts_at).limit(INDEX_MAX_RESULTS)
    fresh_when(@agenda_events)
  end

  # Agregação por dia do ano para a Year View. Listar 1k+ eventos crus
  # estouraria INDEX_MAX_RESULTS e o payload — em vez disso retornamos
  # contagens agregadas por status, índices `(account_id, starts_at)` +
  # partial `WHERE deleted_at IS NULL` cobrem o GROUP BY sem table scan.
  # Filtros: respeita `policy_scope` (scope=own filtra por user_id) e
  # aceita `user_id` opcional pra paridade com `index`. Demais filtros
  # visuais (categoria/serviço/etc.) ficam client-side via breakdown
  # de status — mesma estratégia que o frontend usa hoje em `index`.
  def year_stats
    # Reaproveita o policy check de `index?` — Pundit por default procura
    # por `year_stats?` baseado no nome da action, e como não existe esse
    # método em `AgendaEventPolicy`, levantaria `Pundit::NotDefinedError`
    # (= 500). A leitura agregada tem mesma semântica de permissão que
    # listar eventos (`beclinic_can?(:agenda, :view)`).
    authorize AgendaEvent, :index?
    year = params[:year].to_i
    if year < YEAR_STATS_MIN_YEAR || year > YEAR_STATS_MAX_YEAR
      render json: { error: 'Invalid year' }, status: :unprocessable_entity
      return
    end

    tz = YEAR_STATS_TIMEZONE
    range_start = Time.find_zone(tz).local(year, 1, 1).beginning_of_day
    range_end   = Time.find_zone(tz).local(year, 12, 31).end_of_day

    scope = policy_scope(Current.account.agenda_events.kept)
            .where(starts_at: range_start..range_end)
    scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?

    # GROUP BY day_in_tz + status — uma única query agregada. Postgres
    # converte `starts_at` (UTC) para o timezone da conta antes de fazer
    # DATE(), garantindo que um evento das 23:00 BRT não pule pro dia
    # seguinte por causa de UTC offset.
    rows = scope
           .group(Arel.sql("date_trunc('day', (starts_at AT TIME ZONE 'UTC') AT TIME ZONE #{ActiveRecord::Base.connection.quote(tz)})"), :status)
           .count

    by_day = {}
    rows.each do |(day_ts, status), count|
      next unless day_ts && status

      key = day_ts.strftime('%Y-%m-%d')
      bucket = by_day[key] ||= {
        'count' => 0, 'scheduled' => 0, 'confirmed' => 0, 'arrived' => 0,
        'in_progress' => 0, 'completed' => 0, 'cancelled' => 0, 'no_show' => 0
      }
      bucket['count'] += count
      bucket[status.to_s] = (bucket[status.to_s] || 0) + count if bucket.key?(status.to_s)
    end

    render json: { year: year, by_day: by_day }
  end

  def show
    authorize @agenda_event
  end

  def create
    authorize AgendaEvent
    safe_params = agenda_event_params
    safe_params = clamp_user_id_for_own_scope(safe_params)
    safe_params = nullify_missing_contact(safe_params)
    safe_params = nullify_missing_category(safe_params)
    safe_params = nullify_missing_agenda_service(safe_params)
    @agenda_event = Current.account.agenda_events.create!(safe_params)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    authorize @agenda_event
    safe_params = agenda_event_params
    safe_params = clamp_user_id_for_own_scope(safe_params)
    safe_params = nullify_missing_contact(safe_params)
    safe_params = nullify_missing_category(safe_params)
    safe_params = nullify_missing_agenda_service(safe_params)
    @agenda_event.update!(safe_params)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Soft-delete: o evento NÃO é removido do banco. Permanece visível no
  # prontuário do paciente (Agenda e Histórico + Timeline) com motivo/nota
  # registrados. Aceita params { reason, note } via body do DELETE request.
  def destroy
    authorize @agenda_event

    reason = params[:reason].to_s.strip
    note   = params[:note].to_s.strip

    if reason.blank?
      render json: { error: 'Selecione o motivo da exclusão.' }, status: :unprocessable_entity
      return
    end

    if reason == 'outro' && note.blank?
      render json: { error: 'Justificativa é obrigatória ao escolher "Outro motivo".' },
             status: :unprocessable_entity
      return
    end

    @agenda_event.soft_delete!(actor: current_user, reason: reason, note: note)
    head :ok
  rescue RuntimeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def agenda_event
    # Sem filtro `kept` aqui porque `show`/`update`/`destroy` precisam achar
    # mesmo eventos já soft-deletados (ex.: re-render após delete).
    @agenda_event ||= Current.account.agenda_events.find(params[:id])
  end

  def agenda_event_params
    params.require(:agenda_event).permit(
      :title, :description, :starts_at, :ends_at,
      :user_id, :contact_id, :category_id, :agenda_service_id, :status, :event_type,
      custom_attributes: {}
    )
  end

  # Para usuários com `agenda` `scope=own`, força `user_id` ao usuário atual
  # antes do save. Sem isso (auditoria A-8), o cliente podia passar `user_id`
  # de outro profissional no payload do create/update — criando ou transferindo
  # evento em nome de terceiros e fugindo do confinamento do scope. Admin e
  # SuperAdmin têm `beclinic_scope == 'all'` (definido em BeclinicPermissible),
  # então passam direto sem alteração. AgentBot não responde a `beclinic_scope`,
  # então também passa direto (intencional — bots criam eventos em nome do
  # responsável real via lógica própria).
  def clamp_user_id_for_own_scope(safe_params)
    return safe_params unless Current.user.respond_to?(:beclinic_scope)
    return safe_params unless Current.user.beclinic_scope(Current.account, :agenda) == 'own'

    safe_params.merge(user_id: Current.user.id)
  end

  def nullify_missing_contact(safe_params)
    cid = safe_params[:contact_id]
    return safe_params if cid.blank?

    exists = Contact.where(account_id: Current.account.id, id: cid).exists?
    exists ? safe_params : safe_params.merge(contact_id: nil)
  end

  def nullify_missing_category(safe_params)
    cid = safe_params[:category_id]
    return safe_params if cid.blank?

    exists = Current.account.agenda_categories.where(id: cid).exists?
    exists ? safe_params : safe_params.merge(category_id: nil)
  end

  # PR #4 da auditoria: protege contra IDs de serviço inválidos (cross-tenant,
  # soft-deletados, ou inexistentes). Se o cliente mandar um ID que não casa
  # com nenhum `agenda_services.kept` da conta corrente, nullify em vez de
  # estourar `ActiveRecord::InvalidForeignKey`. O callback do model resolve
  # via `treatment` se houver — então o cliente pode mandar só o NAME no
  # JSONB que o backend completa.
  def nullify_missing_agenda_service(safe_params)
    sid = safe_params[:agenda_service_id]
    return safe_params if sid.blank?

    exists = Current.account.agenda_services.kept.where(id: sid).exists?
    exists ? safe_params : safe_params.merge(agenda_service_id: nil)
  end
end
