class ContactPolicy < ApplicationPolicy
  # Listagens — view_all e view_active no catálogo Klivy.
  # Admins nativos do Chatwoot e donos passam direto via beclinic_can?.
  def index?
    beclinic_can?(:contacts, :view_all)
  end

  def active?
    beclinic_can?(:contacts, :view_active) ||
      beclinic_can?(:contacts, :view_all)
  end

  def show?
    index?
  end

  def search?
    index? || active?
  end

  def filter?
    search?
  end

  def contactable_inboxes?
    show?
  end

  def import?
    beclinic_can?(:contacts, :import_export)
  end

  def export?
    beclinic_can?(:contacts, :import_export)
  end

  def create?
    beclinic_can?(:contacts, :create)
  end

  def update?
    beclinic_can?(:contacts, :edit)
  end

  def avatar?
    update?
  end

  def destroy_custom_attributes?
    update?
  end

  def destroy?
    # Mantém compatibilidade com a perm `chat.delete_contact` (botão de
    # excluir contato dentro do painel da conversa) — qualquer uma das duas
    # permite a operação. Admins nativos passam via beclinic_can?.
    beclinic_can?(:contacts, :delete) || beclinic_can?(:chat, :delete_contact)
  end
end
