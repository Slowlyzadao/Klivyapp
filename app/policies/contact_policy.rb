class ContactPolicy < ApplicationPolicy
  def index?
    administrator? || beclinic_can?(:contacts, :view_all)
  end

  def active?
    administrator? || beclinic_can?(:contacts, :view_active) || beclinic_can?(:contacts, :view_all)
  end

  def import?
    administrator? || beclinic_can?(:contacts, :import_export)
  end

  def export?
    administrator? || beclinic_can?(:contacts, :import_export)
  end

  def search?
    administrator? || beclinic_can?(:contacts, :view_all)
  end

  def filter?
    administrator? || beclinic_can?(:contacts, :view_all)
  end

  def update?
    administrator? || beclinic_can?(:contacts, :edit)
  end

  def contactable_inboxes?
    administrator? || beclinic_can?(:contacts, :view_all)
  end

  def destroy_custom_attributes?
    administrator? || beclinic_can?(:contacts, :edit)
  end

  def show?
    administrator? || beclinic_can?(:contacts, :view_all)
  end

  def create?
    administrator? || beclinic_can?(:contacts, :create)
  end

  def avatar?
    administrator? || beclinic_can?(:contacts, :edit)
  end

  def destroy?
    administrator? || beclinic_can?(:contacts, :delete) || beclinic_can?(:chat, :delete_contact)
  end

  private

  def administrator?
    @account_user&.administrator?
  end
end
