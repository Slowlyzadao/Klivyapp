# frozen_string_literal: true

# app/services/patients/document_whatsapp_sender.rb
#
# Monta um link `wa.me` para que o profissional envie o PDF do documento ao
# paciente via WhatsApp Web/app dele. NÃO envia nada — apenas prepara a URL e
# devolve pro frontend abrir.
#
# Comportamento honesto: o documento NÃO é marcado como `enviado` aqui. Como
# `wa.me` só abre a janela do WhatsApp e o envio depende do clique humano em
# "Enviar", marcar antes seria mentir. O status fica em `gerado` até alguma
# atualização explícita (botão "marcar como enviado" futuro, ou webhook do
# bridge Baileys quando integrado).
#
# Uso:
#   result = Patients::DocumentWhatsappSender.call(
#     document: @document,
#     patient: @patient,
#     actor: current_user
#   )
#
# Retorna `whatsapp_payload[:wa_url]` que o frontend abre em nova aba.

module Patients
  class DocumentWhatsappSender
    Result = Struct.new(:success?, :error, :whatsapp_payload, keyword_init: true)

    SHARE_LINK_EXPIRY = 7.days

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

      file_url = @document.signed_url(expires_in: SHARE_LINK_EXPIRY, disposition: :attachment)
      raise StandardError, 'Não foi possível gerar URL do arquivo' if file_url.blank?

      caption = build_caption(file_url)
      wa_url = "https://wa.me/#{phone}?text=#{ERB::Util.url_encode(caption)}"

      Result.new(
        success?: true,
        whatsapp_payload: {
          wa_url: wa_url,
          phone: phone,
          file_url: file_url,
          file_name: @document.file_name || "#{@document.document_type}.pdf",
          patient_name: @patient.name,
          document_type: @document.document_type,
          expires_in_seconds: SHARE_LINK_EXPIRY.to_i
        },
        error: nil
      )
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

    def build_caption(file_url)
      "#{@document.title}\n\nDocumento gerado pela #{account_display_name}.\n\n#{file_url}"
    end

    def account_display_name
      @patient.account&.name.presence || 'Klivy'
    rescue StandardError
      'Klivy'
    end
  end
end
