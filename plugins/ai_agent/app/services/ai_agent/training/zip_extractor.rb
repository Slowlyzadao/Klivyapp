# Estágio 0 — Ingestão. Extrai o .zip do WhatsApp num diretório isolado por
# job, valida que há `_chat.txt` e apaga tudo que não seja `.opus` ou
# `_chat.txt` (foto, pdf, vCard, etc. não viram conhecimento e, por LGPD,
# não devem nem ser retidos).
class AiAgent::Training::ZipExtractor
  Result = Struct.new(:chat_path, :audio_files, keyword_init: true)

  class MissingChatError < StandardError; end

  CHAT_EXT = '.txt'.freeze
  AUDIO_EXT = '.opus'.freeze

  def self.call(zip_path:, dest_dir:)
    new(zip_path, dest_dir).call
  end

  def initialize(zip_path, dest_dir)
    @zip_path = zip_path
    @dest_dir = dest_dir
  end

  def call
    extract_entries
    chat_path = find_chat_path
    raise MissingChatError, 'nenhum arquivo .txt (conversa) encontrado no .zip' if chat_path.nil?

    purge_unsupported_files(chat_path)
    Result.new(chat_path: chat_path, audio_files: audio_files)
  end

  private

  # Achata a estrutura (o WhatsApp exporta tudo na raiz) usando só o basename
  # de cada entrada — o que também blinda contra zip-slip (path traversal).
  def extract_entries
    Zip::File.open(@zip_path) do |zip|
      zip.each do |entry|
        next if entry.directory?

        dest = File.join(@dest_dir, File.basename(entry.name))
        # rubyzip 3.x mudou a assinatura de `extract` (passou a tratar o arg
        # como caminho relativo + prefixar o CWD). Lemos o stream e gravamos
        # direto no destino absoluto — à prova de versão e streaming.
        entry.get_input_stream { |io| IO.copy_stream(io, dest) }
      end
    end
  end

  # O export do WhatsApp nomeia o chat de várias formas (_chat.txt no iOS,
  # "Conversa do WhatsApp com X.txt" no Android, etc.). Pega o MAIOR .txt — que
  # é sempre o histórico da conversa.
  def find_chat_path
    Dir.children(@dest_dir)
       .select { |name| File.extname(name).casecmp?(CHAT_EXT) }
       .map { |name| File.join(@dest_dir, name) }
       .max_by { |path| File.size(path) }
  end

  def purge_unsupported_files(chat_path)
    Dir.children(@dest_dir).each do |name|
      path = File.join(@dest_dir, name)
      next if path == chat_path
      next if File.extname(name).casecmp?(AUDIO_EXT)

      File.delete(path) if File.file?(path)
    end
  end

  def audio_files
    Dir.children(@dest_dir)
       .select { |name| File.extname(name).casecmp?(AUDIO_EXT) }
       .sort
       .map { |name| { name: name, path: File.join(@dest_dir, name) } }
  end
end
