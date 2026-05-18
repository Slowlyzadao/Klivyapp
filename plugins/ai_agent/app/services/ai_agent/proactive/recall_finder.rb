module AiAgent
  module Proactive
    # Encontra pacientes elegíveis pra recall proativo:
    #   - última `AgendaEvent` (consultation, completed) há ≥ N meses (default 6)
    #   - SEM agendamento futuro ativo (scheduled / pending_confirmation / confirmed)
    #   - SEM opt-out registrado em PatientMemory.preferences['recall_opt_out']
    #   - SEM recall já enviado nos últimos N dias (anti-spam)
    #
    # Reduz no-show 30–50% em benchmarks (Famulor, Neuwark 2026).
    #
    # Stateless — apenas lê. ProactiveOutreachJob é quem escreve mensagens.
    class RecallFinder
      DEFAULT_DORMANT_MONTHS = 6
      RECALL_COOLDOWN_DAYS = 90

      Result = Struct.new(:contact, :last_event, :last_event_date, :dormant_days, keyword_init: true)

      def initialize(account:, dormant_months: DEFAULT_DORMANT_MONTHS, limit: 50)
        @account = account
        @dormant_months = dormant_months
        @limit = limit
      end

      def call
        cutoff = @dormant_months.months.ago

        # Pacientes ativos da conta com pelo menos 1 consulta concluída
        # antes do cutoff. JOIN com AgendaEvent pra pegar última.
        last_completed_per_contact = ::AgendaEvent
                                       .where(account_id: @account.id, status: 'completed', event_type: 'consultation')
                                       .where.not(contact_id: nil)
                                       .where('starts_at <= ?', cutoff)
                                       .group(:contact_id)
                                       .maximum(:starts_at)

        return [] if last_completed_per_contact.empty?

        contact_ids = last_completed_per_contact.keys

        # Remove os que têm agendamento futuro ativo
        with_future = ::AgendaEvent
                        .where(account_id: @account.id, contact_id: contact_ids)
                        .where(status: %w[pending_confirmation scheduled confirmed arrived in_progress])
                        .where('starts_at >= ?', Time.current)
                        .distinct
                        .pluck(:contact_id)
                        .to_set

        elegible_ids = contact_ids - with_future.to_a
        return [] if elegible_ids.empty?

        # Remove opt-outs e cooldowns recentes (PatientMemory.preferences)
        memories_by_contact = AiAgent::PatientMemory.where(account_id: @account.id, contact_id: elegible_ids).index_by(&:contact_id)
        skip_ids = elegible_ids.select do |cid|
          mem = memories_by_contact[cid]
          next false if mem.nil?

          opt_out = mem.preferences.is_a?(Hash) && mem.preferences['recall_opt_out'] == true
          last_recall_at = mem.preferences.is_a?(Hash) ? mem.preferences['last_recall_at'].to_s : nil
          recent = false
          if last_recall_at.present?
            ts = Time.zone.parse(last_recall_at) rescue nil
            recent = ts && ts > RECALL_COOLDOWN_DAYS.days.ago
          end
          opt_out || recent
        end

        target_ids = (elegible_ids - skip_ids).first(@limit)
        return [] if target_ids.empty?

        contacts = ::Contact.where(account_id: @account.id, id: target_ids).index_by(&:id)

        # Última consulta concluída por contato. Itera ordenado desc e
        # pega a primeira (i.e., a mais recente) por contact_id.
        events_by_contact = {}
        ::AgendaEvent
          .where(account_id: @account.id, contact_id: target_ids, status: 'completed', event_type: 'consultation')
          .order(starts_at: :desc).each do |e|
          events_by_contact[e.contact_id] ||= e
        end

        target_ids.filter_map do |cid|
          contact = contacts[cid]
          last = events_by_contact[cid]
          next nil if contact.nil? || last.nil?

          Result.new(
            contact: contact,
            last_event: last,
            last_event_date: last.starts_at,
            dormant_days: ((Time.current - last.starts_at) / 1.day).to_i
          )
        end
      end
    end
  end
end
