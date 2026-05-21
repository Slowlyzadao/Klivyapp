class AddProcedureNameToSessionLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :session_logs, :procedure_name, :string
  end
end
