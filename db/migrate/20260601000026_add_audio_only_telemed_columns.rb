# Sprint L — Refactor pra modo audio-only com diarização perfeita.
#
# Estratégia (refinada 2026-05-20):
#   - 3 gravações paralelas: doctor-temp + patient-temp + composite (todas audio)
#   - Whisper × 2 nos temps pra diarização → merge → DELETA temps
#   - Mantém apenas o `composite_audio_key` no longo prazo (~28 MB/h)
#   - `archived_at` permite "remover" da listagem sem destruir audit trail.
#
# Aditiva — não dropa as colunas *_video_key/*_audio_key que vieram da
# migration 001. Elas ficam ali (sempre null em audio-only mode).
# Em migration futura cleanup pode remover.
class AddAudioOnlyTelemedColumns < ActiveRecord::Migration[7.1]
  def change
    # ID da gravação composite (3º Egress job — RoomCompositeEgress audio_only).
    add_column :telemed_recordings, :composite_egress_id, :string
    add_index  :telemed_recordings, :composite_egress_id,
               unique: true, where: 'composite_egress_id IS NOT NULL'

    # Key R2 do arquivo composite — único arquivo que permanece após o
    # pipeline transcrever os temps e deletá-los.
    add_column :telemed_recordings, :composite_audio_key, :string

    # Arquivamento (quota / purge de assinatura cancelada). Quando setado,
    # o storage key foi removido do R2 mas o registro permanece pra audit.
    # `archive!` no model seta isto + zera os keys.
    add_column :telemed_recordings, :archived_at, :datetime
    add_index  :telemed_recordings, :archived_at

    # Tipo do recording: 'audio' (MVP), 'video' (futuro). Default 'audio'
    # pra todos os registros existentes — Sprint L MVP é audio-only.
    add_column :telemed_recordings, :recording_kind, :string,
               null: false, default: 'audio'
  end
end
