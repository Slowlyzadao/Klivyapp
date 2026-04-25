module Asaas
  class ApiClient
    def initialize
      @api_key = ENV.fetch('ASAAS_API_KEY', 'sandbox_key')
      @base_url = ENV.fetch('ASAAS_API_URL', 'https://api-sandbox.asaas.com/v3')
    end

    def post(path, payload)
      response = connection.post(path) do |req|
        req.body = payload.to_json
      end
      parse_response(response)
    end

    def get(path, params = {})
      response = connection.get(path, params)
      parse_response(response)
    end

    def put(path, payload)
      response = connection.put(path) do |req|
        req.body = payload.to_json
      end
      parse_response(response)
    end

    private

    def connection
      @connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.headers['access_token'] = @api_key
        faraday.headers['Content-Type'] = 'application/json'
        
        # Injects automated retry to avoid async job necessity on signup
        faraday.request :retry, max: 3, interval: 0.05, 
                                interval_randomness: 0.5, backoff_factor: 2, 
                                exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]

        faraday.adapter Faraday.default_adapter
      end
    end

    def parse_response(response)
      body = JSON.parse(response.body) rescue {}
      
      unless response.success?
        error_message = body.dig('errors', 0, 'description') || 'Asaas API Error'
        raise CustomExceptions::Billing::AsaasError, error_message
      end

      body
    end
  end
end
