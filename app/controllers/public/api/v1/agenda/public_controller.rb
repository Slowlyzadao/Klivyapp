class Public::Api::V1::Agenda::PublicController < ActionController::API
  # Auditoria 9.11: actions de cancelamento via link assinado não dependem
  # de `:public_id` — o token já carrega `event_id + account_id`. Por isso
  # pulam o `fetch_user` (que resolve por public_id).
  before_action :fetch_user, except: [:booking_show, :booking_cancel]
  before_action :resolve_booking_token, only: [:booking_show, :booking_cancel]

  # Propósito do MessageVerifier — namespace de tokens, evita colisão se
  # outro fluxo do app criar tokens com chaves diferentes.
  BOOKING_TOKEN_PURPOSE = :agenda_public_booking

  def show
    unless @account.agenda_online_config&.enabled
      render json: { error: 'Online booking is disabled' }, status: :forbidden
      return
    end

    render json: {
      user: {
        name: @user.name,
        display_name: @user.display_name,
        avatar_url: @user.avatar_url
      },
      config: @account.agenda_online_config
    }
  end

  # Lista de serviços ativos da clínica para o paciente escolher no link
  # público. Somente serviços `kept` (não soft-deletados). Retorna `[]` se a
  # clínica não cadastrou serviços — o frontend cai pro fluxo legado (sem
  # `agenda_service_id`).
  #
  # Gate por `agenda_online_config.enabled`: catálogo de serviços (com preço
  # e duração) só é exposto se a clínica tem agendamento online ligado —
  # caso contrário responde 403 igual ao `show`/`book`, sem vazar pricing.
  #
  # Filtro 9.7: se um serviço tem 1+ vínculos em `agenda_service_users`, só
  # aparece nos links públicos dos profissionais vinculados. Sem vínculos
  # nenhum (estado pré-9.7 ou clínica que não configurou) = todos os pros
  # podem oferecer (compat). Implementado com `LEFT JOIN` + `OR` em SQL pra
  # evitar 2 queries e ficar performant numa única passagem.
  def services
    unless @account.agenda_online_config&.enabled
      render json: { error: 'Online booking is disabled' }, status: :forbidden
      return
    end

    services = services_for_current_user.map do |svc|
      {
        id: svc.id,
        name: svc.name,
        duration_minutes: svc.duration_minutes,
        price: svc.price,
        color: svc.color
      }
    end
    render json: { services: services }
  end

  def slots
    date = Date.parse(params[:date])
    service = fetch_service(params[:service_id])
    slots = calculate_slots(date, service: service)
    render json: { slots: slots }
  rescue Date::Error
    render json: { error: 'Invalid date format' }, status: :bad_request
  end

  # Auditoria 9.13: variante batch do `slots`. Recebe `from` e `to` (YYYY-MM-DD)
  # e devolve `{ slots: { "YYYY-MM-DD" => [...] } }`. Frontend usa para
  # pré-popular o calendário inteiro em 1 request em vez de 1 por dia.
  #
  # Otimização: busca TODOS os AgendaEvents do range numa única query (em vez
  # de 1 por dia, já beneficiado pela 9.17) e passa o array como cache para
  # `calculate_slots`. Range máximo limitado a 60 dias (alinhado com o
  # `future_limit_days` default) — impede abuso/enumeração e mantém payload
  # gerenciável.
  MAX_RANGE_DAYS = 60

  def slots_range
    from = Date.parse(params[:from])
    to   = Date.parse(params[:to])

    if to < from
      render json: { error: '`to` must be on or after `from`' }, status: :bad_request
      return
    end

    days = (to - from).to_i + 1
    if days > MAX_RANGE_DAYS
      render json: { error: "Range too wide. Max #{MAX_RANGE_DAYS} days." }, status: :bad_request
      return
    end

    service = fetch_service(params[:service_id])

    # Bulk fetch dos eventos de todo o range — 1 query independente da
    # quantidade de dias.
    Time.use_zone('America/Sao_Paulo') do
      range_start = Time.zone.parse("#{from} 00:00")
      range_end   = Time.zone.parse("#{to} 23:59:59")

      all_events = @account.agenda_events.kept
                           .where(user_id: @user.id)
                           .where('starts_at < ? AND ends_at > ?', range_end, range_start)
                           .pluck(:starts_at, :ends_at)

      result = {}
      (from..to).each do |date|
        # Filtro local por dia — evita refazer a query no banco. Mantém o
        # critério de overlap idêntico ao usado dentro do `calculate_slots`.
        result[date.to_s] = calculate_slots(date, service: service, events_cache: all_events)
      end

      render json: { slots: result }
    end
  rescue Date::Error
    render json: { error: 'Invalid date format. Use YYYY-MM-DD for from/to.' }, status: :bad_request
  end

  def book
    unless @account.agenda_online_config&.enabled
      render json: { error: 'Agendamento online desativado.' }, status: :forbidden
      return
    end

    date_iso = params[:date]
    time_str = params[:time]
    patient  = params[:patient]&.to_unsafe_h

    # Validações básicas
    missing = []
    missing << 'data'    if date_iso.blank?
    missing << 'horário' if time_str.blank?
    missing << 'paciente' if patient.blank?

    unless missing.empty?
      render json: { error: "Campos obrigatórios ausentes: #{missing.join(', ')}" }, status: :unprocessable_entity
      return
    end

    # 9.19 — Honeypot anti-bot. Campo invisível na ERB (`#f-website`); humanos
    # não preenchem. Se veio preenchido = bot. Responde como sucesso falso
    # (não dá pista pro bot de que foi detectado, evita ele tentar variações)
    # e LOGA para análise. Não cria nada no banco.
    if params[:website].to_s.strip.present?
      Rails.logger.warn(
        "[AgendaBooking] Honeypot triggered — ignoring request. " \
        "public_id=#{params[:public_id]} ip=#{request.remote_ip}"
      )
      render json: {
        success: true,
        message: 'Agendamento recebido. Você receberá uma confirmação em breve.'
      }, status: :created
      return
    end

    # 9.12 — Valida CPF (módulo 11) antes de qualquer query. Antes, o backend
    # aceitava `00000000000`/`11111111111`/etc e contaminava a base. Validação
    # client-side era apenas "11 dígitos". Aqui CPF é opcional (se a clínica
    # exige, o front bloqueia o submit) — mas SE veio, tem que ser válido.
    cpf_normalized = patient['cpf']&.gsub(/\D/, '')
    if cpf_normalized.present? && !valid_cpf?(cpf_normalized)
      render json: { error: 'CPF inválido. Verifique os dígitos.' }, status: :unprocessable_entity
      return
    end

    # Usar fuso horário de Brasília para interpretar os horários corretamente
    Time.use_zone('America/Sao_Paulo') do
      starts_at = Time.zone.parse("#{date_iso} #{time_str}")

      config = @account.agenda_online_config
      setting = @account.agenda_setting

      # Se o paciente escolheu um serviço, a duração do evento vem dele —
      # NUNCA confiar em duração mandada pelo cliente. Servidor lê do DB.
      # Fallback para `slot_interval_minutes` quando não há serviço (clínica
      # sem catálogo configurado).
      service = fetch_service(params[:service_id])
      slot_duration = (service&.duration_minutes || setting&.slot_interval_minutes || 60).to_i
      ends_at = starts_at + slot_duration.minutes

      min_lead = config.min_lead_time_minutes.to_i
      if starts_at < Time.zone.now + min_lead.minutes
        render json: { error: "Este horário não está mais disponível. O agendamento deve ser feito com pelo menos #{min_lead} minutos de antecedência." },
               status: :unprocessable_entity
        return
      end

      future_limit = (config.future_limit_days || 60).to_i
      if starts_at.to_date > Date.current + future_limit.days
        render json: { error: "Esta data está além do limite de agendamento online (#{future_limit} dias)." },
               status: :unprocessable_entity
        return
      end

      # Normaliza dados do paciente uma vez — usado pelo resolve_or_create_contact
      # dentro da transação e pelos demais helpers.
      phone = patient['phone']&.gsub(/\D/, '')
      email = patient['email'].presence
      cpf   = patient['cpf']&.gsub(/\D/, '')
      first_name = patient['first_name'].to_s.strip
      last_name  = patient['last_name'].to_s.strip
      full_name  = "#{first_name} #{last_name}".strip

      observations = patient['observations'].presence

      # Título reflete o serviço escolhido (quando houver) para aparecer
      # idêntico ao que a clínica veria criando o evento manualmente.
      event_title = service ? "#{service.name} – #{full_name}" : "Consulta – #{full_name}"

      # Description NÃO carrega dados sensíveis (CPF/telefone) — esse campo
      # vaza pra logs, exports e qualquer view da agenda. Dados pessoais
      # vão em `custom_attributes` (estruturados, fácil de mascarar em
      # serializer e excluir em pedidos LGPD).
      event_description = ['Agendamento realizado online.', observations].compact.join(' ').strip

      event_custom_attrs = { source: 'public_booking' }
      event_custom_attrs[:treatment] = service.name if service
      event_custom_attrs[:observations] = observations if observations.present?

      # Bookings concorrentes para o mesmo profissional ficam serializados
      # pelo `pg_advisory_xact_lock` por `user_id` (9.2). Tudo dentro da
      # transação é tudo-ou-nada, evitando AgendaEvent sem PatientAppointment.
      # Etapas:
      #   1. Advisory lock — bloqueia outros bookings desse profissional.
      #   2. Revalidação `calculate_slots` (9.1/9.10) — agora dentro do lock,
      #      lê estado mais recente, sem janela TOCTOU.
      #   3. Resolve/cria Contact (9.8/9.15) — savepoint próprio com retry.
      #   4. ContactInbox (9.3) — idempotente via ContactInboxBuilder.
      #   5. Patient (9.3) — find_or_create por (account, contact).
      #   6. AgendaEvent.
      #   7. PatientAppointment (9.3) — `avaliacao` se paciente novo, `retorno`.
      # Resposta forbidden (`allow_new_patients=false`) é tratada via throw,
      # não exception — `resolve_or_create_contact` retornaria nil senão.
      event = nil
      slot_unavailable = false
      forbidden_new_patient = false

      ActiveRecord::Base.transaction do
        # 9.2 — serializa por profissional. `_xact_` libera no commit/rollback.
        # `hashtext` converte string em int32 estável; combinado com user_id,
        # gera chave única de lock que não colide com outros locks do sistema.
        ActiveRecord::Base.connection.execute(
          "SELECT pg_advisory_xact_lock(hashtext('agenda_event_book'), #{@user.id.to_i})"
        )

        # 9.1/9.10 — revalidação dentro do lock vê o estado pós-commit dos
        # bookings concorrentes (que estavam segurando o lock antes).
        requested_time = starts_at.strftime('%H:%M')
        available_times = calculate_slots(starts_at.to_date, service: service)
        unless available_times.include?(requested_time)
          slot_unavailable = true
          raise ActiveRecord::Rollback
        end

        contact = resolve_or_create_contact(
          cpf: cpf, phone: phone, email: email, full_name: full_name,
          allow_new: config.allow_new_patients
        )

        unless contact
          forbidden_new_patient = true
          raise ActiveRecord::Rollback
        end

        # PR-UX-3 (2026-05-15): NÃO cria mais ContactInbox automaticamente.
        # Decisão de produto: a clínica inicia conversa manualmente quando
        # precisar — evita poluir /conversations com pacientes que talvez
        # nem tenham WhatsApp no número informado.
        patient_record, patient_is_new = ensure_patient_for(
          contact, full_name: full_name, cpf: cpf, email: email, phone: phone
        )

        event = @account.agenda_events.create!(
          user_id: @user.id,
          contact_id: contact.id,
          agenda_service_id: service&.id,
          title: event_title,
          description: event_description,
          starts_at: starts_at,
          ends_at: ends_at,
          status: 'scheduled',
          event_type: 'consultation',
          custom_attributes: event_custom_attrs
        )

        PatientAppointment.create!(
          account_id: @account.id,
          patient_id: patient_record.id,
          professional_id: @user.id,
          agenda_event_id: event.id,
          appointment_type: patient_is_new ? 'avaliacao' : 'retorno',
          status: 'scheduled',
          scheduled_at: starts_at,
          ends_at: ends_at,
          duration_minutes: slot_duration,
          notes: observations
        )
      end

      if slot_unavailable
        render json: { error: 'Este horário não está mais disponível. Por favor, escolha outro horário.' },
               status: :conflict
      elsif forbidden_new_patient
        render json: { error: 'Apenas pacientes já cadastrados podem realizar agendamentos online.' },
               status: :forbidden
      else
        render json: {
          success: true,
          event_id: event.id,
          # Auditoria 9.11: token assinado para o paciente cancelar o próprio
          # agendamento depois sem precisar de login. Frontend salva no state
          # do step 4 e usa nos endpoints `booking/:token/...`.
          cancel_token: generate_cancel_token(event),
          message: "Agendamento confirmado para #{starts_at.strftime('%d/%m/%Y às %H:%M')}."
        }, status: :created
      end
    end

  rescue ActiveRecord::RecordInvalid => e
    # Falha de validação de model (Patient, AgendaEvent, PatientAppointment,
    # etc) — devolver os erros amigáveis para o front mostrar.
    render json: { error: "Erro ao salvar: #{e.record.errors.full_messages.join(', ')}" },
           status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique => e
    # Chega aqui significa que `resolve_or_create_contact` esgotou os retries
    # (9.8): bug, não estado esperado. Log com contexto para diagnóstico.
    Rails.logger.error(
      "[AgendaBooking] RecordNotUnique fora do retry de dedup: " \
      "account_id=#{@account&.id} public_id=#{params[:public_id]} msg=#{e.message}"
    )
    render json: { error: 'Não foi possível concluir o cadastro. Tente novamente em alguns instantes.' },
           status: :conflict
  rescue ActiveRecord::StatementInvalid, PG::Error => e
    # Erro de banco — pode ser timeout, deadlock, constraint nova etc.
    # Não vaza detalhe interno mas loga contexto suficiente para correlacionar.
    Rails.logger.error(
      "[AgendaBooking] DB error: account_id=#{@account&.id} " \
      "public_id=#{params[:public_id]} class=#{e.class} msg=#{e.message}"
    )
    render json: { error: 'Erro temporário. Por favor, tente novamente em alguns instantes.' },
           status: :service_unavailable
  rescue ActionController::ParameterMissing => e
    render json: { error: "Parâmetro ausente: #{e.param}" }, status: :unprocessable_entity
  rescue StandardError => e
    # Fallback final: erro inesperado. Inclui backtrace pra Sentry/Honeybadger
    # via `Rails.error.report` se a app tiver o reporter configurado (Rails
    # 7.1+ envia para qualquer reporter cadastrado, no-op se não tiver). Não
    # quebra o fluxo do paciente — devolve 500 amigável.
    Rails.logger.error(
      "[AgendaBooking] Unhandled #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    )
    Rails.error.report(e, context: {
      controller: self.class.name,
      action: 'book',
      account_id: @account&.id,
      public_id: params[:public_id]
    }) if Rails.respond_to?(:error)
    render json: { error: 'Erro interno. Tente novamente em alguns instantes.' },
           status: :internal_server_error
  end

  # Auditoria 9.11: detalhes do agendamento via token (paciente clica no link
  # de confirmação). Não revela dados sensíveis — só o que o paciente já sabe
  # (data/hora/profissional/serviço/status). Status `cancellable` evita ter
  # que duplicar a lógica no frontend.
  def booking_show
    render json: { event: serialize_booking(@event) }
  end

  # Auditoria 9.11: cancelamento pelo paciente. Aplica regras de janela mínima
  # (não permite cancelar dentro do `min_lead_time_minutes`), idempotência
  # (já cancelado vira no-op com 200, não 409), e preserva quem cancelou no
  # `custom_attributes` para auditoria.
  def booking_cancel
    reason = params[:reason].to_s.strip.presence

    # Idempotência — re-cancelar é no-op.
    if @event.status == 'cancelled'
      render json: { success: true, message: 'Agendamento já estava cancelado.', event: serialize_booking(@event) }
      return
    end

    why_blocked = cancellation_block_reason(@event)
    if why_blocked
      render json: { error: why_blocked }, status: :unprocessable_entity
      return
    end

    new_attrs = @event.custom_attributes.dup
    new_attrs['cancelled_via_public_link_at'] = Time.current.iso8601
    new_attrs['cancellation_reason'] = reason if reason

    # `update_columns` pula callbacks de timeline pra não duplicar (a UI
    # mostra status='cancelled' direto), e bumpa `updated_at` pra invalidar
    # ETag (lição da PR-C).
    @event.update_columns(
      status: 'cancelled',
      custom_attributes: new_attrs,
      updated_at: Time.current
    )

    render json: { success: true, message: 'Agendamento cancelado com sucesso.', event: serialize_booking(@event.reload) }
  end

  private

  # Auditoria 9.11: token assinado HMAC. Carrega o par (account_id, event_id)
  # — não-falsificável sem `secret_key_base`. Sem expiração explícita: paciente
  # pode tentar cancelar mesmo após o evento (`cancellation_block_reason`
  # decide o que é permitido).
  #
  # Serialização: JSON manual pra evitar problemas com YAML safe-load default
  # (Rails 7.x usa YAML por default no MessageVerifier e em modo strict não
  # permite deserializar Symbol/Hash arbitrário sem allow-list). JSON é
  # neutro e fica sempre dentro de tipos primitivos seguros.
  def generate_cancel_token(event)
    payload = { 'event_id' => event.id, 'account_id' => event.account_id }.to_json
    Rails.application.message_verifier(BOOKING_TOKEN_PURPOSE).generate(payload)
  end

  # Resolve o evento via token assinado. `unscoped` para ver mesmo eventos
  # soft-deletados (paciente pode querer ver estado depois que a clínica
  # removeu).
  def resolve_booking_token
    raw     = Rails.application.message_verifier(BOOKING_TOKEN_PURPOSE).verify(params[:token])
    payload = JSON.parse(raw)
    @event  = AgendaEvent.unscoped.find_by(id: payload['event_id'], account_id: payload['account_id'])
    raise ActiveRecord::RecordNotFound if @event.nil?

    @account = @event.account
    @user    = @event.user
  rescue ActiveSupport::MessageVerifier::InvalidSignature, JSON::ParserError, ActiveRecord::RecordNotFound
    render json: { error: 'Link inválido ou agendamento não encontrado.' }, status: :not_found
  end

  # Serializer mínimo do booking — só o que o paciente já conhece. Não
  # expõe `contact_id`, `user_id`, etc.
  def serialize_booking(event)
    {
      id: event.id,
      starts_at: event.starts_at.iso8601,
      ends_at: event.ends_at.iso8601,
      status: event.status,
      status_label: status_label_for(event.status),
      professional_name: event.user&.name,
      service_name: event.agenda_service&.name,
      deleted: event.deleted_at.present?,
      cancellable: cancellation_block_reason(event).nil?,
      cancellation_block_reason: cancellation_block_reason(event)
    }
  end

  STATUS_LABELS = {
    'scheduled'   => 'Agendado',
    'confirmed'   => 'Confirmado',
    'arrived'     => 'Chegou',
    'in_progress' => 'Em atendimento',
    'completed'   => 'Atendido',
    'no_show'     => 'Faltou',
    'cancelled'   => 'Cancelado'
  }.freeze

  def status_label_for(s)
    STATUS_LABELS[s.to_s] || s.to_s.humanize
  end

  # Regras para PODER cancelar:
  #   - status atual permite (não está `completed`/`no_show`/`in_progress`/`arrived`)
  #   - `starts_at` ainda respeita `min_lead_time_minutes` da conta
  #   - evento não está soft-deletado
  # Retorna mensagem amigável quando bloqueado, `nil` quando permitido.
  def cancellation_block_reason(event)
    return 'Este agendamento já foi removido.' if event.deleted_at.present?
    return 'Esta consulta já foi realizada.'        if event.status == 'completed'
    return 'Este agendamento foi marcado como falta.' if event.status == 'no_show'
    return 'Esta consulta já está em andamento.'    if %w[arrived in_progress].include?(event.status)

    config = @account.agenda_online_config
    min_lead = config&.min_lead_time_minutes.to_i
    return "Esta consulta começa em menos de #{min_lead} minutos — cancele entrando em contato com a clínica." \
      if event.starts_at < Time.zone.now + min_lead.minutes && event.starts_at >= Time.zone.now
    return 'Esta consulta já passou. Entre em contato com a clínica.' if event.starts_at < Time.zone.now

    nil
  end

  # Resolve profissional + conta a partir do `agenda_public_id`. A conta vem
  # do próprio profile (NOT NULL desde a migration 20260514100001), não de
  # `@user.accounts.first` — multi-conta deixa de ser ambíguo: cada profile
  # representa um par (user, conta) específico.
  def fetch_user
    profile = BeclinicCore::UserProfile.find_by!(agenda_public_id: params[:public_id])
    @user = profile.user
    @account = profile.account
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Profissional não encontrado.' }, status: :not_found
  end

  # 9.12 — Validação CPF módulo 11. Algoritmo oficial da Receita Federal.
  # Rejeita: comprimento != 11, todos os dígitos iguais (00000000000, etc),
  # ou DV1/DV2 que não fecham. Recebe a string já normalizada (só dígitos).
  def valid_cpf?(cpf)
    return false if cpf.blank? || cpf.length != 11
    return false if cpf.chars.uniq.size == 1 # 00000000000, 11111111111, ...

    digits = cpf.chars.map(&:to_i)

    sum1 = (0..8).sum { |i| digits[i] * (10 - i) }
    dv1 = (sum1 * 10) % 11
    dv1 = 0 if dv1 == 10
    return false unless dv1 == digits[9]

    sum2 = (0..9).sum { |i| digits[i] * (11 - i) }
    dv2 = (sum2 * 10) % 11
    dv2 = 0 if dv2 == 10
    dv2 == digits[10]
  end

  # Retorna o `AgendaService` escolhido pelo paciente, escopado por
  # `account_id` e `kept` (nunca soft-deletado). Retorna `nil` se o ID
  # não veio, é inválido, ou não pertence à conta — nesses casos o fluxo
  # cai pro comportamento legado (sem serviço, duração = slot_interval).
  #
  # 9.7: também devolve `nil` se o serviço tem vínculos `agenda_service_users`
  # e `@user` NÃO está entre os vinculados. Assim, paciente que mande
  # `service_id` de um serviço que esse profissional não oferece (curl direto
  # ou client desatualizado) cai no fallback "sem serviço" em vez de criar
  # `AgendaEvent` inconsistente (`agenda_service_id` de Dr. B com
  # `user_id` de Dr. A).
  def fetch_service(service_id)
    return nil if service_id.blank?
    service = @account.agenda_services.kept.find_by(id: service_id)
    return nil if service.nil?

    unless service.offered_by?(@user.id)
      # Fail-soft: cai no fluxo legado (sem `agenda_service_id`) em vez de
      # bloquear o booking. Cliente desatualizado ou curl direto não fica
      # com 422 indecifrável — mas a inconsistência é logada para a clínica
      # investigar via Kibana/Grafana se aparecer com frequência.
      Rails.logger.warn(
        "[AgendaBooking] Service rejected: service_id=#{service.id} " \
        "not offered by user_id=#{@user.id} (account_id=#{@account.id}, " \
        "public_id=#{params[:public_id]}). Falling back to default duration."
      )
      return nil
    end

    service
  end

  # 9.7: lista de serviços ofertados por `@user` neste link público.
  # Inclui serviços sem nenhum vínculo (compat) E serviços vinculados a esse
  # user. Numa query só via LEFT JOIN + filtro `OR`.
  def services_for_current_user
    @account.agenda_services
            .kept
            .left_joins(:agenda_service_users)
            .where('agenda_service_users.id IS NULL OR agenda_service_users.user_id = ?', @user.id)
            .distinct
            .order(:position, :created_at)
  end

  # Dedup robusta de Contact (auditoria 9.8 + 9.15).
  #
  # Race condition: dois POSTs simultâneos com paciente novo passariam no
  # `find_by` retornando nil e ambos chegariam em `.create!` — o segundo
  # explodia em 500. Aqui: `transaction(requires_new: true)` + `rescue
  # RecordNotUnique` + retry lookup. Padrão idêntico ao
  # `ContactInboxWithContactBuilder`.
  #
  # Merge não-destrutivo (cenário D do §3 + bug do AgendaEvent #8327):
  # quando o Contact existe, dados do form NÃO sobrescrevem o que já está
  # no banco — só preenchem campos vazios. CPF diferente do registrado
  # vira warning, não overwrite — paciente A não pode "roubar" o cadastro
  # de B mandando CPF de B junto do telefone de A.
  #
  # Retorna o Contact ou `nil` se a clínica não permite novos pacientes.
  def resolve_or_create_contact(cpf:, phone:, email:, full_name:, allow_new:)
    phone_e164 = phone.present? ? "+55#{phone}" : nil

    attempts = 0
    begin
      attempts += 1
      ActiveRecord::Base.transaction(requires_new: true) do
        contact = find_existing_contact(cpf: cpf, phone_e164: phone_e164, email: email)

        if contact
          merge_contact_with_form_data(contact, cpf: cpf, email: email, full_name: full_name)
          contact
        else
          return nil unless allow_new

          @account.contacts.create!(
            name: full_name,
            phone_number: phone_e164,
            email: email,
            custom_attributes: cpf.present? ? { 'cpf' => cpf } : {}
          )
        end
      end
    rescue ActiveRecord::RecordNotUnique
      # Outro request criou o Contact entre o nosso find e o create.
      # Retry no lookup — agora vai achar e cair no merge.
      raise if attempts >= 2
      retry
    end
  end

  def find_existing_contact(cpf:, phone_e164:, email:)
    contact = nil
    contact = @account.contacts.where("custom_attributes->>'cpf' = ?", cpf).first if cpf.present?
    contact ||= @account.contacts.find_by(phone_number: phone_e164) if phone_e164.present?
    contact ||= @account.contacts.find_by(email: email) if email.present?
    contact
  end

  # Atualiza um Contact existente com dados do form preservando o que já
  # está no banco (merge conservador). Loga toda mudança em `Rails.logger`
  # com `contact_id` para auditoria sem schema novo.
  def merge_contact_with_form_data(contact, cpf:, email:, full_name:)
    changes = {}

    changes[:name]  = full_name if contact.name.blank? && full_name.present?
    changes[:email] = email     if contact.email.blank? && email.present?

    if cpf.present?
      stored_cpf = contact.custom_attributes['cpf'].to_s
      if stored_cpf.blank?
        changes[:custom_attributes] = contact.custom_attributes.merge('cpf' => cpf)
      elsif stored_cpf != cpf
        # Conflito intencional ou erro de digitação — manter o do banco e logar.
        # Sem PII no log: só `contact_id` e que houve mismatch.
        Rails.logger.warn(
          "[AgendaBooking] CPF mismatch ignored for contact_id=#{contact.id} " \
          "account_id=#{@account.id} public_id=#{params[:public_id]}"
        )
      end
    end

    return if changes.empty?

    contact.update!(changes)
    Rails.logger.info(
      "[AgendaBooking] Contact merged contact_id=#{contact.id} " \
      "account_id=#{@account.id} fields=#{changes.keys.inspect}"
    )
  end

  # `ensure_contact_inbox` removido na PR-UX-3 (2026-05-15). Decisão de
  # produto: vínculo do Contact com inbox WhatsApp passa a ser manual —
  # clínica busca o número e inicia conversa só quando precisar, evitando
  # poluir /conversations com pacientes que talvez nem tenham WhatsApp.

  # Auditoria 9.3 — garante 1 Patient por (account, contact). Retorna o
  # par `[patient, was_just_created]` para que `book` saiba decidir o
  # `appointment_type` (avaliacao p/ novo, retorno p/ existente).
  #
  # Em Patient existente aplica merge não-destrutivo (mesmo padrão de
  # `merge_contact_with_form_data` em 9.15): só preenche `cpf`/`email`/
  # `phone` quando estão vazios. Nome NUNCA é sobrescrito — preserva o
  # cadastro que a clínica fez no dashboard.
  def ensure_patient_for(contact, full_name:, cpf:, email:, phone:)
    phone_e164 = phone.present? ? "+55#{phone}" : nil
    existing = Patient.active.find_by(account_id: @account.id, contact_id: contact.id)

    if existing
      changes = {}
      changes[:cpf]   = cpf        if existing.cpf.blank?   && cpf.present?
      changes[:email] = email      if existing.email.blank? && email.present?
      changes[:phone] = phone_e164 if existing.phone.blank? && phone_e164.present?
      existing.update!(changes) if changes.any?
      [existing, false]
    else
      patient = Patient.create!(
        account_id: @account.id,
        contact_id: contact.id,
        responsible_professional_id: @user.id,
        name: full_name,
        cpf: cpf.presence,
        email: email,
        phone: phone_e164,
        patient_status: 'novo'
      )
      [patient, true]
    end
  end

  # Generates available time slots for the given date, respecting all
  # AgendaSetting rules configured by the clinic in the dashboard:
  #   - slot_interval_minutes (15/30/60) — grid step AND event duration.
  #   - week_days[].enabled / start / end — working hours per weekday.
  #   - week_days[].lunchStart / lunchEnd + block_lunch_break — skips lunch.
  #   - holidays (status: 'closed') — returns no slots on holidays.
  #   - exceptions (folgas/exceções) — returns no slots inside the range.
  # Falls back to inbox-level WorkingHour only if AgendaSetting is missing,
  # preserving backwards-compat for accounts that haven't configured it yet.
  DOW_KEYS = %w[sun mon tue wed thu fri sat].freeze

  # `events_cache` (auditoria 9.13): array opcional de tuplas [starts_at, ends_at]
  # já buscadas em bulk para um range maior. Quando passado, evita a query
  # individual do dia — usado pelo endpoint `slots_range` para escalar O(1)
  # em queries no banco mesmo cobrindo um mês inteiro.
  def calculate_slots(date, service: nil, events_cache: nil)
    setting = @account.agenda_setting
    config  = @account.agenda_online_config

    future_limit = (config&.future_limit_days || 60).to_i
    return [] if date > Date.current + future_limit.days

    open_str, close_str, lunch_start_str, lunch_end_str = working_window_for(date, setting)
    return [] if open_str.blank? || close_str.blank?
    return [] if blocked_by_holiday?(date, setting)
    return [] if blocked_by_exception?(date, setting)

    slot_interval  = (setting&.slot_interval_minutes || 60).to_i
    # Quando o paciente escolhe um serviço, o evento ocupa
    # `service.duration_minutes` — pode ser diferente do passo da grade
    # (ex.: grade de 30min, serviço de 45min). O slot só é oferecido se
    # a janela inteira `[start, start + event_duration]` cabe no expediente,
    # não cruza almoço e está livre de eventos.
    event_duration = (service&.duration_minutes || slot_interval).to_i
    block_lunch    = setting&.block_lunch_break == true

    slots = []

    Time.use_zone('America/Sao_Paulo') do
      min_lead = config&.min_lead_time_minutes.to_i
      earliest_bookable = Time.zone.now + min_lead.minutes

      open_time  = Time.zone.parse("#{date} #{open_str}")
      close_time = Time.zone.parse("#{date} #{close_str}")
      lunch_start = lunch_start_str.present? ? Time.zone.parse("#{date} #{lunch_start_str}") : nil
      lunch_end   = lunch_end_str.present?   ? Time.zone.parse("#{date} #{lunch_end_str}")   : nil

      # 9.17 — Bulk fetch dos eventos do dia. Antes: 1 EXISTS por slot
      # (~48 queries/dia em grade de 15min). Agora: 1 query que traz todos
      # os eventos com overlap na janela [open_time, close_time], e o loop
      # faz interseção em memória. Usa o índice parcial
      # `index_agenda_events_kept_on_account_user_starts_at` da 9.16.
      # `.pluck` evita instanciar ActiveRecord objects (só precisamos dos
      # 2 timestamps).
      #
      # 9.13 — quando `events_cache` é passado pelo `slots_range`, filtra
      # localmente em vez de fazer query nova (1 query pro range inteiro).
      day_events = if events_cache
                     events_cache.select { |s, e| s < close_time && e > open_time }
                   else
                     @account.agenda_events.kept
                             .where(user_id: @user.id)
                             .where('starts_at < ? AND ends_at > ?', close_time, open_time)
                             .pluck(:starts_at, :ends_at)
                   end

      current_time = open_time

      # `<=` na guarda do while: aceita slot terminando exatamente no
      # fechamento. O step de avanço é `slot_interval` (grade), mas a
      # janela ocupada é `event_duration` (serviço).
      while current_time + event_duration.minutes <= close_time
        slot_end   = current_time + event_duration.minutes
        next_start = current_time + slot_interval.minutes

        if current_time < earliest_bookable
          current_time = next_start
          next
        end

        if block_lunch && lunch_start && lunch_end &&
           current_time < lunch_end && slot_end > lunch_start
          current_time = next_start
          next
        end

        # Overlap check em memória. Critério idêntico ao EXISTS original:
        # `event.starts_at < slot_end AND event.ends_at > current_time`.
        has_event = day_events.any? { |s, e| s < slot_end && e > current_time }

        slots << current_time.strftime('%H:%M') unless has_event

        current_time = next_start
      end
    end

    slots
  end

  # Returns [open_str, close_str, lunch_start_str, lunch_end_str] for the
  # given date, preferring AgendaSetting.week_days (clinic-managed) over
  # the inbox-level WorkingHour fallback.
  def working_window_for(date, setting)
    if setting&.week_days.is_a?(Array)
      day_id = DOW_KEYS[date.wday]
      day_cfg = setting.week_days.find { |d| d['id'] == day_id }
      if day_cfg
        return [nil, nil, nil, nil] unless day_cfg['enabled']
        return [
          day_cfg['start'],
          day_cfg['end'],
          day_cfg['lunchStart'],
          day_cfg['lunchEnd']
        ]
      end
    end

    wh = @account.working_hours
                 .where(day_of_week: date.wday, closed_all_day: false)
                 .first
    return [nil, nil, nil, nil] unless wh
    return [nil, nil, nil, nil] if wh.open_hour.nil? || wh.close_hour.nil?

    [
      "#{wh.open_hour}:#{format('%02d', wh.open_minutes.to_i)}",
      "#{wh.close_hour}:#{format('%02d', wh.close_minutes.to_i)}",
      nil,
      nil
    ]
  end

  def blocked_by_holiday?(date, setting)
    return false unless setting&.holidays.is_a?(Array)
    day_month = "#{date.day.to_s.rjust(2, '0')}/#{date.month.to_s.rjust(2, '0')}"
    setting.holidays.any? do |h|
      h['status'] == 'closed' && h['date'].to_s.start_with?(day_month)
    end
  end

  def blocked_by_exception?(date, setting)
    return false unless setting&.exceptions.is_a?(Array)
    setting.exceptions.any? do |ex|
      next false if ex['start'].blank? || ex['end'].blank?
      ex_start = (Date.parse(ex['start']) rescue nil)
      ex_end   = (Date.parse(ex['end'])   rescue nil)
      next false unless ex_start && ex_end
      date >= ex_start && date <= ex_end
    end
  end
end
