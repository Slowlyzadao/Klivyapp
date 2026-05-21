class ChangeSessionLogTextColumns < ActiveRecord::Migration[7.0]
  # User-Agent moderno passa fácil de 255 chars (Chrome/Mac UA = ~270).
  # Mantemos como string columns que sabidamente cabem em 255 (mode, hash,
  # token, ip).
  def up
    change_column :session_logs, :patient_signature_device_info, :text
  end

  def down
    change_column :session_logs, :patient_signature_device_info, :string
  end
end
