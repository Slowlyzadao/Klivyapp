class DocumentPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_documents)
  end

  def show?
    beclinic_can?(:patients, :view_documents)
  end

  def create?
    beclinic_can?(:patients, :manage_documents)
  end

  def update?
    beclinic_can?(:patients, :manage_documents)
  end

  def destroy?
    beclinic_can?(:patients, :manage_documents)
  end

  def generate?
    beclinic_can?(:patients, :manage_documents)
  end

  def attach?
    beclinic_can?(:patients, :manage_documents)
  end
end
