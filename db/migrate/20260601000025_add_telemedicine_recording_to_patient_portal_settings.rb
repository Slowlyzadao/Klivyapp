# Sprint L — Teleconsulta: configurações de gravação por clínica.
#
# Coluna JSONB separada (não nested em `scheduling.telemedicine`) porque:
#   - reset/destroy de gravação não deve afetar credenciais LiveKit
#   - opt-out de IA deve ser uma decisão clara da clínica
#
# Estrutura default (preenchida pelo PatientPortalSetting#telemedicine_recording_defaults):
# {
#   "enabled": true,
#   "auto_start": true,                # grava sem pedir confirmação dentro da sala
#   "patient_consent_required": true,  # bloqueia start! se consent ausente
#   "retention_days": 7300,            # CFM 2.314/2022 — 20 anos
#   "delete_unconsented": true,        # deleta se consent for revogado depois
#   "ai_evolution_enabled": true,      # opt-in pro LLM rodar
#   "ai_provider": "claude-sonnet-4.6" # default — trocável via UI futura
# }
class AddTelemedicineRecordingToPatientPortalSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :patient_portal_settings, :telemedicine_recording, :jsonb,
               null: false, default: {}
  end
end
