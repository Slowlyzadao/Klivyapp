# Chaves VAPID do servidor para Web Push (Sprint G — Portal do Paciente).
#
# Em produção, configure via ENV:
#   VAPID_PUBLIC_KEY  / VAPID_PRIVATE_KEY  / VAPID_SUBJECT (mailto:admin@klivy.app)
#
# Em dev, se as ENVs não estiverem setadas, geramos um par efêmero — o navegador
# vai aceitar e as notificações funcionam *naquela sessão* do servidor. Cada
# reboot do dev server invalida subscriptions antigas; aceitável só em dev.
#
# Para persistir em dev, rode UMA vez:
#   bin/rails runner 'puts WebPush.generate_key.to_h.to_json' > tmp/vapid.json
# e copie public_key/private_key pra .env (sem aspas).

module VapidKeys
  class << self
    def public_key
      keys[:public_key]
    end

    def private_key
      keys[:private_key]
    end

    def subject
      ENV['VAPID_SUBJECT'].presence || 'mailto:admin@klivy.app'
    end

    def configured?
      ENV['VAPID_PUBLIC_KEY'].present? && ENV['VAPID_PRIVATE_KEY'].present?
    end

    private

    def keys
      @keys ||= load_or_generate
    end

    def load_or_generate
      if configured?
        { public_key: ENV['VAPID_PUBLIC_KEY'], private_key: ENV['VAPID_PRIVATE_KEY'] }
      else
        pair = WebPush.generate_key
        Rails.logger.warn("[VAPID] Usando par efêmero — subscriptions caem no próximo reboot. " \
                          "Configure VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY no .env pra persistir.")
        { public_key: pair.public_key, private_key: pair.private_key }
      end
    end
  end
end
