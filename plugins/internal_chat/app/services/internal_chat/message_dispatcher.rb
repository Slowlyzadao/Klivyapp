module InternalChat
  # Persiste mensagem (texto, anexos ou ambos), atualiza last_message_at da
  # sala e enfileira broadcast assíncrono.
  class MessageDispatcher
    def self.call(room:, sender:, content: nil, content_attributes: {}, attachments: [], sticker_id: nil)
      new(room, sender, content, content_attributes, attachments, sticker_id).call
    end

    def initialize(room, sender, content, content_attributes, attachments, sticker_id = nil)
      @room = room
      @sender = sender
      @content = content
      @content_attributes = content_attributes || {}
      @attachments = Array(attachments)
      @sticker_id = sticker_id
    end

    def call
      # BE-20 (auditoria 2026-05-18): sanitiza `in_reply_to` ANTES do save.
      # Frontend pode enviar in_reply_to apontando msg de outra sala via
      # request craftado (mesmo cenário: ID válido mas cross-room). Se o
      # id não pertence a esta sala, descartamos silenciosamente em vez de
      # quebrar a request — preserva UX se a msg original foi deletada
      # numa race entre user clicar reply e mandar.
      # Cross-room reply legítimo ("responder no particular") usa
      # `quoted_message` snapshot — não passa por in_reply_to. Esse fluxo
      # continua intacto.
      sanitize_in_reply_to!

      message = nil
      ActiveRecord::Base.transaction do
        # Cria mensagem com content_type baseado no primeiro anexo (se só anexo)
        # ou 'text' (se houver texto). Mensagens com texto + anexo ficam 'text'
        # — UI renderiza ambos. Sticker tem seu próprio content_type.
        ct = derive_content_type
        message = @room.messages.new(
          sender_user_id: ai_sender? ? nil : @sender.id,
          sender_ai_agent_id: ai_sender? ? @sender.id : nil,
          content: @content,
          content_type: ct,
          content_attributes: @content_attributes,
          sticker_id: @sticker_id,
        )
        attach_files(message)
        message.save!
        persist_mentions(message)
        @room.touch_last_message!(message.created_at)
      end

      # RT-7 (auditoria 2026-05-18): marca como lida pelo próprio sender.
      # Antes era feito no MessagesController#create em linha separada;
      # mover pro dispatcher cobre todos os callers (controllers, jobs
      # futuros) e elimina o estado "sender vê badge unread sobre própria
      # msg" quando o controller esquece. AI sender (Bea) não tem
      # membership humana — skipa.
      mark_read_by_sender!(message)

      # BE-11 (auditoria 2026-05-18): enqueue do broadcast com rescue —
      # se a queue (Redis/Sidekiq) estiver fora, a mensagem JÁ está
      # persistida (transação commitada acima); broadcast falhar não pode
      # rollback o save. Frontend reconcilia eventualmente via fetch ao
      # reabrir a sala. Sem o rescue, o caller recebia 500 mesmo com
      # message gravada — UX inconsistente.
      begin
        InternalChat::BroadcastMessageJob.perform_later(message.id)
      rescue StandardError => e
        Rails.logger.error(
          "[InternalChat::MessageDispatcher] broadcast enqueue falhou message=#{message.id} " \
          "room=#{@room.id}: #{e.class}: #{e.message}"
        )
      end
      InternalChat::Telemetry.track('message_sent',
                                    account_id: @room.account_id,
                                    room_id: @room.id,
                                    message_id: message.id,
                                    content_type: message.content_type,
                                    has_mentions: message.mentions.any?,
                                    is_reply: message.in_reply_to_id.present?,
                                    attachments: message.attachments.size)
      message.attachments.each do |a|
        InternalChat::Telemetry.track('attachment_uploaded',
                                      account_id: @room.account_id,
                                      room_id: @room.id,
                                      file_type: a.file_type,
                                      size_kb: ((a.file_size || 0) / 1024.0).round(1))
      end
      message
    end

    def persist_mentions(message)
      result = InternalChat::MentionExtractor.call(message)

      result.user_ids.each do |uid|
        next if !ai_sender? && uid == @sender.id

        InternalChat::Mention.create!(
          message_id: message.id,
          user_id: uid,
          account_id: @room.account_id,
        )
      end

      result.ai_agent_ids.each do |aid|
        next if ai_sender? && aid == @sender.id

        InternalChat::Mention.create!(
          message_id: message.id,
          ai_agent_id: aid,
          account_id: @room.account_id,
        )
      end

      # Sprint 7: notifica listener AI (no-op por enquanto). Roda fora da
      # transação principal pra não bloquear o save.
      InternalChat::AiAgentMentionListener.call(
        message: message,
        ai_agent_ids: result.ai_agent_ids,
      )
    end

    private

    # RT-7: atualiza last_read_message_id da membership do sender com
    # update_column (skipa callbacks e validation; last_read não tem
    # nenhuma validation custom). Fora da transação propositadamente —
    # se a mensagem foi salva mas isso falhar, o estado "unread badge
    # próprio" é cosmético e auto-corrigido no próximo open.
    def mark_read_by_sender!(message)
      return if ai_sender?

      membership = @room.memberships.active.where(user_id: @sender.id).first
      # update_column ignora optimistic locking + callbacks. Sem rescue:
      # se o membership sumiu entre save e este update (improvável dado
      # mesmo turn), preferimos saber.
      membership&.update_column(:last_read_message_id, message.id) # rubocop:disable Rails/SkipsModelValidations
    end

    # Remove `in_reply_to` se aponta pra mensagem que não pertence a esta sala
    # (msg de outra conta, msg deletada, id inválido). Mantém o resto do
    # content_attributes intacto. Idempotente — chama 1x antes do save.
    def sanitize_in_reply_to!
      return unless @content_attributes.is_a?(Hash)

      in_reply_to = @content_attributes['in_reply_to'] || @content_attributes[:in_reply_to]
      return if in_reply_to.blank?
      return if @room.messages.exists?(id: in_reply_to)

      Rails.logger.warn(
        "[InternalChat::MessageDispatcher] in_reply_to=#{in_reply_to} não existe " \
        "na sala #{@room.id} (account_id=#{@room.account_id}); descartando do payload"
      )
      @content_attributes = @content_attributes.except('in_reply_to', :in_reply_to)
    end

    # Pipeline B futuro também usa AI sender; hoje só Pipeline A (notificador).
    # Captain::Assistant é o tipo da Bea (ver BeaResolver). Mantemos a checagem
    # estrutural pra não acoplar este service ao plugin ai_agent diretamente.
    def ai_sender?
      defined?(::Captain::Assistant) && @sender.is_a?(::Captain::Assistant)
    end

    def derive_content_type
      return 'sticker' if @sticker_id.present? && @content.blank? && @attachments.empty?
      return 'text' if @content.present?
      return 'text' if @attachments.empty?

      first = @attachments.first
      ct = first.respond_to?(:content_type) ? first.content_type : nil
      InternalChat::Attachment.classify(ct)
    end

    def attach_files(message)
      return if @attachments.empty?

      @attachments.first(15).each do |upload|
        next unless upload.respond_to?(:read)

        att = message.attachments.build(
          file_type: InternalChat::Attachment.classify(upload.content_type),
          file_name: upload.original_filename,
          content_type: upload.content_type,
          file_size: upload.size,
        )
        att.file.attach(io: upload, filename: upload.original_filename, content_type: upload.content_type)
      end
    end
  end
end
