class ChangeProcedureNameToTextInSessionLogs < ActiveRecord::Migration[7.0]
  def up
    # Backfill copia `clinical_notes.conduct` (text, livre) para `procedure_name`
    # e textos longos (>255 chars) estouram a varchar original. Não há outra
    # restrição clínica para limitar o nome do procedimento.
    change_column :session_logs, :procedure_name, :text
  end

  def down
    change_column :session_logs, :procedure_name, :string
  end
end
