# Gateway Asaas — implementação real para cobranças iniciadas no portal do
# paciente (Sprint G).
#
# Responsabilidades:
#   1. Garantir customer no Asaas (POST /v3/customers, cacheado em
#      `Patient.external_ids['asaas_customer_id']`).
#   2. Criar cobrança (POST /v3/payments) com `externalReference` = portal_payment.id
#      → o webhook usa esse campo pra encontrar o PortalPayment de volta.
#   3. Para PIX, buscar QR Code (GET /v3/payments/:id/pixQrCode).
#
# Credenciais: Financial::GatewaySetting (api_key + environment).
#
# Erros: lançam `AsaasError` (subclasse de StandardError) — o controller já
# captura e cria PortalPayment com status=failed.
#
# NÃO confiar nesta classe em produção sem antes:
#   1. Configurar Financial::GatewaySetting com credencial válida.
#   2. Configurar webhook no painel Asaas → POST /webhooks/financial/asaas?account_id=:id
#   3. Testar em sandbox (api-sandbox.asaas.com) com cartão de teste.
require 'net/http'

module PatientPortal
  module Payment
    class AsaasGateway < Gateway
      AsaasError = Class.new(StandardError)

      METHOD_MAP = {
        'pix'         => 'PIX',
        'boleto'      => 'BOLETO',
        'credit_card' => 'CREDIT_CARD'
      }.freeze

      BASE_PRODUCTION = 'https://api.asaas.com/v3'.freeze
      BASE_SANDBOX    = 'https://api-sandbox.asaas.com/v3'.freeze

      def initialize(setting:)
        raise AsaasError, 'Asaas gateway setting ausente' if setting.blank?
        raise AsaasError, 'Asaas api_key ausente'         if setting.api_key.blank?

        @setting = setting
      end

      def create_charge!(method:, amount_cents:, patient:, installment:)
        billing_type = METHOD_MAP[method] or raise AsaasError, "método não suportado: #{method}"
        customer_id  = ensure_customer!(patient)
        due_date     = next_business_day_iso

        charge = post_json('/payments', {
          customer:          customer_id,
          billingType:       billing_type,
          value:             (amount_cents / 100.0).round(2),
          dueDate:           due_date,
          externalReference: installment.id.to_s,
          description:       "Parcela #{installment.number}/#{installment.total_in_series} — Klivy"
        })

        pix_data = (billing_type == 'PIX') ? fetch_pix_qr(charge['id']) : {}

        Result.new(
          gateway_payment_id: charge['id'],
          pix_qr_code:        pix_data['encodedImage'],
          pix_copy_paste:     pix_data['payload'],
          boleto_url:         charge['bankSlipUrl'],
          boleto_barcode:     charge['nossoNumero'] || charge['identificationField'],
          expires_at:         parse_expiration(charge, billing_type),
          raw: { charge: charge, pix: pix_data }
        )
      end

      private

      def ensure_customer!(patient)
        existing = patient.external_ids.is_a?(Hash) && patient.external_ids['asaas_customer_id']
        return existing if existing.present?

        cpf  = patient.try(:cpf) || patient.try(:document_number)
        body = {
          name:        patient.name,
          email:       patient.email,
          mobilePhone: patient.try(:phone_number) || patient.try(:phone),
          cpfCnpj:     cpf
        }.compact

        created = post_json('/customers', body)
        save_customer_id!(patient, created['id'])
        created['id']
      end

      def save_customer_id!(patient, id)
        return if id.blank?
        return unless patient.respond_to?(:external_ids=)

        ids = patient.external_ids.is_a?(Hash) ? patient.external_ids.dup : {}
        ids['asaas_customer_id'] = id
        patient.update_columns(external_ids: ids, updated_at: Time.current)
      end

      def fetch_pix_qr(payment_id)
        get_json("/payments/#{payment_id}/pixQrCode")
      rescue AsaasError => e
        Rails.logger.warn("[AsaasGateway] pixQrCode falhou para #{payment_id}: #{e.message}")
        {}
      end

      def parse_expiration(charge, billing_type)
        raw = charge['dueDate']
        date = Date.parse(raw.to_s) rescue Date.current + 1.day
        billing_type == 'PIX' ? Time.current + 30.minutes : date.end_of_day
      end

      def base_url
        @setting.try(:environment) == 'production' ? BASE_PRODUCTION : BASE_SANDBOX
      end

      def next_business_day_iso
        date = Date.current + 1.day
        date += 1 while date.saturday? || date.sunday?
        date.iso8601
      end

      def post_json(path, payload)
        request_json(:post, path, payload)
      end

      def get_json(path)
        request_json(:get, path, nil)
      end

      def request_json(verb, path, payload)
        uri = URI.join("#{base_url}/", path.sub(%r{^/}, ''))
        req = case verb
              when :post then Net::HTTP::Post.new(uri)
              when :get  then Net::HTTP::Get.new(uri)
              end
        req['access_token'] = @setting.api_key
        req['Content-Type'] = 'application/json'
        req.body = payload.to_json if payload

        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
          http.request(req)
        end

        unless res.is_a?(Net::HTTPSuccess)
          raise AsaasError, "Asaas #{verb.upcase} #{path} → #{res.code}: #{res.body.to_s.first(300)}"
        end

        JSON.parse(res.body.to_s.presence || '{}')
      rescue JSON::ParserError => e
        raise AsaasError, "Resposta inválida do Asaas: #{e.message}"
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise AsaasError, "Timeout no Asaas (#{verb} #{path}): #{e.message}"
      end
    end
  end
end
