class AgendaServicePolicy < ApplicationPolicy
  # Qualquer membro autenticado da conta pode listar e visualizar
  def index?
    account_user?
  end

  def show?
    account_user?
  end

  # PR #7 da auditoria: usage_stats é só leitura (contadores) — mesmo nível
  # de show. Operadores não-admin que veem o serviço podem ver os contadores.
  def usage_stats?
    account_user?
  end

  # Somente administradores criam, editam e deletam serviços
  def create?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  def reorder?
    administrator?
  end

  # PR de UI overhaul (2026-05-14): só admin pode rodar limpeza em massa.
  # Mesmo nível de destroy?.
  def cleanup_unused?
    administrator?
  end

  def cleanup_unused_preview?
    administrator?
  end

  # PR de arquivados (2026-05-14): restore e hard-delete são privilegiados.
  # Restore desfaz soft-delete (deleted_at=nil), hard-delete remove fisicamente
  # do banco. Ambos exigem admin.
  def restore?
    administrator?
  end

  def destroy_permanently?
    administrator?
  end

  private

  def account_user?
    @account_user.present?
  end

  def administrator?
    @account_user&.administrator?
  end
end
