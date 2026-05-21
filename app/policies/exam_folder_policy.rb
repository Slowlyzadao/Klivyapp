class ExamFolderPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_exams)
  end

  def show?
    beclinic_can?(:patients, :view_exams)
  end

  def create?
    beclinic_can?(:patients, :manage_exams)
  end

  def update?
    beclinic_can?(:patients, :manage_exams)
  end

  def destroy?
    beclinic_can?(:patients, :manage_exams)
  end

  def reorder?
    beclinic_can?(:patients, :manage_exams)
  end
end
