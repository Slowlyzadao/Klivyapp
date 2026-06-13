class Api::V1::Accounts::InternalChat::AttachmentsController < Api::V1::Accounts::BaseController
  before_action :fetch_room
  before_action -> { authorize(@room, policy_class: InternalChat::AttachmentPolicy) }

  # GET .../rooms/:room_id/attachments?type=media|documents&page=N&per_page=M
  # Lista anexos da sala pra aba "Arquivos" das settings.
  # - media: imagens + vídeos (galeria com miniaturas)
  # - documents: arquivos genéricos (PDFs, planilhas, etc)
  # Stickers ficam de fora (não são attachments). Mensagens deletadas também.
  #
  # PERF-17 (auditoria 2026-05-18): paginação opt-in (default per_page=200
  # mantém comportamento). Salas com >200 anexos antigos antes ficavam
  # inacessíveis pela aba "Arquivos".
  ATTACHMENTS_PER_PAGE_DEFAULT = 200
  ATTACHMENTS_PER_PAGE_MAX = 200

  def index
    file_types = case params[:type].to_s
                 when 'documents' then %w[file]
                 else %w[image video] # default = media
                 end
    page = (params[:page].presence || 1).to_i.clamp(1, 10_000)
    per_page = (params[:per_page].presence || ATTACHMENTS_PER_PAGE_DEFAULT)
               .to_i.clamp(1, ATTACHMENTS_PER_PAGE_MAX)
    offset = (page - 1) * per_page

    base = InternalChat::Attachment
           .joins(:message)
           .where(internal_chat_messages: { room_id: @room.id, deleted_at: nil })
           .where(file_type: file_types)
    total = base.count
    attachments = base.includes(message: :sender)
                      .order('internal_chat_messages.created_at DESC')
                      .offset(offset)
                      .limit(per_page)

    render json: {
      data: attachments.map { |a| attachment_payload(a) },
      meta: { page: page, per_page: per_page, total: total }
    }
  end

  # GET .../attachments/:id/download
  # Pra WebP (que é o formato em que armazenamos imagens): converte de volta
  # pra JPG (sem alpha) ou PNG (com alpha) e serve com Content-Disposition
  # attachment. Pra outros tipos, redireciona pra URL direta do ActiveStorage.
  def download
    @attachment = InternalChat::Attachment
                  .joins(:message)
                  .where(internal_chat_messages: { room_id: @room.id })
                  .find_by(id: params[:id])
    return head :not_found unless @attachment

    if @attachment.content_type == 'image/webp'
      send_converted_image(@attachment)
    else
      redirect_to @attachment.file_url, allow_other_host: false
    end
  end

  private

  # Lê o WebP, detecta alpha, converte pra PNG (alpha) ou JPG (sem alpha),
  # serve in-memory com filename apropriado. Falha → cai pro WebP original.
  def send_converted_image(att)
    blob_data = att.file.download
    img = MiniMagick::Image.read(blob_data)
    target = alpha_channel?(img.path) ? 'png' : 'jpg'

    img.format target
    img.combine_options { |c| c.quality '92' } if target == 'jpg'

    base = File.basename(att.file_name.to_s.presence || "imagem-#{att.id}", '.*')
    send_data img.to_blob,
              filename: "#{base}.#{target}",
              type: target == 'jpg' ? 'image/jpeg' : 'image/png',
              disposition: 'attachment'
  rescue StandardError => e
    Rails.logger.warn "[InternalChat::Attachments#download] convert failed: #{e.class}: #{e.message}"
    redirect_to att.file_url, allow_other_host: false
  end

  # Detecta canal alpha via `magick identify -format %A`.
  # Retorna 'Blend' / 'On' quando há transparência; 'Off' / 'Undefined' quando opaco.
  def alpha_channel?(path)
    out = MiniMagick::Tool::Identify.new do |c|
      c.format '%A'
      c << path
    end
    %w[Blend On True].include?(out.to_s.strip)
  rescue StandardError
    true # safer default — PNG cobre os dois casos sem perda
  end

  def attachment_payload(att)
    msg = att.message
    {
      id: att.id,
      file_type: att.file_type,
      file_name: att.file_name,
      content_type: att.content_type,
      file_size: att.file_size,
      file_url: att.file_url,
      thumb_url: att.file_type == 'image' ? att.thumb_url : nil,
      download_url: download_url_for(att),
      message_id: msg.id,
      message_created_at: msg.created_at,
      sender: serialize_sender(msg.sender),
    }
  end

  # WebP convertido salvo no disco precisa voltar pra um formato que o usuário
  # entende ao baixar (JPG/PNG). Pra outros tipos, redireciona pra URL direta.
  def download_url_for(att)
    return att.file_url unless att.content_type == 'image/webp'

    "/api/v1/accounts/#{Current.account.id}/internal_chat/rooms/#{att.message.room_id}/attachments/#{att.id}/download"
  end

  def serialize_sender(user)
    return nil unless user

    {
      id: user.id,
      name: user.available_name,
      avatar_url: user.respond_to?(:avatar_url) ? user.avatar_url : nil,
    }
  end

  def fetch_room
    @room = Current.account.internal_chat_rooms.find(params[:room_id])
  end
end
