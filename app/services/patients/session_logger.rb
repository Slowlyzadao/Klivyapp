module Patients
  # Registra uma sessão de tratamento e atualiza o progresso do item.
  # Criado pelo SessionLogsController — lógica extraída para ser testável isoladamente.
  #
  # Uso:
  #   result = Patients::SessionLogger.new(params, current_user, current_account).call
  #   result.success?    => true/false
  #   result.session_log => o registro criado
  #   result.error       => mensagem de erro
  class SessionLogger
    Result = Struct.new(:success?, :session_log, :error, keyword_init: true)

    def initialize(params, current_user, current_account)
      @params          = params
      @current_user    = current_user
      @current_account = current_account
    end

    def call
      session_log = nil

      ActiveRecord::Base.transaction do
        session_log = SessionLog.create!(
          account: @current_account,
          patient_id: @params[:patient_id],
          professional: @current_user,
          treatment_plan_id: @params[:treatment_plan_id],
          treatment_item_id: @params[:treatment_item_id],
          appointment_id: @params[:appointment_id],
          procedure_name: @params[:procedure_name],
          performed_at: @params[:performed_at],
          duration_minutes: @params[:duration_minutes],
          areas_treated: @params[:areas_treated] || [],
          products_used: @params[:products_used] || [],
          complications: @params[:complications],
          result_observed: @params[:result_observed],
          post_procedure_guidance: @params[:post_procedure_guidance],
          return_needed: @params[:return_needed] || false,
          return_in_days: @params[:return_in_days]
        )
      end

      Result.new(success?: true, session_log: session_log)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, session_log: nil, error: e.message)
    end
  end
end
