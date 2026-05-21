class AddCpfIndexToContacts < ActiveRecord::Migration[7.0]
  # Auditoria agendamento público (item 9.8 / cenário H): o `book` faz lookup
  # de Contact por CPF via `custom_attributes->>'cpf' = ?`. Sem índice na
  # expressão, cada booking público faz full-table scan em `contacts` — em
  # contas com milhares de pacientes vira gargalo e janela de timeout em
  # picos. Índice B-tree em expressão é suficiente para igualdade exata
  # (que é o uso atual).
  #
  # CONCURRENTLY: tabela `contacts` é grande e está sob tráfego — criar
  # índice sem trava de write. Requer `disable_ddl_transaction!`.

  disable_ddl_transaction!

  def up
    return if index_exists?(:contacts, "(custom_attributes->>'cpf')", name: 'index_contacts_on_custom_attrs_cpf')

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS index_contacts_on_custom_attrs_cpf
        ON contacts ((custom_attributes->>'cpf'))
       WHERE custom_attributes ? 'cpf'
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS index_contacts_on_custom_attrs_cpf
    SQL
  end
end
