# Sprint L — Transcreve audio com diarização perfeita + cleanup.
#
# Estratégia:
#   1. Baixa doctor-temp.ogg + patient-temp.ogg do R2 (paralelo)
#   2. Whisper × 2 → cada arquivo já vira segments com speaker conhecido
#      (origem do arquivo = speaker garantido)
#   3. Merge cronológico
#   4. Persiste transcript_text + transcript_segments
#   5. DELETA doctor_audio_key + patient_audio_key do R2 (permanente)
#   6. ZERA as colunas no DB (composite_audio_key continua intacto)
#   7. Enfileira GenerateEvolutionJob
#
# Após esta job rodar com sucesso, o registro tem apenas:
#   - composite_audio_key  (arquivo único — usado pelo player)
#   - transcript_text/segments (texto pra revisão e pro LLM)
#
# Falhas — retry exponencial 3×. Esgotado, marca `failed` mas mantém os
# arquivos (admin pode reprocessar).
require 'tempfile'

module Telemed
  class TranscribeRecordingJob < ApplicationJob
    # `:low` (priority Sidekiq) — job longo (Whisper 1-10min, download R2,
    # upload back). NÃO pode bloquear queues `:critical`/`:high` (timers
    # de no-show, mark-in-progress, notificações). Audit Fase 2 — antes
    # estava em `:default` competindo com tudo.
    queue_as :low

    # Mecanismo único de retry: `retry_on` controla as 3 tentativas; o bloco
    # roda quando todas esgotam e marca o recording como failed. Antes
    # tínhamos `retry_on` E lógica manual de `retries_exhausted?` no rescue,
    # o que era redundante e confuso (mesmo que numericamente equivalente).
    # Agora `bump_retry!` serve APENAS pra contador no DB (visibilidade), e
    # `fail!` final acontece num lugar só.
    retry_on StandardError, wait: :exponentially_longer, attempts: 3 do |job, exception|
      recording = TelemedRecording.find_by(id: job.arguments.first)
      next if recording.nil? || recording.failed?

      recording.fail!("Transcrição falhou após retries (#{exception.class}): #{exception.message}")
    end
    discard_on ActiveJob::DeserializationError

    # Limite de arquivo aceito pela Whisper API.
    WHISPER_MAX_FILE_BYTES = 25 * 1024 * 1024

    # Erros permanentes (`Telemed::PermanentFailure`) que NÃO devem entrar
    # no `retry_on` — retentar 3x não muda o resultado, só desperdiça
    # download R2 + Whisper. Ex: arquivo > 25MB. A classe é compartilhada
    # com GenerateEvolutionJob (ambos descartam em fail-fast).
    discard_on Telemed::PermanentFailure do |job, exception|
      recording = TelemedRecording.find_by(id: job.arguments.first)
      next if recording.nil? || recording.failed?

      recording.fail!("Transcrição abortada (permanente): #{exception.message}")
    end

    def perform(recording_id)
      recording = TelemedRecording.find_by(id: recording_id)
      return unless recording
      return if recording.ready? || recording.failed?
      return if recording.archived?

      doctor_key    = recording.doctor_audio_key
      patient_key   = recording.patient_audio_key
      composite_key = recording.composite_audio_key

      # Pipeline modos:
      #   1) Diarizado: doctor + patient temps disponíveis → modo ideal
      #      (2 Whisper calls, speakers garantidos pelo arquivo de origem)
      #   2) Single (fallback): só composite disponível → 1 Whisper call,
      #      sem diarização. Acontece quando ParticipantEgress falha em um
      #      ou ambos os participantes (ex: dentista com WiFi ruim) mas o
      #      composite egress concluiu OK.
      #   3) Inviável: nenhum key disponível → fail.
      mode =
        if doctor_key.present? && patient_key.present?
          :diarized
        elsif composite_key.present?
          :single
        else
          nil
        end

      if mode.nil?
        recording.fail!('Nenhum áudio disponível pra transcrição (doctor/patient/composite todos vazios)')
        return
      end

      recording.update!(status: 'transcribing')
      recording.broadcast_status_change!

      merged =
        if mode == :diarized
          merge_segments(
            transcribe_track(doctor_key,  speaker: 'Doutor') +
            transcribe_track(patient_key, speaker: 'Paciente')
          )
        else
          # Modo single: composite tem ambos os speakers misturados, sem
          # forma confiável de separá-los. Speaker fica 'Participante'.
          merge_segments(transcribe_track(composite_key, speaker: 'Participante'))
        end

      text = render_text(merged)

      recording.update!(
        status:              'transcribed',
        transcript_text:     text,
        transcript_segments: merged.map(&:to_h),
        transcript_provider: 'whisper'
      )
      recording.broadcast_status_change!

      # Cleanup só dos temps (composite continua intacto pro player).
      # No modo `single` não há temps a deletar.
      if mode == :diarized
        cleanup_temp_files!(recording, doctor_key, patient_key)
      end

      GenerateEvolutionJob.perform_later(recording.id)
    rescue StandardError
      # Apenas incrementa contador (UI/admin pode ver tentativa em curso).
      # `retry_on` (acima) faz o re-enqueue automaticamente quando a
      # exceção propaga.
      recording&.bump_retry!
      raise
    end

    private

    def transcribe_track(storage_key, speaker:)
      return [] if storage_key.blank?

      tmp = Tempfile.new(['telemed-', '.ogg'], binmode: true)
      begin
        RecordingStorage.download(storage_key, tmp.path)

        # Guard pré-Whisper. API rejeita >25MB com 400 e o `retry_on` faria
        # 2 retries inúteis pagos. Detectar localmente economiza $$$ e
        # propaga erro semântico — caller pode logar / alertar. Em consulta
        # longa (>1h @ 64kbps), composite pode passar 25MB; precisa de
        # split/compress (Fase 3).
        size = File.size(tmp.path)
        if size > WHISPER_MAX_FILE_BYTES
          raise Telemed::PermanentFailure,
                "Áudio excede limite Whisper (25MB): key=#{storage_key} size=#{size} bytes. " \
                'Implementar split/compress (Fase 3).'
        end

        tmp.rewind
        provider = TranscriptionProvider.for('whisper')
        result   = provider.call(audio_io: File.open(tmp.path, 'rb'))

        result.segments.map do |seg|
          AnnotatedSegment.new(
            start:   seg.start,
            end_:    seg.end_,
            speaker: speaker,
            text:    seg.text
          )
        end
      ensure
        tmp.close
        tmp.unlink
      end
    end

    def cleanup_temp_files!(recording, *keys)
      keys.compact.each do |key|
        begin
          RecordingStorage.delete(key)
        rescue StandardError => e
          # Não-fatal — log e segue. Pior caso é arquivo órfão no R2;
          # job futuro `ReapOrphanRecordingsJob` (Fase 2) pode varrer.
          Rails.logger.warn("[TranscribeRecordingJob] R2 delete falhou key=#{key}: #{e.message}")
        end
      end

      recording.update!(doctor_audio_key: nil, patient_audio_key: nil)
    end

    def merge_segments(segments)
      segments.sort_by(&:start)
    end

    def render_text(segments)
      segments.map do |s|
        "[#{format_timestamp(s.start)}] [#{s.speaker}] #{s.text}"
      end.join("\n")
    end

    def format_timestamp(seconds)
      seconds = seconds.to_f.round
      format('%02d:%02d:%02d', seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    end

    AnnotatedSegment = Struct.new(:start, :end_, :speaker, :text, keyword_init: true) do
      def to_h
        { start: start, end: end_, speaker: speaker, text: text }
      end
    end
  end
end
