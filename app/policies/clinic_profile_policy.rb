class ClinicProfilePolicy < ApplicationPolicy
  # Qualquer membro da conta vê o perfil da clínica (precisamos ler em vários
  # fluxos clínicos — ex.: anamnese pré-preenchendo `default_specialty`).
  def show?
    @account_user.present?
  end

  # Só admin/owner edita. Não amarro a `:financial` porque esse perfil é
  # institucional (especialidades atendidas), não financeiro.
  def update?
    @account_user&.administrator?
  end
end
