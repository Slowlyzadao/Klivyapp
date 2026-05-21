module Patients
  # Registra uma sessão de tratamento/evolução e atualiza o progresso do item.
  # Criado pelo SessionLogsController — lógica extraída para ser testável isoladamente.
  #
  # Uso:
  #   result = Patients::SessionLogger.new(params, current_user, current_account).call
  #   result.success?    => true/false
  #   result.session_log => o registro criado
  #   result.error       => mensagem de erro
  class SessionLogger
    Result = Struct.new(:success?, :session_log, :error, keyword_init: true)

    PERMITTED_PRODUCT_KEYS = %i[product_id name quantity unit batch expires_at].freeze
    PERMITTED_AREA_KEYS    = %i[region tooth_number description side].freeze

    def initialize(params, current_user, current_account)
      @params          = params
      @current_user    = current_user
      @current_account = current_account
    end

    def call
      session_log = nil

      ActiveRecord::Base.transaction do
        session_log = SessionLog.create!(attributes)
      end

      Result.new(success?: true, session_log: session_log)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, session_log: nil, error: e.message)
    end

    private

    def attributes
      {
        account: @current_account,
        patient_id: @params[:patient_id],
        professional: assigned_professional,
        treatment_plan_id: @params[:treatment_plan_id],
        treatment_item_id: @params[:treatment_item_id],
        appointment_id: @params[:appointment_id],
        form_template_id: @params[:form_template_id],
        procedure_name: @params[:procedure_name],
        performed_at: @params[:performed_at],
        duration_minutes: @params[:duration_minutes],
        areas_treated: sanitize_collection(@params[:areas_treated], PERMITTED_AREA_KEYS),
        products_used: sanitize_collection(@params[:products_used], PERMITTED_PRODUCT_KEYS),
        complications: @params[:complications],
        result_observed: @params[:result_observed],
        post_procedure_guidance: @params[:post_procedure_guidance],
        return_needed: @params[:return_needed] || false,
        return_in_days: @params[:return_in_days],
        complaint_of_day: @params[:complaint_of_day],
        assessment: @params[:assessment],
        next_consultation_details: @params[:next_consultation_details],
        observation: @params[:observation],
        status: @params[:status].presence || 'draft'
      }
    end

    # Permite o frontend mandar `professional_id` explícito (caso o usuário escolha
    # outro profissional do dropdown). Sem essa chave, cai no current_user.
    def assigned_professional
      explicit_id = @params[:professional_id].presence
      return User.find_by(id: explicit_id) if explicit_id

      @current_user
    end

    def sanitize_collection(input, allowed_keys)
      return [] if input.blank?

      Array(input).map do |entry|
        next entry if entry.is_a?(Hash) && (entry.keys.map(&:to_sym) - allowed_keys).empty?

        entry.is_a?(Hash) ? entry.slice(*allowed_keys.map(&:to_s), *allowed_keys) : entry
      end
    end
  end
end
