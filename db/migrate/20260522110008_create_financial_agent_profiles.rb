# Cria `financial_agent_profiles` — extensão financeira de `users` (1-to-1).
#
# Decisão arquitetural 2026-05-22:
# `User` core do Klivy gerencia identidade (login, role, availability) via
# `/api/v1/accounts/:id/agents`. Campos específicos do financeiro (canon
# `mapa-financeiro.json` step 1) vivem aqui, sem mexer no User core.
#
# Sem AgentProfile = user não aparece em selects de DR/SDR/Comercial nos
# fluxos financeiros (validação no service).
class CreateFinancialAgentProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_agent_profiles do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id,    null: false
      # 1-to-1 com User (unique index abaixo)

      t.string :cpf, limit: 20
      # CPF (formatado ou só dígitos — formato decidido no model)

      t.string :agent_category, null: false, limit: 20
      # canon: profissional | operacional | comercial | administrador
      t.string :bond_type, null: false, limit: 10
      # canon: PJ | CLT | Socio
      t.date :entry_date, null: false
      t.boolean :commissionable, null: false, default: false

      # Apenas para agent_category='profissional'
      t.string :cro, limit: 40
      t.string :specialties, array: true, limit: 80
      # Array de especialidades (canon §1: Endodontia, Periodontia, etc)

      # Dados bancários para pagamento de comissão
      t.string :bank_name,           limit: 120
      t.string :bank_agency,         limit: 20
      t.string :bank_account_number, limit: 40
      t.string :pix_key,             limit: 120

      t.string :status, null: false, default: 'active', limit: 16
      # status: active | inactive

      t.text :notes

      t.bigint :created_by_id
      t.bigint :updated_by_id
      t.bigint :deleted_by_id
      t.datetime :deleted_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :financial_agent_profiles, :account_id
    add_index :financial_agent_profiles, %i[account_id user_id], unique: true,
              where: 'deleted_at IS NULL',
              name: 'idx_uniq_agent_profile_per_user'
    add_index :financial_agent_profiles, %i[account_id agent_category],
              where: 'deleted_at IS NULL',
              name: 'idx_agent_profiles_category'
    add_index :financial_agent_profiles, %i[account_id commissionable],
              where: 'deleted_at IS NULL AND commissionable = true',
              name: 'idx_agent_profiles_commissionable'

    add_foreign_key :financial_agent_profiles, :accounts,
                    column: :account_id, on_delete: :restrict
    add_foreign_key :financial_agent_profiles, :users,
                    column: :user_id, on_delete: :restrict

    add_check_constraint :financial_agent_profiles,
                         "agent_category IN ('profissional','operacional','comercial','administrador')",
                         name: 'chk_agent_profiles_category'
    add_check_constraint :financial_agent_profiles,
                         "bond_type IN ('PJ','CLT','Socio')",
                         name: 'chk_agent_profiles_bond_type'
    add_check_constraint :financial_agent_profiles,
                         "status IN ('active','inactive')",
                         name: 'chk_agent_profiles_status'
    add_check_constraint :financial_agent_profiles,
                         "agent_category != 'profissional' OR cro IS NOT NULL",
                         name: 'chk_agent_profiles_profissional_has_cro'
    add_check_constraint :financial_agent_profiles,
                         "agent_category != 'administrador' OR commissionable = false",
                         name: 'chk_agent_profiles_admin_not_commissionable'
  end
end
