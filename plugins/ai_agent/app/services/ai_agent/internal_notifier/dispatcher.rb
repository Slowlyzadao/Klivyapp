# Helper genérico que cada notifier especializado chama. Centraliza:
# resolução do Router (sala/DM), render do template, dedupe por
# notifier_key, MessageDispatcher pra postar como Bea.
#
# Cada notifier (AppointmentPendingConfirmation, OffensiveToneDetected,
# ClinicalEmergencyDetected, etc.) só precisa decidir QUANDO chamar e
# PASSAR as vars do template — tudo o resto é uniforme.
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
class AiAgent::InternalNotifier::Dispatcher
  # ARCH-13 (auditoria 2026-05-18): `.call` é a entrada padronizada de
  # services puros no Klivy (ver AGENTS.md). `.dispatch` preservado como
  # alias pra backwards-compat com callers existentes.
  def self.call(account:, event_key:, vars: {}, dedupe_key: nil)
    new(account, event_key, vars, dedupe_key).call
  end

  class << self
    alias_method :dispatch, :call
  end

  def initialize(account, event_key, vars, dedupe_key)
    @account = account
    @event_key = event_key
    @vars = vars
    @dedupe_key = dedupe_key.presence || "#{event_key}:#{SecureRandom.uuid}"
  end

  def call
    result = AiAgent::InternalNotifier::Router.resolve(account: @account, event_key: @event_key)
    return nil unless result.room

    bea = ::InternalChat::BeaResolver.for_account(@account)
    return nil unless bea

    return nil if already_notified?(result.room)

    body = render_body(result.template)
    recipients = active_human_member_ids(result.room)

    ::InternalChat::MessageDispatcher.call(
      room: result.room,
      sender: bea,
      content: body,
      content_attributes: {
        'mentioned_user_ids' => recipients,
        'mentioned_all' => recipients.size > 1,
        'notifier_key' => @dedupe_key,
        'event_key' => @event_key
      }
    )
  rescue StandardError => e
    Rails.logger.error(
      "[AiAgent::InternalNotifier::Dispatcher] #{@event_key} falhou: #{e.class}: #{e.message}"
    )
    nil
  end

  private

  def render_body(template)
    body = template&.body.presence ||
           AiAgent::InternalNotifier::EventCatalog.default_body_for(@event_key)
    AiAgent::InternalNotifier::TemplateRenderer.render(body, @vars)
  end

  def active_human_member_ids(room)
    room.memberships.where.not(user_id: nil).where(left_at: nil).pluck(:user_id)
  end

  def already_notified?(room)
    ::InternalChat::Message
      .where(room_id: room.id)
      .exists?(["content_attributes ->> 'notifier_key' = ?", @dedupe_key])
  end
end
