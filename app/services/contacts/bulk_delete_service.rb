class Contacts::BulkDeleteService
  def initialize(account:, contact_ids: [])
    @account = account
    @contact_ids = Array(contact_ids).compact
  end

  # Retorna o nº de contatos efetivamente excluídos. A contagem é usada pelo
  # controller pra responder de forma síncrona ao front (toast honesto com o
  # total real), em vez de enfileirar um job assíncrono cuja conclusão o front
  # não conseguia observar — o que fazia a contagem exibida não bater com a
  # seleção. Ver [[Contacts::BulkActionService]] e bulk_actions_controller.
  def perform
    return 0 if @contact_ids.blank?

    deleted = 0
    contacts.find_each do |contact|
      contact.destroy!
      deleted += 1
    end
    deleted
  end

  private

  def contacts
    @account.contacts.where(id: @contact_ids)
  end
end
