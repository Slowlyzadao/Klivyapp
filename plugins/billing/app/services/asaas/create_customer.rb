module Asaas
  class CreateCustomer
    def initialize(params, external_reference)
      @params = params
      @external_reference = external_reference
    end

    def perform
      payload = {
        name: @params[:name],
        email: @params[:email],
        company: @params[:clinic_name],
        cpfCnpj: @params[:cpf_cnpj],
        phone: @params[:phone],
        mobilePhone: @params[:phone], # Often required by Asaas for SMS billing
        address: @params[:address],
        addressNumber: @params[:address_number],
        complement: @params[:complement],
        province: @params[:province],
        postalCode: @params[:postal_code],
        externalReference: @external_reference.to_s
      }

      client = Asaas::ApiClient.new

      begin
        response = client.post('customers', payload)
      rescue CustomExceptions::Billing::AsaasError => e
        # Se o Asaas recusou porque o e-mail já está cadastrado,
        # tentamos encontrar o customer existente e reusá-lo.
        raise unless duplicate_email_error?(e.message)

        existing_id = find_existing_customer_id(@params[:email])
        raise unless existing_id

        Rails.logger.info("[Asaas::CreateCustomer] Reutilizando customer existente (#{existing_id}) para #{@params[:email]}")
        return existing_id
      end

      # Alguns retornos de sucesso ainda trazem campo `errors` com avisos.
      if response['errors']&.any?
        if duplicate_email_error?(response['errors'].map { |e| e['description'] || e['message'] }.join(' '))
          existing_id = find_existing_customer_id(@params[:email])
          return existing_id if existing_id
        end
        raise CustomExceptions::Billing::AsaasError, 'Falha ao criar cliente no Asaas'
      end

      response['id']
    end

    private

    def duplicate_email_error?(message)
      message.to_s.match?(/(email|e-mail).*(já.*cadastrad|already)/i)
    end

    def find_existing_customer_id(email)
      return nil if email.blank?
      response = Asaas::ApiClient.new.get('customers', email: email)
      data = response['data']
      return nil unless data.is_a?(Array) && data.any?
      data.first['id']
    rescue StandardError => e
      Rails.logger.warn("[Asaas::CreateCustomer] Falha ao buscar customer por email: #{e.message}")
      nil
    end
  end
end
