# Join table between User (specialist agent) and AgendaService (procedure
# they offer). Bea uses these links to know which professionals to consider
# when a patient requests a specific service. Without an explicit link, the
# user is NOT considered for that service — clinics must opt in their team
# to each procedure.
class AgendaServiceUser < ApplicationRecord
  belongs_to :account
  belongs_to :agenda_service
  belongs_to :user

  validates :agenda_service_id, uniqueness: { scope: :user_id }

  # Rails' HABTM-through shortcut (`user.agenda_service_ids = [...]`)
  # auto-creates rows but does NOT populate account_id. Infer it from
  # the linked service so the shortcut is usable from controllers and
  # console without forcing every caller to remember the scope column.
  before_validation :infer_account_id, on: :create

  private

  def infer_account_id
    self.account_id ||= agenda_service&.account_id || user&.account_ids&.first
  end
end
