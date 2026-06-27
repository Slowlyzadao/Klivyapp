# Endpoint da config de LANÇAMENTO por voucher (recurso singular por conta):
#   GET   ai_agent/voucher_config  → { voucher_config: { enabled, triggers:[] } }
#   PATCH ai_agent/voucher_config  → grava enabled + textos-gatilho do QR
#
# enabled=true coloca a conta em "modo voucher": a Bea SÓ responde quem chegou
# por voucher (foto) ou por um dos textos-gatilho (ver AiAgent::Voucher::Gate).
class AiAgent::Api::V1::Accounts::VoucherConfigsController < Api::V1::Accounts::BaseController
  before_action :authorize_request

  MAX_TRIGGERS = 50
  MAX_TRIGGER_LEN = 280

  def show
    render json: serialize(setting)
  end

  def update
    setting.update!(voucher_config: build_config)
    render json: serialize(setting)
  end

  private

  def authorize_request
    authorize(Current.account, policy_class: ::AiAgent::VoucherConfigPolicy)
  end

  # find_or_create_by! — mesma convenção do resto do plugin (model valida
  # unicidade de account_id, então create_or_find_by! estouraria).
  def setting
    @setting ||= ::AiAgent::AccountSetting.find_or_create_by!(account_id: Current.account.id)
  end

  def serialize(setting)
    { voucher_config: setting.voucher_config.presence || { 'enabled' => false, 'triggers' => [] } }
  end

  def build_config
    p = update_params
    {
      'enabled' => ActiveModel::Type::Boolean.new.cast(p[:enabled]) || false,
      'triggers' => Array(p[:triggers]).map { |t| t.to_s.strip[0, MAX_TRIGGER_LEN] }.reject(&:blank?).uniq.first(MAX_TRIGGERS)
    }
  end

  def update_params
    params.require(:voucher_config).permit(:enabled, triggers: [])
  end
end
