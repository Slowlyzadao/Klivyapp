class AccountTransactionPolicy < ApplicationPolicy
  # Transações são compartilhadas pelas páginas Receber/Pagar/Fluxo/Caixa.
  # Para listar/ver, basta o usuário ter qualquer perm de visualização do
  # módulo financeiro — a guarda de rota da página específica já restringe
  # qual seção o usuário consegue abrir.
  FINANCIAL_VIEW_PERMS = %i[
    view_dashboard
    view_cashflow
    view_receivables
    view_payables
    view_dre
    view_reports
    view_cash_register
  ].freeze

  def index?
    FINANCIAL_VIEW_PERMS.any? { |perm| beclinic_can?(:financial, perm) }
  end

  def show?
    index?
  end

  def create?
    beclinic_can?(:financial, :create_transaction)
  end

  def update?
    beclinic_can?(:financial, :edit_transaction)
  end

  def destroy?
    beclinic_can?(:financial, :delete_transaction)
  end
end
