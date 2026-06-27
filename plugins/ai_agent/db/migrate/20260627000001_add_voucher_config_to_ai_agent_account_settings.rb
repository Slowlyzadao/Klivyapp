# MVP lançamento por voucher: config por conta do "modo voucher" + os
# textos-gatilho do QR. Shape: { "enabled" => bool, "triggers" => [String] }.
class AddVoucherConfigToAiAgentAccountSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_account_settings, :voucher_config, :jsonb, default: {}, null: false
  end
end
