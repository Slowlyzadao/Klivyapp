class TreatmentPlanPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_treatment_plans)
  end

  def show?
    beclinic_can?(:patients, :view_treatment_plans)
  end

  def create?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  # Edição e exclusão são permitidas em qualquer status — administradores
  # precisam corrigir planos aprovados (CID errado, valor a ajustar) sem ter
  # que cancelar e recriar tudo. Aprovar plano gera Financial::Budget v2 em
  # RASCUNHO ("Precisa aprovação" no Financial Tab — recepção valida números
  # e clica "Aprovar orçamento" pra gerar parcelas). Ver
  # `Patients::TreatmentPlanBudgetCreator`.
  def update?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def destroy?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def approve?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  def cancel?
    beclinic_can?(:patients, :manage_treatment_plans)
  end

  # Baixar o PDF do plano usa a mesma permissão de visualizar.
  def pdf?
    show?
  end
end
