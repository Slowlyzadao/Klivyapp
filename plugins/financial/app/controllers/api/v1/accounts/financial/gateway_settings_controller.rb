module Api
  module V1
    module Accounts
      module Financial
        # Configuração do gateway por conta. Apenas ADMIN.
        class GatewaySettingsController < BaseController
          skip_before_action :ensure_setup_complete!
          before_action :require_admin!
          before_action :load_setting

          def show
            render json: serialize(@setting)
          end

          def update
            attrs = setting_params
            api_key = attrs.delete(:api_key)
            webhook_secret = attrs.delete(:webhook_secret)

            @setting.assign_attributes(attrs)
            @setting.api_key = api_key if api_key.present?
            @setting.webhook_secret = webhook_secret if webhook_secret.present?

            if @setting.save
              render json: serialize(@setting)
            else
              render json: { errors: @setting.errors.full_messages }, status: :unprocessable_entity
            end
          end

          private

          def require_admin!
            render(json: { error: 'forbidden' }, status: :forbidden) unless user_has_any_role?(%w[ADMIN])
          end

          def load_setting
            @setting = ::Financial::GatewaySetting.find_or_create_by!(account_id: current_account.id) do |s|
              s.gateway = 'manual'
            end
          end

          def setting_params
            params.require(:gateway_setting).permit(
              :gateway, :environment, :api_key, :webhook_secret,
              :default_pix_key, :default_customer_external_ref_strategy, :auto_sync_enabled
            )
          end

          def serialize(s)
            {
              gateway: s.gateway,
              environment: s.environment,
              has_api_key: s.api_key.present?,
              has_webhook_secret: s.webhook_secret.present?,
              webhook_verified: s.webhook_verified,
              webhook_last_received_at: s.webhook_last_received_at,
              auto_sync_enabled: s.auto_sync_enabled
            }
          end
        end
      end
    end
  end
end
