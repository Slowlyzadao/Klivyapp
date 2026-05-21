# app/services/patients/clinical_note_signer.rb
#
# Responsabilidade: Assinar uma evolução clínica (draft → signed).
# Após assinatura, a nota torna-se juridicamente imutável.
#
# Uso:
#   result = Patients::ClinicalNoteSignerService.call(note: @note, actor: current_user)
#   result.success? # => true

module Patients
  class ClinicalNoteSignerService
    Result = Struct.new(:success, :note, :error, keyword_init: true) do
      def success? = success
    end

    def self.call(note:, actor:)
      new(note: note, actor: actor).call
    end

    def initialize(note:, actor:)
      @note  = note
      @actor = actor
    end

    def call
      return error_result('Evolução já está assinada.') if @note.status_signed?
      return error_result('Janela de edição encerrada. Contate um administrador.') unless @note.within_draft_window?
      return error_result('Você não tem permissão para assinar esta evolução.') unless authorized?

      ActiveRecord::Base.transaction do
        @note.sign!(actor: @actor)

        Result.new(success: true, note: @note)
      end
    rescue StandardError => e
      Result.new(success: false, note: @note, error: e.message)
    end

    private

    def authorized?
      # Profissional que criou OU admin/supervisor
      @note.professional_id == @actor.id ||
        @actor.administrator? ||
        @actor.custom_role&.name.to_s.in?(%w[supervisor])
    end

    def error_result(msg)
      Result.new(success: false, note: @note, error: msg)
    end
  end
end
