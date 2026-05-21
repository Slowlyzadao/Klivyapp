class DeleteObjectJob < ApplicationJob
  queue_as :low

  BATCH_SIZE = 5_000

  def perform(object, user = nil, ip = nil)
    # Pre-purge heavy associations for large objects to avoid
    # timeouts & race conditions due to destroy_async fan-out.
    purge_heavy_associations(object)

    # Se for um Inbox com canal WhatsApp QR, destruir a sessão no bridge
    cleanup_whatsapp_bridge_session(object) if object.is_a?(Inbox)

    object.destroy!
    process_post_deletion_tasks(object, user, ip)
  end

  def process_post_deletion_tasks(object, user, ip); end

  private

  def heavy_associations
    {
      Account => %i[conversations contacts inboxes reporting_events],
      Inbox => %i[conversations contact_inboxes reporting_events]
    }.freeze
  end

  def purge_heavy_associations(object)
    klass = heavy_associations.keys.find { |k| object.is_a?(k) }
    return unless klass

    heavy_associations[klass].each do |assoc|
      next unless object.respond_to?(assoc)

      batch_destroy(object.public_send(assoc))
    end
  end

  def batch_destroy(relation)
    relation.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each(&:destroy!)
    end
  end

  def cleanup_whatsapp_bridge_session(inbox)
    return unless inbox.channel_type == 'Channel::Whatsapp'

    inbox_id = inbox.id
    bridge_url = ENV.fetch('WHATSAPP_QR_BRIDGE_URL') { ENV.fetch('WHATSAPP_BRIDGE_URL', 'http://localhost:3002') }
    uri = URI("#{bridge_url}/sessions/#{inbox_id}")

    Rails.logger.info("[WHATSAPP_CLEANUP] 🗑️ Destruindo sessão #{inbox_id} no bridge...")

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 5

    request = Net::HTTP::Delete.new(uri)
    response = http.request(request)

    Rails.logger.info("[WHATSAPP_CLEANUP] ✅ Bridge respondeu: #{response.code} - #{response.body}")
  rescue StandardError => e
    # Não bloqueia a exclusão do inbox se o bridge estiver fora do ar
    Rails.logger.warn("[WHATSAPP_CLEANUP] ⚠️ Falha ao limpar sessão no bridge (prosseguindo com exclusão): #{e.message}")
  end
end

DeleteObjectJob.prepend_mod_with('DeleteObjectJob')
