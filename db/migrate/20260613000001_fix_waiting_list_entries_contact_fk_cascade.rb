# Plugin agenda: a FK waiting_list_entries.contact_id era restritiva (sem
# on_delete) e contact_id é NOT NULL — então deletar um Contact que estava
# numa lista de espera estourava PG::ForeignKeyViolation (500 ao excluir
# contato). O Contact também não tinha `has_many :waiting_list_entries` com
# dependent (só Account tinha). Cascade no banco garante que a entrada de
# lista de espera some junto com o contato, por QUALQUER rota de deleção.
class FixWaitingListEntriesContactFkCascade < ActiveRecord::Migration[7.1]
  def up
    return unless foreign_key_exists?(:waiting_list_entries, :contacts)

    remove_foreign_key :waiting_list_entries, :contacts
    add_foreign_key :waiting_list_entries, :contacts, on_delete: :cascade
  end

  def down
    return unless foreign_key_exists?(:waiting_list_entries, :contacts)

    remove_foreign_key :waiting_list_entries, :contacts
    add_foreign_key :waiting_list_entries, :contacts
  end
end
