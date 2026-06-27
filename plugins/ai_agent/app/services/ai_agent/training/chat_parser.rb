# Estágio 1 — Parsing determinístico (sem IA, custo zero). Transforma o
# `_chat.txt` numa lista de mensagens estruturadas: agrupa linhas de
# continuação na mensagem anterior, remove ruído de sistema e caracteres
# invisíveis, classifica papel (CLINICA x PACIENTE) e tipo (texto/áudio/
# anexo ignorado) e mascara a PII de cada texto via PiiRedactor (LGPD).
class AiAgent::Training::ChatParser
  Message = Struct.new(:idx, :date, :time, :sender, :role, :text, :type, :attachment, keyword_init: true) do
    def to_h
      { idx: idx, date: date, time: time, sender: sender, role: role,
        text: text, type: type, attachment: attachment }
    end
  end

  ROLE_CLINIC = 'CLINICA'.freeze
  ROLE_PATIENT = 'PACIENTE'.freeze
  TYPE_TEXT = 'texto'.freeze
  TYPE_AUDIO = 'audio'.freeze
  TYPE_IGNORED = 'anexo_ignorado'.freeze

  # Cabeçalho de mensagem do export do WhatsApp. O formato da data/hora varia
  # por locale e plataforma: dia/mês podem ter 1-2 dígitos, ano 2 ou 4 dígitos
  # (ex.: iOS pt-BR "31/05/2026"; iOS en/US "5/31/26") e os segundos são
  # opcionais. Ex.: [5/31/26, 19:23:40] Nome do Remetente: texto
  LINE_RE = %r{\A\[(\d{1,2}/\d{1,2}/\d{2,4}),\s(\d{1,2}:\d{2}(?::\d{2})?)\]\s([^:]+):\s?(.*)\z}
  # ‎<anexado: 00000019-AUDIO-2026-06-03-09-41-21.opus>
  ATTACHMENT_RE = /<anexado:\s*([^>]+?)>/i
  AUDIO_NAME_RE = /-AUDIO-.*\.opus\z/i
  # Caracteres invisíveis/de direção (bidi) que o WhatsApp injeta — inclusive
  # os que envolvem números de telefone (‪…‬). Removidos pra não
  # sujarem o nome do remetente nem o corpo da mensagem.
  INVISIBLE_RE = /[‎‏‪-‮⁦-⁩]/
  EDITED_MARKER = /<Mensagem editada>/i

  # Linhas de sistema que não são conhecimento da clínica.
  SYSTEM_NOISE = [
    /mensagens e (as )?chamadas são criptografadas/i,
    /são protegidas com (a )?criptografia/i,
    /criptografia de ponta a ponta/i,
    /somente as pessoas que fazem parte (desta|da) conversa/i,
    /está na sua lista de contatos/i,
    /agora está usando um novo número/i,
    /Mensagem apagada/i,
    /This message was deleted/i,
    # ruído de GRUPO do WhatsApp
    /criou (o|este) grupo/i,
    /adicionou você/i,
    /foi adicionad[oa]/i,
    /saiu do grupo/i,
    /foi removid[oa]/i,
    /removeu você/i,
    /mudou (o nome|a imagem|a descrição|o ícone|as configurações) (deste|do) grupo/i,
    /mudou este grupo/i,
    /agora (é|são) (um |uma )?admin/i,
    /entrou usando (o|seu) link de convite/i,
    /seu código de segurança/i
  ].freeze

  def self.call(chat_path:, clinic_sender_name:, audio_filenames: [])
    new(chat_path, clinic_sender_name, audio_filenames).call
  end

  def initialize(chat_path, clinic_sender_name, audio_filenames)
    @chat_path = chat_path
    @clinic_sender_name = clinic_sender_name.to_s.strip
    @audio_filenames = audio_filenames
  end

  def call
    messages = []
    each_logical_message do |sender, date, time, raw_body|
      body = raw_body.gsub(EDITED_MARKER, '').strip
      next if body.empty?
      next if SYSTEM_NOISE.any? { |re| re.match?(body) }

      messages << build_message(messages.size, sender, date, time, body)
    end
    messages
  end

  private

  # Agrupa continuações (linhas sem o prefixo `[data]`) na mensagem anterior.
  def each_logical_message
    current = nil
    File.foreach(@chat_path, encoding: 'bom|utf-8') do |raw|
      line = raw.chomp.gsub(INVISIBLE_RE, '')

      if (m = LINE_RE.match(line))
        yield(*current) if current
        current = [m[3].strip, m[1], m[2], m[4]]
      elsif current
        current[3] = "#{current[3]}\n#{line}"
      end
    end
    yield(*current) if current
  end

  def build_message(idx, sender, date, time, body)
    type, attachment, text = classify(body)
    Message.new(
      idx: idx, date: date, time: time, sender: sender,
      role: role_for(sender), type: type, attachment: attachment,
      text: AiAgent::Training::PiiRedactor.call(text)
    )
  end

  def classify(body)
    if (m = ATTACHMENT_RE.match(body))
      filename = m[1].strip
      audio = filename.match?(AUDIO_NAME_RE) && @audio_filenames.include?(filename)
      return [audio ? TYPE_AUDIO : TYPE_IGNORED, filename, '']
    end

    [TYPE_TEXT, nil, body]
  end

  def role_for(sender)
    sender == @clinic_sender_name ? ROLE_CLINIC : ROLE_PATIENT
  end
end
