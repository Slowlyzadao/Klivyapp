# Audit Fase 3 — extraído de `ProposedEvolution#approve!` (audit #10.8).
# Audit 2026-05-26 — Reescrito para criar `SessionLog` (modelo unificado
# usado pela aba Evolução do paciente) em vez de `ClinicalNote` legado.
# Antes a aprovação ia pra `clinical_notes` (existia no banco mas a UI
# da Ficha Clínica/Histórico lê de `session_logs` — invisível pro
# dentista). O mapeamento agora consome direto os 14 `procedure_fields`
# do prompt novo, sem passar por SOAP (que continua salvo na proposta
# como backward-compat).
#
# Aprovar uma proposta clínica gerada por IA é o ponto que CRUZA a fronteira
# "IA → prontuário oficial". Responsabilidades:
#   1) Mapear procedure_fields → SessionLog (incluindo areas_treated e
#      products_used em jsonb arrays).
#   2) Persistir SessionLog(status='draft', proposed_evolution_id=N).
#   3) Atualizar a ProposedEvolution com status='approved' + link reverso.
#
# Tudo numa transaction única (atomicidade clínica — ou o registro
# existe no prontuário ou nada muda).
module Telemed
  class ProposedEvolutionApprovalService
    # `clinical_note` mantido no Result por compat com chamadores existentes —
    # agora aponta pro session_log (que é o sucessor).
    Result = Struct.new(:evolution, :clinical_note, :session_log, keyword_init: true)

    def self.call(evolution:, actor:)
      new(evolution: evolution, actor: actor).call
    end

    def initialize(evolution:, actor:)
      @evolution = evolution
      @actor     = actor
    end

    def call
      raise 'Proposta já aprovada' if @evolution.status == 'approved'
      raise 'Proposta rejeitada não pode ser aprovada' if @evolution.status == 'rejected'

      ActiveRecord::Base.transaction do
        session_log = build_session_log
        session_log.save!

        @evolution.update!(
          status:        'approved',
          reviewed_by:   @actor,
          reviewed_at:   Time.current
        )

        # Link bidirecional — `session_logs.proposed_evolution_id` aponta
        # de volta. Setamos depois do save pra evitar circularidade na
        # construção. Update column pra não disparar callbacks de novo.
        session_log.update_column(:proposed_evolution_id, @evolution.id)

        Result.new(
          evolution:     @evolution.reload,
          clinical_note: session_log, # compat: chamadores antigos esperam .id e .status
          session_log:   session_log
        )
      end
    end

    private

    # Mapeia procedure_fields (14 chaves preenchidas pela IA + edições do
    # dentista) → colunas/jsonb do SessionLog. `areas_treated` e
    # `products_used` são jsonb arrays no schema — montamos um item só
    # com o que a IA capturou; o dentista pode editar via aba Evolução.
    def build_session_log
      event   = @evolution.telemed_recording.agenda_event
      patient = Patient.find_by(contact_id: event.contact_id, account_id: event.account_id)
      raise 'Paciente do agendamento não encontrado' unless patient

      pf = @evolution.procedure_fields.is_a?(Hash) ? @evolution.procedure_fields : {}

      areas_treated = build_areas_treated(pf)
      products_used = build_products_used(pf)

      SessionLog.new(
        account_id:                event.account_id,
        patient_id:                patient.id,
        professional_id:           event.user_id || @actor.id,
        appointment_id:            event.id,
        performed_at:              event.starts_at || Time.current,
        duration_minutes:          compute_duration_minutes(event),
        procedure_name:            value_or_default(pf['procedimento_realizado'], 'Teleconsulta'),
        complaint_of_day:          pf['queixa_do_dia'].to_s.strip.presence,
        assessment:                pf['avaliacao_clinica'].to_s.strip.presence,
        complications:             pf['intercorrencias'].to_s.strip.presence,
        result_observed:           pf['resultado_imediato'].to_s.strip.presence,
        next_consultation_details: pf['detalhes_proxima_consulta'].to_s.strip.presence,
        observation:               pf['observacao'].to_s.strip.presence,
        return_in_days:            normalize_return_days(pf['retorno_em_dias']),
        return_needed:             !normalize_return_days(pf['retorno_em_dias']).nil?,
        areas_treated:             areas_treated,
        products_used:             products_used,
        status:                    'draft'
      )
    end

    def build_areas_treated(pf)
      area = pf['area_tratada'].to_s.strip
      return [] if area.empty?
      [{ region: area, description: pf['procedimento_realizado'].to_s.strip.presence }.compact]
    end

    def build_products_used(pf)
      product = pf['produto_utilizado'].to_s.strip
      return [] if product.empty?
      [{
        name:       product,
        quantity:   pf['quantidade_dose'].to_s.strip.presence || '1',
        unit:       pf['unidade'].to_s.strip.presence || 'un',
        batch:      pf['lote'].to_s.strip.presence,
        expires_at: pf['validade'].to_s.strip.presence
      }.compact]
    end

    def normalize_return_days(value)
      return nil if value.nil? || value == ''
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end

    # AgendaEvent não tem coluna `duration_minutes`; calcula a partir
    # de `starts_at`/`ends_at`. Default 30 se faltar algum dos dois.
    def compute_duration_minutes(event)
      return 30 unless event.starts_at && event.ends_at
      ((event.ends_at - event.starts_at) / 60).round
    end

    def value_or_default(value, default)
      value.to_s.strip.presence || default
    end
  end
end
