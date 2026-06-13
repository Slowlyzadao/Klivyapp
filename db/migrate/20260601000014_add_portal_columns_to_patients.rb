# Colunas do Patient para suportar Suspensão (PRD §5.7) e Recall (PRD §13bis.1).
# Default `active` garante backfill seguro nas accounts existentes.
class AddPortalColumnsToPatients < ActiveRecord::Migration[7.1]
  # Idempotente: algumas colunas (`needs_recall`) podem já existir de iterações
  # anteriores antes do Sprint A. Use `add_column ... if_not_exists` (Rails 7+).
  def change
    add_column :patients, :portal_status,             :string,   null: false, default: 'active', if_not_exists: true
    add_column :patients, :portal_suspended_until,    :datetime,                                  if_not_exists: true
    add_column :patients, :portal_suspension_reason,  :text,                                      if_not_exists: true

    add_column :patients, :needs_recall,              :boolean,  null: false, default: false,     if_not_exists: true
    add_column :patients, :last_recall_at,            :datetime,                                  if_not_exists: true

    add_index  :patients, :portal_status,                                                          if_not_exists: true
    add_index  :patients, :needs_recall,
               where: 'needs_recall = true',
               name: 'idx_patients_needs_recall_partial',
               if_not_exists: true
  end
end
