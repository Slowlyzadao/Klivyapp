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
require 'open3'

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

      # 2026-05-23 — Pipeline reescrito pra usar `gpt-4o-transcribe-diarize`
      # no composite. Vantagem: diarização por voiceprint NATIVA (modelo
      # identifica speakers pelas características da voz, não pela origem
      # do arquivo) → resolve crosstalk acústico que matava transcrições
      # do paciente sem fone. Whisper-1 tinha WER 5.3% + alucinava em
      # silêncio; gpt-4o-transcribe-diarize tem WER 2.46% no mesmo preço.
      #
      # Pipeline:
      #   1) `:diarize` (default): só precisa de composite. Modelo
      #      retorna speakers ("speaker_0", "speaker_1"). Mapeio via
      #      heurística temporal — primeiro speaker que aparece = Doutor.
      #   2) `:fallback_diarized`: composite indisponível mas temos
      #      doctor+patient temps → roda whisper-1 nos 2 separados (legado).
      #   3) `:fallback_single`: só doctor OU patient temp → whisper-1
      #      genérico ("Participante").
      #   4) Inviável: nada → fail.
      mode =
        if composite_key.present?
          :diarize
        elsif doctor_key.present? && patient_key.present?
          :fallback_diarized
        elsif doctor_key.present? || patient_key.present?
          :fallback_single
        else
          nil
        end

      if mode.nil?
        recording.fail!('Nenhum áudio disponível pra transcrição (doctor/patient/composite todos vazios)')
        return
      end

      recording.update!(status: 'transcribing')
      recording.broadcast_status_change!

      merged, provider_used =
        case mode
        when :diarize
          diarize_composite_with_match(composite_key, doctor_key, patient_key)
        when :fallback_diarized
          [
            merge_segments(
              transcribe_track(doctor_key,  speaker: 'Doutor') +
              transcribe_track(patient_key, speaker: 'Paciente')
            ),
            'gpt-4o-transcribe'
          ]
        else # :fallback_single
          key = doctor_key.presence || patient_key.presence || composite_key
          [merge_segments(transcribe_track(key, speaker: 'Participante')), 'gpt-4o-transcribe']
        end

      # 2026-05-25 — Removida camada de pós-revisão Gemini cross-modal.
      # A revisão Gemini 2.5 Flash não trouxe ganho perceptível de qualidade
      # vs. o output direto do `gpt-4o-transcribe-diarize`, apenas latência
      # adicional (~5-15s) e custo (~$0.05/consulta). Decisão do produto:
      # ficar só com a transcrição da OpenAI. Histórico em git blame antes
      # deste commit caso queira reativar.

      text = render_text(merged)

      recording.update!(
        status:              'transcribed',
        transcript_text:     text,
        transcript_segments: merged.map(&:to_h),
        transcript_provider: provider_used
      )
      recording.broadcast_status_change!

      # 2026-05-22 — Cleanup dos temps desabilitado temporariamente pra
      # debug da diarização. Quando TrackEgress voltar a popular
      # doctor/patient_audio_key, conseguir baixar os .ogg do MinIO e
      # ouvir o áudio isolado de cada speaker é o que vai confirmar se
      # o TrackEgress está mesmo separando os streams. Reabilitar
      # depois que diarização estiver validada — comentário só pra
      # marcar o ponto de re-ativação.
      # if mode == :diarized
      #   cleanup_temp_files!(recording, doctor_key, patient_key)
      # end

      GenerateEvolutionJob.perform_later(recording.id)
    rescue StandardError
      # Apenas incrementa contador (UI/admin pode ver tentativa em curso).
      # `retry_on` (acima) faz o re-enqueue automaticamente quando a
      # exceção propaga.
      recording&.bump_retry!
      raise
    end

    private

    # Roda `gpt-4o-transcribe-diarize` no composite e mapeia os speakers
    # retornados (`A`/`B` ou `speaker_0`/`speaker_1`) pra Doutor/Paciente
    # usando GROUND TRUTH dos arquivos isolados.
    #
    # Por que ground truth (e não heurística "primeiro a falar" ou
    # "fala mais"): os tracks isolados (`doctor.ogg`, `patient.ogg`)
    # vêm de TrackEgress filtrado pelo `audio_track_sid` de um
    # participant LiveKit cuja identity é `doctor-*` ou `patient-*`.
    # Esses prefixes são definidos pelo backend ao emitir o token
    # de acesso — quem entra como doctor é o usuário logado no
    # dashboard (que vai apertar "Gravar"). NÃO há ambiguidade. Logo:
    #   - `doctor.ogg` SÓ tem voz do doutor
    #   - `patient.ogg` SÓ tem voz do paciente
    #
    # Algoritmo de mapping:
    #   1. Transcreve doctor.ogg e patient.ogg sem timestamps (gpt-4o-
    #      transcribe simples — só o texto).
    #   2. Pra cada speaker do composite (A, B), concatena texto.
    #   3. Calcula overlap (Jaccard sobre palavras) com cada referência.
    #   4. Speaker com maior overlap em doctor_text → Doutor; outro
    #      → Paciente.
    #
    # Falta de doctor.ogg ou patient.ogg → fallback pra heurística de
    # tempo de fala (maior tempo = Doutor). Caso edge.
    def diarize_composite_with_match(composite_key, doctor_key, patient_key)
      segments = transcribe_track(composite_key, speaker: nil, provider: 'gpt-4o-transcribe-diarize')

      doctor_ref  = doctor_key.present?  ? transcribe_text_only(doctor_key)  : nil
      patient_ref = patient_key.present? ? transcribe_text_only(patient_key) : nil

      mapping = build_speaker_mapping_from_refs(segments, doctor_ref, patient_ref)
      labeled = segments.map do |s|
        role = mapping[s.speaker] || 'Participante'
        AnnotatedSegment.new(start: s.start, end_: s.end_, speaker: role, text: s.text)
      end

      [merge_segments(labeled), 'gpt-4o-transcribe-diarize']
    end

    # Transcrição só de texto (sem timestamps) — pra usar como
    # referência de voiceprint textual ao mapear speakers. Mais barato
    # que verbose_json e gpt-4o-transcribe não suporta verbose_json
    # mesmo (só json simples).
    def transcribe_text_only(storage_key)
      return nil if storage_key.blank?

      tmp = Tempfile.new(['telemed-ref-', '.ogg'], binmode: true)
      processed = nil
      begin
        RecordingStorage.download(storage_key, tmp.path)
        processed = preprocess_for_whisper(tmp.path, storage_key)

        api_key = lookup_whisper_api_key
        client  = OpenAI::Client.new(access_token: api_key, request_timeout: 600)
        response = client.audio.transcribe(parameters: {
          file: File.open(processed.path, 'rb'),
          model: 'gpt-4o-transcribe',
          language: 'pt',
          response_format: 'json'
        })
        response.is_a?(Hash) ? response['text'].to_s : ''
      rescue StandardError => e
        Rails.logger.warn("[TranscribeRecordingJob] transcribe_text_only falhou key=#{storage_key}: #{e.class}: #{e.message}")
        nil
      ensure
        tmp.close
        tmp.unlink
        if processed
          processed.close
          processed.unlink
        end
      end
    end

    def lookup_whisper_api_key
      ENV['OPENAI_WHISPER_KEY'].presence ||
        InstallationConfig.find_by(name: 'OPENAI_WHISPER_KEY')&.value ||
        InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    end

    # Mapping speaker→role usando refs textuais (ground truth) quando
    # disponíveis; fallback pra tempo de fala se faltar referência.
    def build_speaker_mapping_from_refs(segments, doctor_ref, patient_ref)
      speakers = segments.map(&:speaker).compact.uniq
      return {} if speakers.empty?

      # Sem nenhuma ref → fallback fala-mais
      if doctor_ref.blank? && patient_ref.blank?
        return build_speaker_mapping_by_duration(segments)
      end

      # Junta texto por speaker
      texts_by_speaker = Hash.new { |h, k| h[k] = +'' }
      segments.each do |s|
        next unless s.speaker
        texts_by_speaker[s.speaker] << ' ' << s.text
      end

      # Pra cada speaker, calcula overlap com cada ref
      scored = speakers.map do |spk|
        spk_text = texts_by_speaker[spk]
        d_score  = doctor_ref.present?  ? text_overlap(spk_text, doctor_ref)  : 0.0
        p_score  = patient_ref.present? ? text_overlap(spk_text, patient_ref) : 0.0
        { speaker: spk, doctor: d_score, patient: p_score }
      end

      # Assign greedy: o speaker com maior score em doctor que TAMBÉM
      # ganha sobre patient vira Doutor. Outro vira Paciente.
      doctor_winner =
        scored.max_by { |x| x[:doctor] - x[:patient] }

      mapping = {}
      mapping[doctor_winner[:speaker]] = 'Doutor'
      scored.each do |x|
        next if mapping.key?(x[:speaker])
        mapping[x[:speaker]] = mapping.values.include?('Paciente') ? "Participante #{mapping.size + 1}" : 'Paciente'
      end
      mapping
    end

    def build_speaker_mapping_by_duration(segments)
      totals = Hash.new(0.0)
      segments.each do |s|
        next unless s.speaker
        totals[s.speaker] += (s.end_.to_f - s.start.to_f)
      end
      sorted = totals.sort_by { |_, dur| -dur }.map(&:first)
      mapping = {}
      labels  = ['Doutor', 'Paciente']
      sorted.each do |spk|
        label = labels.shift || "Participante #{mapping.size + 1}"
        mapping[spk] = label
      end
      mapping
    end

    # Jaccard sobre palavras normalizadas (lowercase, sem pontuação).
    # Retorna 0.0..1.0. Empate em zero → 0 (raro: textos completamente
    # disjuntos). Robustez: ignora palavras curtas (<= 2 chars) pra não
    # inflacionar score com "e", "o", "a".
    def text_overlap(text_a, text_b)
      words_a = tokenize(text_a)
      words_b = tokenize(text_b)
      return 0.0 if words_a.empty? || words_b.empty?

      inter = (words_a & words_b).size
      union = (words_a | words_b).size
      union.zero? ? 0.0 : inter.to_f / union
    end

    def tokenize(text)
      text.to_s.downcase.gsub(/[^\w\sáéíóúâêôãõàçü]/u, ' ').split(/\s+/).select { |w| w.length > 2 }.uniq
    end

    # Quando `speaker:` é uma string, sobrescreve todos os segments com
    # esse label (modo legado whisper). Quando `speaker:` é nil, preserva
    # o `seg.speaker` retornado pelo provider (modo diarize: speaker_X).
    def transcribe_track(storage_key, speaker:, provider: 'whisper')
      return [] if storage_key.blank?

      tmp = Tempfile.new(['telemed-', '.ogg'], binmode: true)
      processed = nil
      compressed = nil
      begin
        RecordingStorage.download(storage_key, tmp.path)

        # 2026-05-22 — Denoise pre-Whisper. Sem isso, o Whisper alucinava
        # frases comuns do dataset de treino ("Não tenho dinheiro",
        # "Obrigado por assistir", "Alô galera de casa") em trechos de
        # silêncio ou crosstalk fraco. Filtros aplicados:
        #   - highpass=80Hz: remove rumble/zumbido de fundo
        #   - afftdn=nr=20: denoise FFT, atenua -20dB em frequências de
        #     ruído estacionário (mantém voz, mata ar-condicionado etc.)
        #   - dynaudnorm: normalização adaptativa, dá ganho uniforme sem
        #     amplificar silêncio (ao contrário de loudnorm)
        # Mantém timestamps (não corta nada, só re-encoda). Pra crosstalk
        # acústico FORTE (mic interno + speaker do laptop sem fone), o
        # AEC do browser e este denoise reduzem mas não eliminam — fix
        # físico final é o paciente usar fone.
        processed = preprocess_for_whisper(tmp.path, storage_key)
        upload_path = processed.path

        # Audit Fase 3 — comprime quando arquivo passa do limite Whisper
        # (25MB) antes de mandar pra API. 32 kbps mono opus mantém
        # inteligibilidade de fala (Whisper aceita até 16kHz internamente)
        # e reduz tamanho ~50%, cobrindo consultas até ~3h. Acima disso,
        # PermanentFailure → recording.fail! (split por tempo fica como
        # dívida pra Fase 4).
        if File.size(upload_path) > WHISPER_MAX_FILE_BYTES
          compressed = compress_for_whisper(upload_path, storage_key)
          upload_path = compressed.path
        end

        client = TranscriptionProvider.for(provider)
        result = client.call(audio_io: File.open(upload_path, 'rb'))

        result.segments.map do |seg|
          AnnotatedSegment.new(
            start:   seg.start,
            end_:    seg.end_,
            # `speaker` argumento sobrescreve quando é string (modo
            # whisper legado, 1 arquivo = 1 falante). Quando nil
            # (modo diarize), preserva o seg.speaker do provider.
            speaker: speaker || seg.speaker,
            text:    seg.text
          )
        end
      ensure
        tmp.close
        tmp.unlink
        if processed
          processed.close
          processed.unlink
        end
        if compressed
          compressed.close
          compressed.unlink
        end
      end
    end

    # Aplica denoise + highpass + dynaudnorm antes de mandar pro Whisper.
    # Retorna Tempfile com o áudio limpo. Falha → log e devolve um Tempfile
    # com o original copiado (não-fatal — pior caso é Whisper rodar com
    # áudio cru, que é o comportamento de antes deste commit).
    def preprocess_for_whisper(input_path, storage_key)
      out = Tempfile.new(['telemed-clean-', '.ogg'], binmode: true)
      out.close

      cmd = %W[
        ffmpeg -y -hide_banner -loglevel error
        -i #{input_path}
        -af highpass=f=80,afftdn=nr=20:nf=-30,dynaudnorm=g=15:p=0.5
        -c:a libopus -b:a 48k -ac 1
        #{out.path}
      ]
      _stdout_err, status = Open3.capture2e(*cmd)
      unless status.success?
        Rails.logger.warn(
          "[TranscribeRecordingJob] preprocess falhou key=#{storage_key} — usando original"
        )
        FileUtils.cp(input_path, out.path)
      end
      out
    end

    # Roda `ffmpeg` pra recomprimir o áudio em 32 kbps mono opus, retornando
    # um Tempfile novo com o arquivo reduzido. Falha → PermanentFailure
    # (sem retry — recompressão é determinística, não vai melhorar).
    def compress_for_whisper(input_path, storage_key)
      out = Tempfile.new(['telemed-32k-', '.ogg'], binmode: true)
      out.close # ffmpeg escreve direto no path
      Rails.logger.info(
        "[TranscribeRecordingJob] comprimindo key=#{storage_key} " \
        "size=#{File.size(input_path)} bytes (excede limite Whisper)"
      )

      cmd = %W[
        ffmpeg -y -hide_banner -loglevel error
        -i #{input_path}
        -vn -ac 1 -c:a libopus -b:a 32k
        #{out.path}
      ]
      stdout_err, status = Open3.capture2e(*cmd)
      unless status.success?
        out.close!
        raise Telemed::PermanentFailure,
              "ffmpeg falhou ao recomprimir #{storage_key}: #{stdout_err.lines.last(3).join.strip}"
      end

      new_size = File.size(out.path)
      if new_size > WHISPER_MAX_FILE_BYTES
        out.close!
        raise Telemed::PermanentFailure,
              "Áudio excede limite Whisper mesmo após compressão " \
              "(#{new_size} > #{WHISPER_MAX_FILE_BYTES}). Consulta >3h precisa " \
              'de split por tempo (Fase 4).'
      end

      Rails.logger.info(
        "[TranscribeRecordingJob] compressão OK key=#{storage_key} " \
        "new_size=#{new_size} bytes"
      )
      out
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
