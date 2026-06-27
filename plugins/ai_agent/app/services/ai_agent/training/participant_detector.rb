# Detecção rápida (sem IA) dos PARTICIPANTES da conversa, pra o usuário
# escolher quem é a clínica antes do processamento pesado. Extrai apenas o
# `_chat.txt` do .zip (ignora os áudios) e conta as mensagens por remetente,
# reusando o parser para já descartar ruído de sistema.
class AiAgent::Training::ParticipantDetector
  class MissingChatError < StandardError; end

  def self.call(zip_path:)
    new(zip_path).call
  end

  def initialize(zip_path)
    @zip_path = zip_path
  end

  def call
    Dir.mktmpdir('ai_agent_detect_', Rails.root.join('tmp').to_s) do |dir|
      chat_path = extract_chat(dir)
      messages = AiAgent::Training::ChatParser.call(
        chat_path: chat_path,
        clinic_sender_name: '',
        audio_filenames: []
      )
      messages.map(&:sender)
              .tally
              .sort_by { |_name, count| -count }
              .map { |name, count| { 'name' => name, 'count' => count } }
    end
  end

  private

  # Extrai só o _chat.txt (não os áudios) via stream — rápido mesmo em .zip
  # grande, e à prova da mudança de API do rubyzip 3.x.
  def extract_chat(dir)
    chat_path = File.join(dir, 'chat.txt')

    Zip::File.open(@zip_path) do |zip|
      entry = zip.entries
                 .reject(&:directory?)
                 .select { |e| File.extname(e.name).casecmp?(AiAgent::Training::ZipExtractor::CHAT_EXT) }
                 .max_by(&:size)
      raise MissingChatError, 'nenhum arquivo .txt (conversa) encontrado no .zip' if entry.nil?

      entry.get_input_stream { |io| IO.copy_stream(io, chat_path) }
    end

    chat_path
  end
end
