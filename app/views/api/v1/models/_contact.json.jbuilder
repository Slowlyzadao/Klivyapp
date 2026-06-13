if resource.nil?
  # BECLINIC (edição core autorizada pelo dono — 2026-06-09): conversa/registro
  # ÓRFÃO. O Chatwoot apaga as conversas de um contato de forma ASSÍNCRONA
  # (`Contact has_many :conversations, dependent: :destroy_async`). Entre o
  # delete do contato e o job rodar (ou se o Sidekiq estiver fora do ar), a
  # conversa fica apontando pra um contato inexistente e este partial recebia
  # `nil` → `undefined method 'additional_attributes' for nil` → 500 que
  # derrubava a LISTA inteira de conversas. Em vez de quebrar, devolvemos um
  # contato-placeholder; a conversa some sozinha quando o cascade roda.
  json.id nil
  json.name 'Contato removido'
  json.additional_attributes({})
  json.custom_attributes({})
else
  json.additional_attributes resource.additional_attributes
  json.availability_status resource.availability_status
  json.email resource.email
  json.id resource.id
  json.name resource.name
  json.phone_number resource.phone_number
  json.blocked resource.blocked
  json.identifier resource.identifier
  json.thumbnail resource.avatar_url
  json.custom_attributes resource.custom_attributes
  json.last_activity_at resource.last_activity_at.to_i if resource[:last_activity_at].present?
  json.created_at resource.created_at.to_i if resource[:created_at].present?
  # we only want to output contact inbox when its /contacts endpoints
  if defined?(with_contact_inboxes) && with_contact_inboxes.present?
    json.contact_inboxes do
      json.array! resource.contact_inboxes do |contact_inbox|
        json.partial! 'api/v1/models/contact_inbox', formats: [:json], resource: contact_inbox
      end
    end
  end
end
