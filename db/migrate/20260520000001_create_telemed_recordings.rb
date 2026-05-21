# Sprint L — Teleconsulta: tabela de gravação por agenda_event.
#
# Cada teleconsulta gravada vira UMA linha. Pipeline assíncrono:
#   pending → recording → uploaded → transcribing → transcribed → evolving → ready
#                                                                          ↘ failed
#
# Storage (R2): cada participante grava em arquivo separado (`Track Egress` —
# decisão §5.1 do PRD), permitindo diarização "de graça" pela origem do áudio.
# Composite gerado pós-fato é opcional na Fase 2 (CompositeRecordingJob).
#
# Tabela separada de `agenda_events` porque:
#   - múltiplas gravações por evento podem existir (reprocessamento, reconexões)
#   - retenção independente (PRD §11 sugere 20 anos por CFM)
#   - estado de pipeline (status) é volátil e poluiria custom_attributes
class CreateTelemedRecordings < ActiveRecord::Migration[7.1]
  def change
    create_table :telemed_recordings do |t|
      t.references :agenda_event, null: false, foreign_key: true, index: true
      t.references :account,      null: false, foreign_key: true, index: true

      # LiveKit egress info. Cada participante (doctor + patient) tem seu
      # próprio job de ParticipantEgress — 2 jobs por sessão. Diarização sai
      # "de graça" porque arquivos chegam separados (PRD §5.1). Webhooks
      # do LiveKit chegam por job → lookup é OR nos dois ids.
      t.string :doctor_egress_id
      t.string :patient_egress_id

      t.string :status, null: false, default: 'pending'
      # values: pending | recording | uploaded | transcribing |
      #         transcribed | evolving | ready | failed

      # Storage keys no bucket R2 (`klivy-telemed-recordings`). Convenção:
      # recordings/YYYY/MM/DD/{room_code}/{role}-{nonce}.{ext}
      t.string :doctor_audio_key
      t.string :patient_audio_key
      t.string :doctor_video_key
      t.string :patient_video_key
      t.string :composite_video_key   # Fase 2: ffmpeg pós-processa em split-screen

      # Métricas operacionais
      t.integer :duration_seconds
      t.bigint  :total_size_bytes

      # Transcrição — texto plano com tags `[Doutor]/[Paciente]` + timestamps
      # iso8601, e segments estruturados pra ancorar o player na transcrição.
      t.text  :transcript_text
      t.jsonb :transcript_segments    # [{start, end, speaker, text}, ...]
      t.string :transcript_provider   # 'whisper' | 'assemblyai' | 'deepgram' | 'gemini'

      # Falhas — texto pra logs humanos + retry_count pra cap manual.
      t.text    :failure_reason
      t.integer :retry_count, default: 0, null: false

      t.timestamps
    end

    # Unique-where-not-null permite que um egress_id falhe (NULL) sem violar
    # a constraint. Lookup do webhook é OR nos dois.
    add_index :telemed_recordings, :doctor_egress_id, unique: true, where: 'doctor_egress_id IS NOT NULL'
    add_index :telemed_recordings, :patient_egress_id, unique: true, where: 'patient_egress_id IS NOT NULL'
    add_index :telemed_recordings, :status
    add_index :telemed_recordings, [:account_id, :created_at]
  end
end
