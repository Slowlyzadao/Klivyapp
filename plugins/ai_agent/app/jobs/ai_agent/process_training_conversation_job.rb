require 'tmpdir'

# Orquestra a destilação de um .zip de WhatsApp em FAQs para a Bea. Cada
# estágio é um service isolado (AiAgent::Training::*); o job só coordena,
# atualiza o status (que alimenta a barra de progresso na aba "Treinamento")
# e garante a limpeza dos temporários — a mídia bruta nunca é retida.
#
# Pipeline completo: ingestão + parser (0-1), transcrição (2), geração das
# FAQs sugeridas (3-5) e limpeza do .zip bruto (6). A publicação das FAQs
# aprovadas no RAG da Bea é feita à parte (FaqPublisher, via endpoint publish).
class AiAgent::ProcessTrainingConversationJob < ApplicationJob
  queue_as :low

  # Erro determinístico de input (ex.: nome da clínica não bate com nenhum
  # remetente) — marca failed com mensagem clara e NÃO retenta.
  class InvalidInput < StandardError; end

  def perform(training_conversation_id)
    training = AiAgent::TrainingConversation.find(training_conversation_id)
    return if training.completed?

    # 1ª passada: sem clínica escolhida ainda → detecta os participantes e
    # espera o usuário selecionar (não transcreve nem gera FAQ ainda).
    return detect_and_await(training) if training.clinic_sender_name.blank?

    training.update!(status: :extracting, error_message: nil)

    messages = run_pipeline(training)
    faqs = generate_faqs(training, messages)
    persist_result(training, messages, faqs)
    cleanup_raw_media(training)
  rescue InvalidInput => e
    # Determinístico: marca failed com a mensagem amigável e não retenta.
    mark_failed(training_conversation_id, e.message)
  rescue StandardError => e
    Rails.logger.error("[AiAgent::ProcessTrainingConversationJob] #{e.class}: #{e.message}")
    mark_failed(training_conversation_id, "#{e.class}: #{e.message}")
    raise
  end

  private

  def mark_failed(training_conversation_id, message)
    AiAgent::TrainingConversation.find_by(id: training_conversation_id)
                                 &.update(status: :failed, error_message: message)
  end

  # 1ª passada — detecta os participantes da conversa (sem IA) e marca
  # awaiting_clinic, pra o usuário escolher quem é a clínica.
  def detect_and_await(training)
    training.update!(status: :extracting, error_message: nil)
    participants = training.zip_file.blob.open(tmpdir: Rails.root.join('tmp').to_s) do |zip|
      AiAgent::Training::ParticipantDetector.call(zip_path: zip.path)
    end
    raise InvalidInput, 'Não consegui identificar participantes na conversa.' if participants.empty?

    training.update!(status: :awaiting_clinic, participants: participants)
  end

  # Estágio 6 — após gerar e persistir o resultado, descarta o .zip bruto (a
  # mídia extraída já saiu com o tmpdir). Só os finais leves sobrevivem (LGPD).
  def cleanup_raw_media(training)
    training.zip_file.purge_later if training.zip_file.attached?
  end

  # Baixa o .zip do storage e roda os estágios num diretório temporário
  # isolado, sempre removido ao final (mesmo em erro). A transcrição roda
  # AQUI dentro, enquanto os `.opus` ainda existem — só os metadados e o
  # texto final sobrevivem.
  def run_pipeline(training)
    # Base explícita em Rails.root/tmp (absoluta e sempre presente): em alguns
    # ambientes o TMPDIR/Dir.tmpdir vem relativo e o mktmpdir default quebra.
    Dir.mktmpdir('ai_agent_training_', Rails.root.join('tmp').to_s) do |dir|
      extract_dir = File.join(dir, 'unzipped')
      Dir.mkdir(extract_dir)

      training.zip_file.blob.open(tmpdir: dir) do |zip|
        extracted = AiAgent::Training::ZipExtractor.call(zip_path: zip.path, dest_dir: extract_dir)
        messages = AiAgent::Training::ChatParser.call(
          chat_path: extracted.chat_path,
          clinic_sender_name: training.clinic_sender_name,
          audio_filenames: extracted.audio_files.map { |audio| audio[:name] }
        )
        ensure_clinic_matched!(training, messages)
        transcribe_audios(training, messages, extracted.audio_files)
        messages
      end
    end
  end

  # Falha cedo (antes de gastar transcrição) quando o nome da clínica não bate
  # com nenhum remetente — guia o usuário a reenviar com o nome certo.
  def ensure_clinic_matched!(training, messages)
    return if messages.empty?
    return if messages.any? { |msg| msg.role == AiAgent::Training::ChatParser::ROLE_CLINIC }

    senders = messages.map(&:sender).uniq.compact_blank.first(8)
    raise InvalidInput, "O nome \"#{training.clinic_sender_name}\" não corresponde a nenhum " \
                        "participante da conversa. Remetentes encontrados: #{senders.join(', ')}. " \
                        'Reenvie usando exatamente um desses nomes.'
  end

  # Estágio 2 — transcreve os áudios in-place, reportando progresso pra UI.
  def transcribe_audios(training, messages, audio_files)
    total = messages.count { |msg| msg.type == AiAgent::Training::ChatParser::TYPE_AUDIO }
    return if total.zero?

    training.update!(status: :transcribing, audio_total: total, audio_transcribed: 0)
    AiAgent::Training::AudioTranscriber.call(
      messages: messages,
      audio_files: audio_files,
      on_progress: ->(done) { training.update_column(:audio_transcribed, done) } # rubocop:disable Rails/SkipsModelValidations
    )
  end

  # Estágios 3-5.5 — gera as FAQs sugeridas: extração por trecho, consolidação
  # (dedup, fica a versão mais recente) e o JUIZ semântico (FaqValidator), que
  # barra conteúdo pontual/clínico/pessoal que não pode virar RAG.
  # Se ALGUM trecho ficou indisponível (rate-limit/crédito mesmo após os
  # retries), falha o job de propósito: o Sidekiq reprocessa quando o limite
  # liberar, em vez de salvar um resultado PARCIAL em silêncio.
  def generate_faqs(training, messages)
    training.update!(status: :extracting_faq)
    blocks = AiAgent::Training::Chunker.call(messages: messages)
    results = blocks.map { |block| AiAgent::Training::FaqExtractor.call(block_text: block.text) }
    ensure_extraction_available!(results, blocks.size)

    raw_faqs = results.flatten
    return [] if raw_faqs.empty?

    consolidated = AiAgent::Training::FaqConsolidator.call(faqs: raw_faqs)
    validated = AiAgent::Training::FaqValidator.call(faqs: consolidated)
    if validated == AiAgent::Training::LlmResilience::UNAVAILABLE
      raise 'Validação das FAQs indisponível (rate-limit/crédito da IA). ' \
            'Será reprocessado automaticamente quando o limite liberar.'
    end

    Rails.logger.info(
      "[AiAgent::ProcessTrainingConversationJob] FAQs: #{raw_faqs.size} extraídas → " \
      "#{consolidated.size} após dedup → #{validated.size} aprovadas pelo juiz"
    )
    validated
  end

  def ensure_extraction_available!(results, total_blocks)
    failed = results.count { |result| result == AiAgent::Training::LlmResilience::UNAVAILABLE }
    return unless failed.positive?

    raise "Extração indisponível em #{failed}/#{total_blocks} trecho(s) (rate-limit/crédito da IA). " \
          'Será reprocessado automaticamente quando o limite liberar.'
  end

  def persist_result(training, messages, faqs)
    clinic = messages.count { |msg| msg.role == AiAgent::Training::ChatParser::ROLE_CLINIC }
    audios = messages.count { |msg| msg.type == AiAgent::Training::ChatParser::TYPE_AUDIO }

    training.update!(
      status: :completed,
      parsed_messages: messages.map(&:to_h),
      faqs: faqs,
      faq_count: faqs.size,
      message_count: messages.size,
      clinic_message_count: clinic,
      patient_message_count: messages.size - clinic,
      audio_total: audios,
      processed_at: Time.current
    )
  end
end
