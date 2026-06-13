# Roadmap #13 — Versionamento optimista para prevenir lost-update entre dois
# clínicos editando simultaneamente o mesmo plano de tratamento ou evolução.
#
# Usa o suporte nativo do Rails (`ActiveRecord::Locking::Optimistic`) via
# coluna `lock_version`. O Rails:
#   - incrementa automaticamente `lock_version` em cada UPDATE
#   - raise `ActiveRecord::StaleObjectError` se a versão fornecida na
#     atualização for diferente da atual no banco
#
# Anamnesis NÃO recebe a coluna porque já é imutável após `finalized`
# (callback `prevent_edit_if_finalized` em `anamnesis.rb`).

class AddLockVersionForConcurrentEdits < ActiveRecord::Migration[7.0]
  def change
    add_column :treatment_plans, :lock_version, :integer, default: 0, null: false
    add_column :clinical_notes,  :lock_version, :integer, default: 0, null: false
  end
end
