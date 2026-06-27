require 'csv'

module Migration
  class ClinicorpAgendaImporter
    BATCH_SIZE = 250
    BR_TZ = 'America/Sao_Paulo'.freeze
    NOTES_ATTR_NAME = 'Notas (Clinicorp)'.freeze

    # PR-D (auditoria 2026-05-15): adicionados CHECKOUT/IN_SESSION/LATE que
    # caíam no fallback `scheduled`, levando 118 eventos para o status errado.
    # CHECKOUT (paciente saiu) é finalização → `completed`; IN_SESSION
    # (paciente no atendimento) → `in_progress`; LATE (atrasado) → `arrived`
    # como aproximação melhor que `scheduled` (paciente está na clínica, só
    # demorou). LATE também poderia justificar um status próprio, mas não
    # vale alargar o enum por 1 evento histórico.
    STATUS_MAP = {
      ''             => 'scheduled',
      'SCHEDULED'    => 'scheduled',
      'PENDING'      => 'scheduled',
      'CONFIRMED'    => 'confirmed',
      'CONFIRMADO'   => 'confirmed',
      'ARRIVED'      => 'arrived',
      'CHECKED_IN'   => 'arrived',
      'CHECKEDIN'    => 'arrived',
      'LATE'         => 'arrived',
      'IN_PROGRESS'  => 'in_progress',
      'INPROGRESS'   => 'in_progress',
      'STARTED'      => 'in_progress',
      'IN_SESSION'   => 'in_progress',
      'ATTENDED'     => 'completed',
      'COMPLETED'    => 'completed',
      'DONE'         => 'completed',
      'FINISHED'     => 'completed',
      'CHECKOUT'     => 'completed',
      'NO_SHOW'      => 'no_show',
      'NOSHOW'       => 'no_show',
      'MISSED'       => 'no_show',
      'CANCELED'     => 'cancelled',
      'CANCELLED'    => 'cancelled'
    }.freeze

    # PR auditoria 2026-05-21: classificação de `event_type` a partir do CSV
    # Clinicorp. Antes desta PR, todo evento importado entrava como
    # 'appointment' (Compromisso) — bug que afetou a conta 21 (46.102 eventos,
    # corrigidos via `update_all` manual) e silenciava o recall proativo do
    # AI Agent (que filtra por event_type='consultation').
    #
    # Causa raiz: a coluna `CategoryDescription` do XLSX Clinicorp era lida e
    # armazenada como custom attribute "Categoria", mas o importer ignorava
    # esse sinal pra decidir o tipo do evento.
    #
    # Regra atual (validada com os valores reais do `plugins/xls/Appointment.csv`):
    #
    #   - 'Intervalo', 'Intervalo Almoço', 'Almoço', 'Pausa', 'Bloqueio'
    #       → agenda_block (literalmente bloqueia o slot, sem paciente)
    #   - 'Reunião', 'Compromisso', 'Evento'
    #       → appointment (compromisso pessoal do dentista)
    #   - Sem paciente (defesa pra futuro: hoje a linha é skipped antes)
    #       → agenda_block
    #   - Qualquer outra coisa COM paciente
    #       → consultation (default em clínica odonto = consulta clínica)
    #
    # Listas conservadoras de propósito: categorias não-óbvias ('Manutenção',
    # 'Particular', 'Avaliação', 'Retorno', 'Odonto', 'Consulta', 'Cirurgia')
    # ficam como `consultation` porque a clínica atende paciente nesses slots.
    # Se aparecer categoria nova que deva ser tratada diferente, só adicionar
    # na lista correspondente — sem mexer no fluxo de importação.
    #
    # Métodos de classe (não de instância) pra serem reusados pelo backfill
    # rake task `migration:backfill_event_type[account_id]`.
    BLOCK_CATEGORIES = %w[
      intervalo
      intervalo_almoco
      almoco
      pausa
      bloqueio
    ].freeze

    APPOINTMENT_CATEGORIES = %w[
      reuniao
      compromisso
      evento
    ].freeze

    def self.classify_event_type(category:, patient_present:)
      norm = normalize_category_for_match(category)
      return 'agenda_block' if BLOCK_CATEGORIES.include?(norm)
      return 'appointment' if APPOINTMENT_CATEGORIES.include?(norm)
      return 'agenda_block' unless patient_present
      'consultation'
    end

    # "Intervalo Almoço" → "intervalo_almoco"; "Reunião" → "reuniao".
    # ASCII-only + underscore pra as listas acima ficarem legíveis em código.
    def self.normalize_category_for_match(value)
      return nil if value.to_s.strip.empty?
      s = value.to_s.strip.downcase
      s = s.tr('áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')
      s.gsub(/\s+/, '_')
    end

    def initialize(migration_run, csv_content)
      @run = migration_run
      @csv_content = csv_content
      @account = migration_run.account
      @errors = []
      @counters = { created: 0, updated: 0, skipped: 0, errors: 0, processed: 0 }
      @user_cache = {}
      @patient_cache = {}
      @category_attr = nil
      @notes_attr = nil
      # PR audit 2026-05-21: mapa "string original do CSV" → "forma canonical
      # preservada no dropdown e no JSONB". Resolve dedup case+accent
      # insensitive (Avaliação == AVALIAÇÃO == avaliacao) sem perder a forma
      # bonita escolhida pela 1ª aparição. Dedup semântico (Avaliação vs
      # AVALIAÇÃO (CRC)) continua sendo manual via migration:dedupe_categories.
      @category_canonical_map = {}
    end

    # AgendaCustomAttribute "Categoria" — created as a SELECT (dropdown) so the
    # event modal shows a friendly picker instead of free text. Options come
    # from the unique CategoryDescription values in the imported CSV; the union
    # of existing options + new options is preserved on re-imports.
    #
    # PR audit 2026-05-21: agora chamado APÓS `build_canonical_map` (que pré-
    # popula `@category_canonical_map` lendo opções já existentes no dropdown
    # se houver re-importação). Recebe a lista de valores canonical
    # (deduplicados case+accent-insensitive) — clinic vê dropdown limpo sem
    # variantes só por digitação.
    def ensure_category_custom_attribute(category_values)
      values = category_values.compact_blank.uniq
      attr = AgendaCustomAttribute.where(account_id: @account.id)
                                  .where('LOWER(name) = ?', 'categoria').first
      if attr
        existing = attr.options.to_s.split(',').map(&:strip).reject(&:blank?)
        merged = (existing | values).uniq
        attr.update!(field_type: 'select', options: merged.join(',')) if attr.field_type != 'select' || merged != existing
      else
        attr = AgendaCustomAttribute.create!(
          account_id: @account.id,
          name: 'Categoria',
          field_type: 'select',
          required: false,
          options: values.join(','),
          position: AgendaCustomAttribute.where(account_id: @account.id).count
        )
      end
      attr
    end

    # Atributo personalizado para o campo `Notes` do XLSX Clinicorp — texto livre
    # da secretária ("trazer raio-X", "alergia a anestesia"). Antes da PR-B
    # (auditoria agendamento público §11), `Notes` ia direto para `description`
    # do AgendaEvent — misturando com `Procedures`. Agora cada um vai pro seu
    # lugar: Procedures → description; Notes → este atributo (textarea).
    def ensure_notes_custom_attribute
      attr = AgendaCustomAttribute.where(account_id: @account.id)
                                  .where('LOWER(name) = ?', NOTES_ATTR_NAME.downcase).first
      return attr if attr

      AgendaCustomAttribute.create!(
        account_id: @account.id,
        name: NOTES_ATTR_NAME,
        field_type: 'textarea',
        required: false,
        position: AgendaCustomAttribute.where(account_id: @account.id).count
      )
    end

    def call
      rows = parse_csv
      @run.update!(total_rows: rows.size, processed_rows: 0)

      categories = rows.map { |r| r['CategoryDescription'].to_s.strip }
      # PR audit 2026-05-21: dedup trivial case+accent-insensitive ANTES de
      # criar o dropdown e antes de gravar nos eventos. `build_canonical_map`
      # preserva a 1ª forma vista pra cada chave normalizada e respeita
      # opções já existentes no dropdown (re-importação).
      @category_canonical_map = build_canonical_map(categories.compact_blank)
      canonical_values = @category_canonical_map.values.uniq
      @category_attr = ensure_category_custom_attribute(canonical_values)
      @notes_attr    = ensure_notes_custom_attribute

      rows.each_slice(BATCH_SIZE).with_index do |slice, batch_index|
        slice.each_with_index do |row, idx|
          line_number = (batch_index * BATCH_SIZE) + idx + 2
          process_row(row, line_number)
          @counters[:processed] += 1
        end
        flush_progress!
      end

      flush_progress!(final: true)
      @counters
    end

    private

    def parse_csv
      content = @csv_content.to_s.sub(/\A\xEF\xBB\xBF/, '')
      delim = detect_delimiter(content)
      CSV.parse(content, headers: true, col_sep: delim, liberal_parsing: true).map(&:to_h)
    end

    def detect_delimiter(content)
      first_line = content.lines.first.to_s
      counts = { ',' => first_line.count(','), ';' => first_line.count(';'), "\t" => first_line.count("\t") }
      counts.max_by { |_, v| v }.first
    end

    def process_row(row, line_number)
      h = row.transform_keys { |k| k.to_s.strip }

      patient_name = h['PatientName'].to_s.strip
      dentist_name = h['DentistName'].to_s.strip
      starts_at, ends_at = parse_window(h['date'], h['fromTime'], h['toTime'])

      if starts_at.nil? || ends_at.nil?
        @counters[:skipped] += 1
        log_error(line_number, 'Data ou horário inválido — linha ignorada.')
        return
      end

      if patient_name.blank?
        @counters[:skipped] += 1
        log_error(line_number, 'Sem PatientName — linha ignorada.')
        return
      end

      contact, patient = find_or_create_contact(patient_name, h['MobilePhone'])
      user = find_user(dentist_name)

      # PR-B (auditoria 2026-05-15): Procedures e Notes do XLSX Clinicorp passam
      # a ter destinos separados e corretos:
      #   - Procedures (procedimento daquela consulta — texto livre) → description
      #     do evento. Antes virava `AgendaService` poluindo o catálogo (2.048
      #     services criados na conta 31 antes desta PR).
      #   - Notes (observação livre da secretária) → atributo personalizado
      #     "Notas (Clinicorp)". Antes ia pra description, misturando com
      #     Procedures depois desta correção.
      #   - Importer NÃO cria mais AgendaService. Catálogo de serviços fica sob
      #     controle exclusivo da clínica (Configurações → Serviços + 9.7).
      proc_text  = h['Procedures'].to_s.strip.presence
      notes_text = h['Notes'].to_s.strip.presence

      raw_status = h['Status'].to_s.strip.upcase
      status = STATUS_MAP[raw_status] || 'scheduled'

      # PR-D: semântica do XLSX Clinicorp tem 2 flags distintas, não 1:
      #   - `Canceled=X` → paciente cancelou, mas evento fica visível no
      #     calendário com status="cancelled" (histórico clínico preserva).
      #   - `Deleted=X` → clínica deletou o evento (botão lixeira no
      #     Clinicorp), some do calendário → soft-delete no Klivy.
      # Antes a importação tratava ambos como `cancelled`, perdendo a
      # distinção. Aplicado abaixo após criar/atualizar o evento (precisamos
      # do `id` para soft-delete via `update_columns`).
      canceled_flag = truthy?(h['Canceled'])
      deleted_flag  = truthy?(h['Deleted'])
      status = 'cancelled' if canceled_flag

      external_id = h['id'].to_s.strip
      title = patient_name.presence || 'Compromisso'

      # PR auditoria 2026-05-21: classifica event_type a partir de
      # CategoryDescription + presença de paciente. Antes era hardcoded
      # 'appointment'. Calculado UMA vez aqui e aplicado tanto no create
      # quanto no update — re-importar o CSV agora conserta eventos
      # antigos (antes o update path ignorava event_type).
      event_type = self.class.classify_event_type(
        category: h['CategoryDescription'],
        patient_present: patient_name.present?
      )

      # PR auditoria 2026-05-21: `find_by(custom_attributes: { … })` no Rails 7
      # faz EQUALITY do JSONB inteiro (não containment), e como `custom_attributes`
      # tem 11+ chaves (`source, attr_<id>, priority, patient_*, clinicorp_*, …`)
      # nunca casa. Resultado: re-importação tratava todo evento existente como
      # novo → tentava INSERT → batia no unique index BE-7 anti-double-booking
      # → contava como erro. Eventos da 1ª importação ficavam sem update do
      # `user_id` (sintoma na Streit conta #12274: 18.117 eventos sem dentista).
      # Fix: query JSONB explícita por `->>`. Resolve a idempotência real.
      event = AgendaEvent.where(account_id: @account.id)
                         .where("custom_attributes->>'source' = ? AND custom_attributes->>'external_id' = ?", 'clinicorp', external_id)
                         .first if external_id.present?
      if event
        event.update!(
          title: title,
          description: proc_text,
          starts_at: starts_at,
          ends_at: ends_at,
          status: status,
          event_type: event_type,
          user_id: user&.id,
          contact_id: contact&.id,
          custom_attributes: build_custom_attrs(h, external_id, contact, patient, notes_text)
        )
        @counters[:updated] += 1
      else
        event = AgendaEvent.create!(
          account_id: @account.id,
          user_id: user&.id,
          contact_id: contact&.id,
          title: title,
          description: proc_text,
          starts_at: starts_at,
          ends_at: ends_at,
          status: status,
          event_type: event_type,
          custom_attributes: build_custom_attrs(h, external_id, contact, patient, notes_text)
        )
        @counters[:created] += 1
      end

      # PR-D: aplica soft-delete por Clinicorp Deleted=X. `update_columns`
      # pra evitar disparar callbacks (que poderiam recriar timeline events).
      # Re-importações com Deleted=X em row antes ativa também aplicam o
      # soft-delete; reverso (un-delete) requer ação manual — preferimos não
      # automatizar pra não atropelar correção feita pela clínica no Klivy.
      if deleted_flag && event.deleted_at.nil?
        event.update_columns(deleted_at: Time.current, updated_at: Time.current)
      end

      # PR-UX-3 (2026-05-15): popula PatientAppointment pra cada AgendaEvent
      # importado — alimenta prontuário, timeline e relatórios clínicos
      # ("Meus Agendamentos" do paciente no record). Só cria pra eventos
      # ativos (decisão B1 — pula soft-deletados, lixo histórico não
      # deveria aparecer no prontuário). Idempotente: pula se já existe.
      ensure_patient_appointment(event, patient) if patient && event.deleted_at.nil?

      log_info(line_number, "Sem dentista identificado: '#{dentist_name}'.") if dentist_name.present? && user.nil?
    rescue StandardError => e
      @counters[:errors] += 1
      log_error(line_number, "#{e.class}: #{e.message}")
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Helpers
    # ──────────────────────────────────────────────────────────────────────────

    # PR-D: aceita "X" / "x" (notação que o XLSX Clinicorp usa nas colunas
    # `Canceled` e `Deleted` em vez de "true"). Sem isso, 1.143 linhas
    # marcadas como deletadas no Clinicorp eram importadas como agendamentos
    # ativos no Klivy.
    def truthy?(val)
      %w[true 1 yes sim t x].include?(val.to_s.strip.downcase)
    end

    # PR-UX-3: garante 1 PatientAppointment por AgendaEvent. Idempotente
    # (via `find_or_create_by` no `agenda_event_id`), seguro em re-importações.
    def ensure_patient_appointment(event, patient)
      existing = PatientAppointment.find_by(agenda_event_id: event.id)
      return if existing

      duration = ((event.ends_at - event.starts_at) / 60).to_i
      duration = 60 if duration <= 0

      PatientAppointment.create!(
        account_id: @account.id,
        patient_id: patient.id,
        professional_id: event.user_id,
        agenda_event_id: event.id,
        appointment_type: determine_appointment_type(event),
        status: map_appointment_status(event.status),
        scheduled_at: event.starts_at,
        ends_at: event.ends_at,
        duration_minutes: duration
      )
    end

    # A2 (decisão de produto 2026-05-15): primeiro evento cronológico de
    # cada paciente = `avaliacao`; restante = `retorno`. Olha o DB pra
    # achar evento anterior; se houver, o atual já não é mais primeira
    # visita. Funciona corretamente quando o CSV é processado em ordem
    # (Clinicorp exporta cronologicamente); em CSV out-of-order, o
    # backfill da rake task corrige a posteriori.
    def determine_appointment_type(event)
      has_earlier = AgendaEvent.where(account_id: @account.id, contact_id: event.contact_id)
                               .where('starts_at < ?', event.starts_at)
                               .where.not(id: event.id)
                               .exists?
      has_earlier ? 'retorno' : 'avaliacao'
    end

    # Mapeia AgendaEvent.status (7 valores) → PatientAppointment.status
    # (8 valores). Eventos "em curso" / "futuros" → scheduled; concluído
    # → done; falta → no_show; cancelamento → canceled.
    APPT_STATUS_MAP = {
      'scheduled'   => 'scheduled',
      'confirmed'   => 'scheduled',
      'arrived'     => 'scheduled',
      'in_progress' => 'scheduled',
      'completed'   => 'done',
      'no_show'     => 'no_show',
      'cancelled'   => 'canceled'
    }.freeze

    def map_appointment_status(event_status)
      APPT_STATUS_MAP[event_status.to_s] || 'scheduled'
    end

    # The Clinicorp `date` column is an ISO-8601 string with Z that, decoded into
    # America/Sao_Paulo, gives the local calendar day at 00:00. Combine that day
    # with `fromTime` / `toTime` (HH:MM, 24h) in the local zone.
    def parse_window(date_iso, from_time, to_time)
      return [nil, nil] if date_iso.blank? || from_time.blank? || to_time.blank?

      tz = ActiveSupport::TimeZone[BR_TZ]
      utc = Time.iso8601(date_iso.to_s)
      local_day = utc.in_time_zone(tz).to_date
      starts = tz.parse("#{local_day} #{from_time}")
      ends   = tz.parse("#{local_day} #{to_time}")
      ends   = ends + 1.day if ends < starts # crosses midnight
      [starts, ends]
    rescue StandardError
      [nil, nil]
    end

    def find_user(name)
      return nil if name.blank?
      return @user_cache[name] if @user_cache.key?(name)

      norm = normalize(name)
      candidate = @account.users.find { |u| normalize(u.name) == norm }
      @user_cache[name] = candidate
    end

    def find_or_create_contact(name, mobile_phone)
      cache_key = "#{normalize(name)}|#{mobile_phone}"
      return @patient_cache[cache_key] if @patient_cache.key?(cache_key)

      norm = normalize(name)
      phone = normalize_phone(mobile_phone)

      patient = Patient.where(account_id: @account.id, deleted_at: nil)
                       .where('LOWER(name) = ?', norm).first
      contact = patient&.contact

      contact ||= Contact.where(account_id: @account.id)
                         .where('LOWER(name) = ?', norm).first

      # PR-D: fallback por `phone_number` para cobrir casos onde o XLSX
      # Clinicorp tem o MESMO paciente em linhas diferentes com pequenas
      # variações no nome (espaços, acentos, capitalização). Sem isso, a 2ª
      # linha falhava com `Phone number já está em uso` (UNIQUE em
      # `contacts(phone_number, account_id)`) — causa de 199+ erros na
      # importação de Mamedes. Reusa o contato existente, em vez de tentar
      # criar duplicado.
      contact ||= Contact.where(account_id: @account.id, phone_number: phone).first if phone.present?

      if contact.nil?
        contact = Contact.create!(
          account_id: @account.id,
          name: name,
          phone_number: phone,
          additional_attributes: { source: 'migration_clinicorp_agenda' }
        )
      end

      # Ensure a Patient row exists and is linked to the Contact so the
      # AgendaEventModal can show it correctly and the timeline keeps working.
      if patient.nil?
        patient = Patient.create!(
          account_id: @account.id,
          name: name,
          phone: contact.phone_number,
          contact_id: contact.id,
          origin: 'migration_clinicorp_agenda'
        )
      elsif patient.contact_id.nil?
        patient.update_columns(contact_id: contact.id)
      end

      @patient_cache[cache_key] = [contact, patient]
    end

    # PR-B (2026-05-15): NÃO cria mais AgendaService. Procedures vai para
    # description do evento, Notes vai para custom attribute. Catálogo de
    # serviços fica sob controle exclusivo da clínica via UI.
    # `find_or_create_service` removida com a PR. `random_color`,
    # `SERVICE_COLOR_PALETTE` e `@service_cache` também — eram só usados aqui.

    def build_custom_attrs(row, external_id, contact, patient, notes_text)
      attrs = {
        'source' => 'clinicorp',
        'external_id' => external_id,
        # Display fields the AgendaEventModal expects for showing patient
        'patient_id' => patient&.id,
        'patient_name' => contact&.name,
        'patient_phone' => contact&.phone_number,
        'patient_avatar_url' => nil,
        # Service-id e treatment ficam nulos no fluxo Clinicorp pós-PR-B —
        # modal mostra "Selecione o tratamento". Clínica preenche manualmente
        # quando o agendamento virar plano de tratamento / consulta concluída.
        'treatment' => nil,
        'priority' => 'medium',
        'clinicorp_status' => row['Status'].to_s.strip.presence,
        'clinicorp_canceled' => truthy?(row['Canceled']),
        'clinicorp_deleted'  => truthy?(row['Deleted']),
        'cancel_reason' => row['CancelReason'].to_s.strip.presence,
        'cancel_by'     => row['CancelBy'].to_s.strip.presence,
        'canceled_date' => row['CanceledDate'].to_s.strip.presence,
        'mobile_phone' => row['MobilePhone'].to_s.strip.presence
      }.compact

      # Categoria as a real AgendaCustomAttribute (attr_<id>) so it appears in
      # the event modal under "Atributos Personalizados".
      # PR audit 2026-05-21: salva a forma CANONICAL (deduplicada
      # case+accent-insensitive) em vez do valor cru do CSV — garante que
      # eventos com "Avaliação" e "AVALIAÇÃO" no CSV gravem o MESMO valor no
      # JSONB, casando com a única opção do dropdown. Fallback pro original
      # se a string não estiver no map (caso raro: linha nova após o build).
      raw_category = row['CategoryDescription'].to_s.strip.presence
      if raw_category
        canonical = @category_canonical_map[raw_category] || raw_category
        attrs["attr_#{@category_attr.id}"] = canonical
      end

      # Notas — o `Notes` do XLSX que antes ia pra description.
      attrs["attr_#{@notes_attr.id}"] = notes_text if notes_text && @notes_attr
      attrs
    end

    def normalize_phone(value)
      digits = value.to_s.gsub(/\D/, '')
      return nil if digits.length < 8

      digits.start_with?('55') ? "+#{digits}" : "+55#{digits}"
    end

    def normalize(str)
      str.to_s.strip.downcase
    end

    # PR audit 2026-05-21: dedup trivial das CategoryDescription do CSV.
    # Recebe lista de strings, retorna Hash{ string_original => canonical }.
    # Canonical = primeira forma vista pra cada chave normalizada (case+accent
    # insensitive). Re-importação respeita opções já existentes no dropdown
    # da conta — pré-popula o índice com o que tá lá pra não trocar canonical
    # histórica por uma nova variação do CSV (estaria quebrando referência
    # nos eventos antigos).
    def build_canonical_map(values)
      canonical_by_key = {}
      existing_attr = AgendaCustomAttribute.where(account_id: @account.id)
                                           .where('LOWER(name) = ?', 'categoria').first
      if existing_attr
        existing_attr.options.to_s.split(',').map(&:strip).reject(&:blank?).each do |opt|
          canonical_by_key[normalize_for_dedupe(opt)] = opt
        end
      end

      map = {}
      values.each do |v|
        next if v.blank?
        key = normalize_for_dedupe(v)
        canonical_by_key[key] ||= v.strip  # 1ª forma vista vence (entre as não-existentes)
        map[v.strip] = canonical_by_key[key]
      end
      map
    end

    # Normalização pra match trivial: "AVALIAÇÃO  " e "avaliacao" e "Avaliação"
    # todas viram "avaliacao" (sem acento, sem case, sem extremos). NÃO mexe
    # em pontuação/parênteses propositalmente — "AVALIAÇÃO (CRC)" continua
    # distinto de "Avaliação" porque a distinção É semântica.
    def normalize_for_dedupe(s)
      s.to_s.strip.downcase.tr('áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')
    end

    def flush_progress!(final: false)
      @run.update_columns(
        processed_rows: @counters[:processed],
        created_count: @counters[:created],
        updated_count: @counters[:updated],
        skipped_count: @counters[:skipped],
        error_count: @counters[:errors],
        errors_log: @errors.last(200),
        updated_at: Time.current
      )
    end

    def log_error(line, message)
      @errors << { line: line, level: 'error', message: message }
    end

    def log_info(line, message)
      @errors << { line: line, level: 'info', message: message }
    end
  end
end
