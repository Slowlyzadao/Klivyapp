module Api
  module V1
    module Accounts
      module Patients
        class RecallsController < Api::V1::Accounts::Patients::BaseController
          # POST /api/v1/accounts/:account_id/patients/:patient_id/recall
          def create
            authorize @patient, :update?
            result = ::Patients::RecallSender.call(
              patient: @patient,
              actor: current_user,
              account: Current.account,
              message_override: params[:message]
            )

            if result.success?
              render json: {
                message: 'Recall preparado com sucesso',
                payload: result.payload,
                patient_id: @patient.id,
                needs_recall_updated: true
              }, status: :created
            else
              render json: { error: result.error }, status: :unprocessable_entity
            end
          end
        end
      end
    end
  end
end
