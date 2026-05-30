class Webhooks::InstagramController < ActionController::API
  include MetaTokenVerifyConcern

  def events
    Rails.logger.info("[IG_AUDIT] Webhook hit: object=#{params['object'].inspect} entries=#{params['entry'].is_a?(Array) ? params['entry'].size : 'n/a'}")
    if params['object'].casecmp('instagram').zero?
      entry_params = params.to_unsafe_hash[:entry]
      Rails.logger.info("[IG_AUDIT] Recipient IDs in payload: #{extract_recipient_ids(entry_params).inspect}")

      if contains_echo_event?(entry_params)
        # Add delay to prevent race condition where echo arrives before send message API completes
        # This avoids duplicate messages when echo comes early during API processing
        ::Webhooks::InstagramEventsJob.set(wait: 2.seconds).perform_later(entry_params)
      else
        ::Webhooks::InstagramEventsJob.perform_later(entry_params)
      end

      render json: :ok
    else
      Rails.logger.warn("[IG_AUDIT] Webhook ignored, object is not 'instagram': #{params['object'].inspect}")
      head :unprocessable_entity
    end
  end

  private

  def extract_recipient_ids(entry_params)
    return [] unless entry_params.is_a?(Array)

    entry_params.flat_map do |entry|
      messages = entry[:messaging].presence || entry[:standby] || []
      messages.map { |m| m.dig(:recipient, :id) }
    end.compact.uniq
  end

  def contains_echo_event?(entry_params)
    return false unless entry_params.is_a?(Array)

    entry_params.any? do |entry|
      # Check messaging array for echo events
      messaging_events = entry[:messaging] || []
      messaging_events.any? { |messaging| messaging.dig(:message, :is_echo).present? }
    end
  end

  def valid_token?(token)
    # Validates against both IG_VERIFY_TOKEN (Instagram channel via Facebook page) and
    # INSTAGRAM_VERIFY_TOKEN (Instagram channel via direct Instagram login)
    token == GlobalConfigService.load('IG_VERIFY_TOKEN', '') ||
      token == GlobalConfigService.load('INSTAGRAM_VERIFY_TOKEN', '')
  end
end
