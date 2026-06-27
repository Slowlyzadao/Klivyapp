# Fase 4: decide e monta a mensagem de saída de um follow-up conforme o
# canal e a janela de 24h do WhatsApp.
#   - dentro da janela (ou canal sem janela: qr/web) → TEXTO LIVRE
#     (Bea generativa ou mensagem estática renderizada)
#   - fora da janela (WhatsApp oficial, +24h sem resposta) → TEMPLATE
#     aprovado, se a regra tiver um; senão pula (`outside_messaging_window`).
#
# Reusa StaticRenderer (variáveis) e MessageGenerator (LLM). Devolve um
# Result que o SendFollowUpJob só precisa postar — toda a decisão de
# composição mora aqui, fora do job.
class AiAgent::FollowUps::OutboundMessage
  Result = Struct.new(:skip_reason, :content, :template_params, :usage, keyword_init: true)

  def initialize(rule:, contact:, step: nil, agenda_event: nil)
    @rule = rule
    @contact = contact
    @step = step
    @agenda_event = agenda_event
  end

  def call(conversation)
    @conversation = conversation
    return free_text if within_window?
    return template if @rule.cloud_template?

    Result.new(skip_reason: 'outside_messaging_window')
  end

  private

  # `can_reply?` já trata qr (sem janela) e a janela de 24h do cloud/360.
  # Na dúvida (erro), assume que pode — preserva o comportamento legado.
  def within_window?
    @conversation.can_reply?
  rescue StandardError
    true
  end

  def free_text
    return Result.new(content: render(static_body), usage: nil) if @rule.static?

    gen = AiAgent::FollowUps::MessageGenerator.new(
      rule: @rule, step: @step, contact: @contact,
      agenda_event: @agenda_event, conversation: @conversation
    ).call
    return Result.new(skip_reason: 'message_generation_failed') if gen.nil?

    Result.new(content: gen.text, usage: gen)
  end

  def template
    body = body_params
    Result.new(
      content: template_preview(body),
      template_params: {
        'name' => @rule.cloud_template_name,
        'language' => @rule.cloud_template_lang,
        'processed_params' => { 'body' => body }
      },
      usage: nil
    )
  end

  # { '1' => valor, '2' => valor } na ordem de `cloud_template_params`.
  # Nunca emite valor em branco: o TemplateProcessorService do Chatwoot
  # PULA params vazios (filter_map), o que DESLOCARIA as posições ({{1}}
  # receberia o valor de {{2}}). O fallback '-' preserva o alinhamento.
  def body_params
    @rule.cloud_template_params.each_with_index.to_h do |var, i|
      [(i + 1).to_s, render("{{#{var}}}").presence || '-']
    end
  end

  def static_body
    @step&.static_body.presence || @rule.static_body
  end

  def render(body)
    AiAgent::FollowUps::StaticRenderer.call(
      body: body, contact: @contact, agenda_event: @agenda_event, account: @rule.account
    )
  end

  # Texto exibido no inbox: o corpo do template aprovado já com as
  # variáveis substituídas, quando encontrável; senão um rótulo com o nome.
  def template_preview(body)
    text = approved_body_text
    return "[#{@rule.cloud_template_name}]" if text.blank?

    body.reduce(text) { |acc, (k, v)| acc.gsub("{{#{k}}}", v.to_s) }
  end

  def approved_body_text
    tmpl = approved_template
    return nil if tmpl.blank?

    Array(tmpl['components']).find { |c| c['type'].to_s.upcase == 'BODY' }&.dig('text')
  end

  def approved_template
    channel = @conversation.inbox&.channel
    return nil unless channel.respond_to?(:message_templates)

    # Só template APROVADO — espelha o find_template do
    # TemplateProcessorService (envio real), pra o preview não renderizar
    # de um template que a Meta vai recusar.
    Array(channel.message_templates).find do |t|
      t['name'] == @rule.cloud_template_name &&
        t['language'].to_s.downcase == @rule.cloud_template_lang.to_s.downcase &&
        t['status'].to_s.downcase == 'approved'
    end
  end
end
