# frozen_string_literal: true

# app/services/patients/document_whatsapp_sender.rb
#
# Serviço para envio de documentos PDF pelo gateway WhatsApp existente.
# Reutiliza a infraestrutura de WhatsappQrService já construída no projeto.
#
# Uso:
#   result = Patients::DocumentWhatsappSender.call(
#     document: @document,
#     patient: @patient,
#     actor: current_user
#   )

module Patients
  class DocumentWhatsappSender
    Result = Struct.new(:success?, :error, :whatsapp_payload, keyword_init: true)

    def self.call(**args)
      new(**args).call
    end

    def initialize(document:, patient:, actor: nil)
      @document = document
      @patient  = patient
      @actor    = actor
    end

    def call
      raise StandardError, 'Documento sem arquivo anexado' unless @document.file.attached?

      phone = resolve_phone
      raise StandardError, 'Paciente sem telefone cadastrado' if phone.blank?

      file_url = @document.signed_url(expires_in: 2.hours, disposition: :attachment)
      raise StandardError, 'Não foi possível gerar URL do arquivo' if file_url.blank?

      payload = build_whatsapp_payload(phone, file_url)

      @document.mark_as_sent!

      Patients::PatientTimelineEventJob.perform_later(
        patient_id: @patient.id,
        event_type: 'document_sent',
        label: "Documento enviado via WhatsApp: #{@document.title}",
        actor_id: @actor&.id,
        actor: @actor&.name || 'Sistema',
        reference_id: @document.id,
        reference_type: 'Document',
        metadata: { phone: phone, document_type: @document.document_type }
      )

      Result.new(success?: true, whatsapp_payload: payload, error: nil)
    rescue StandardError => e
      Rails.logger.error("[DocumentWhatsappSender] Erro: #{e.message}")
      Result.new(success?: false, error: e.message, whatsapp_payload: nil)
    end

    private

    def resolve_phone
      phone = @patient.phone.presence
      phone ||= @patient.contacts&.find { |c| c['type'] == 'phone' }&.dig('value')
      phone&.gsub(/\D/, '')
    end

    def build_whatsapp_payload(phone, file_url)
      {
        phone: phone,
        file_url: file_url,
        file_name: @document.file_name || "#{@document.document_type}.pdf",
        mime_type: 'application/pdf',
        caption: "📄 #{@document.title}\n\nDocumento gerado pela #{begin
          @patient.account.name
        rescue StandardError
          'BeClinic'
        end}",
        patient_name: @patient.name,
        document_type: @document.document_type,
        note: 'Use o gateway WhatsApp para enviar este documento'
      }
    end
  end
end
