# frozen_string_literal: true

module Signatures
  # Plugin de assinatura eletrônica de documentos.
  #
  # Provê uma abstração `Signatures::Provider` que pode ser implementada por
  # qualquer serviço externo (Clicksign, D4Sign, Autentique, ZapSign...) ou
  # interno (PortalProvider — paciente assina dentro do app Klivy).
  #
  # Pra MVP, dois providers concretos:
  #   - `MockProvider` (dev/test) — simula envelope + status
  #   - `ClicksignProvider` (produção) — HTTP client pra Clicksign API v3
  #
  # Decisão arquitetural: sem `isolate_namespace` (padrão Klivy). Models
  # no namespace global (`SignatureRequest`); services/jobs em `module
  # Signatures`. Engine injeta associações via `to_prepare`.
  class Engine < ::Rails::Engine
    engine_name 'signatures'

    config.to_prepare do
      # Document e ConsentRecord ganham coleção de signature_requests.
      # `dependent: :destroy_async` porque request guarda dados sensíveis
      # (IP, email do signatário, envelope_id externo) que devem sumir
      # quando o documento original some.
      if defined?(Document)
        Document.class_eval do
          has_many :signature_requests,
                   class_name: 'SignatureRequest',
                   as: :signable,
                   dependent: :destroy_async
        end
      end

      if defined?(ConsentRecord)
        ConsentRecord.class_eval do
          has_many :signature_requests,
                   class_name: 'SignatureRequest',
                   as: :signable,
                   dependent: :destroy_async
        end
      end

      if defined?(Account)
        Account.class_eval do
          has_many :signature_requests, dependent: :destroy_async
        end
      end
    end
  end
end
