# Audit Fase 3 — extraído de `ProposedEvolution#approve!` (audit #10.8).
#
# Aprovar uma proposta clínica gerada por IA é o ponto que CRUZA a fronteira
# "IA → prontuário oficial". Tem 3 responsabilidades distintas:
#   1) Mapear SOAP (subjetivo/objetivo/avaliação/plano) → colunas
#      ClinicalNote (complaint_of_day, assessment, conduct).
#   2) Persistir ClinicalNote(source='telemed_ai', status='draft').
#   3) Atualizar a ProposedEvolution com status='approved' + link reverso.
#
# Esse processo todo precisa rodar em transaction única (atomicidade
# clínica — ou o registro existe no prontuário ou nada muda). Antes vivia
# direto no model `ProposedEvolution#approve!`, o que misturava lógica de
# domínio (state machine da proposta) com lógica de outro bounded context
# (criação de ClinicalNote). Service object isola a costura.
#
# Pattern Klivy: `.call(...)` único método público; raises StandardError
# com mensagem clara em erros de negócio (controller pega no rescue e
# devolve 422 com `error: e.message`).
module Telemed
  class ProposedEvolutionApprovalService
    Result = Struct.new(:evolution, :clinical_note, keyword_init: true)

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
        note = build_clinical_note
        note.save!

        @evolution.update!(
          status:        'approved',
          clinical_note: note,
          reviewed_by:   @actor,
          reviewed_at:   Time.current
        )

        # Link bidirecional — `clinical_notes.proposed_evolution_id` aponta de
        # volta. Setamos depois do save pra evitar circularidade na construção.
        note.update_column(:proposed_evolution_id, @evolution.id)

        Result.new(evolution: @evolution.reload, clinical_note: note)
      end
    end

    private

    # Mapeia SOAP da proposta pras colunas existentes em ClinicalNote.
    # PRD §7.4 + ClinicalNote schema:
    #   S — Subjetivo   → complaint_of_day
    #   O — Objetivo    → assessment (parte inicial — concat)
    #   A — Avaliação   → assessment (hipótese diagnóstica)
    #   P — Plano       → conduct
    #
    # `raw_markdown` permanece salvo no ProposedEvolution pra recuperar texto
    # completo sem perdas se o dentista precisar reconciliar depois.
    def build_clinical_note
      event   = @evolution.telemed_recording.agenda_event
      patient = Patient.find_by(contact_id: event.contact_id, account_id: event.account_id)
      raise 'Paciente do agendamento não encontrado' unless patient

      soap = @evolution.soap_structure.is_a?(Hash) ? @evolution.soap_structure : {}
      subjetivo = soap['subjetivo'].to_s.strip
      objetivo  = soap['objetivo'].to_s.strip
      avaliacao = soap['avaliacao'].to_s.strip
      plano     = soap['plano'].to_s.strip

      assessment_parts = []
      assessment_parts << "[Objetivo]\n#{objetivo}"   if objetivo.present?
      assessment_parts << "[Avaliação]\n#{avaliacao}" if avaliacao.present?

      ClinicalNote.new(
        account_id:       event.account_id,
        patient_id:       patient.id,
        professional_id:  event.user_id || @actor.id,
        appointment_id:   event.id,
        note_date:        (event.starts_at&.to_date || Time.current.to_date),
        complaint_of_day: subjetivo.presence,
        assessment:       assessment_parts.join("\n\n").presence,
        conduct:          plano.presence,
        status:           'draft',
        source:           'telemed_ai'
      )
    end
  end
end
