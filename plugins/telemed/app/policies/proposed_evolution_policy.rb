# Sprint L — Política da proposta de evolução gerada por IA.
#
# Regras (PRD §6.3):
#   - Ver/editar/aprovar: SÓ o profissional dono do agendamento OU admin
#     com beclinic_scope='all'. Não aceita "qualquer dentista da clínica" —
#     evolução clínica é PII de quem atendeu.
#
# Note: usamos `record.telemed_recording.agenda_event.user_id` em vez de
# duplicar `user_id` na própria ProposedEvolution. Fonte da verdade é o
# AgendaEvent (Sprint K).
class ProposedEvolutionPolicy < ApplicationPolicy
  def show?
    beclinic_can?(:agenda, :view) && (admin_scope? || owns_event?)
  end

  def update?
    beclinic_can?(:agenda, :edit_event) && (admin_scope? || owns_event?)
  end

  # Aprovar = criar ClinicalNote → exige permissão clínica também.
  # Cobre o caso de scope=own da agenda mas sem permissão de evolução.
  def approve?
    update? && beclinic_can?(:patients, :create_clinical_note)
  end

  def reject?
    update?
  end

  private

  def admin_scope?
    beclinic_scope(:agenda) == 'all'
  end

  def owns_event?
    event = record.telemed_recording&.agenda_event
    event && event.user_id == user.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.joins(telemed_recording: :agenda_event)
                  .where(telemed_recordings: { account_id: account.id })

      return base if user.beclinic_scope(account, :agenda) == 'all'

      base.where(agenda_events: { user_id: user.id })
    end
  end
end
