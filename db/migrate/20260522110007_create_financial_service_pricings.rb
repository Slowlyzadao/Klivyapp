# Cria `financial_service_pricings` — preço financeiro 1-to-1 com `AgendaService`.
#
# Decisão arquitetural 2026-05-22 (doc `financial-2026-05-implementation.md` §0):
# Separação de domínio entre `agenda` e `financial`:
# - Nome / duração / cor / sala / profissionais → `agenda_services` (agenda plugin)
# - Preço particular, preço convênio, DRE category, comissão padrão, TUSS →
#   `financial_service_pricings` (este plugin)
#
# Migration `drop_price_from_agenda_services` (2026-05-22) já removeu o
# campo `price` de `agenda_services`. Esta migration adiciona onde o valor
# vive agora.
#
# UI:
# - `/agenda/settings > aba Serviços` mostra apenas dados de agendabilidade
# - `/financial/v2/settings > tab Serviços` (NOVA tab Fase 2B) lista todos
#   os AgendaServices da conta e permite preencher/editar pricing
#
# Serviço sem pricing cadastrado = warning "Falta configurar preço" + bloqueio
# ao tentar gerar Budget/Installment com este serviço (validação no service).
class CreateFinancialServicePricings < ActiveRecord::Migration[7.1]
  def change
    create_table :financial_service_pricings do |t|
      t.bigint  :account_id,         null: false
      t.bigint  :agenda_service_id,  null: false
      # 1-to-1 com AgendaService (unique index abaixo)

      t.bigint  :financial_dre_category_id, null: false
      # Categoria contábil que cai no DRE quando lançado financeiramente

      t.bigint  :particular_price_cents, null: false, default: 0
      t.bigint  :convenio_price_cents
      # null = não aceita convênio. Quando preenchido, é o preço aplicado em
      # Budget com forma de pagamento "convenio".

      t.bigint  :default_commission_rule_id
      # Regra padrão aplicada quando este serviço gera comissão.
      # Pode ser override no Budget (canon §4.3).

      t.string  :tuss_code,     limit: 32
      # Código TUSS (Terminologia Unificada da Saúde Suplementar) — obrigatório
      # pra emissão TISS de convênios médicos. Pra odontologia, opcional.
      t.string  :internal_code, limit: 32
      # Código interno da clínica — ex: "PROC-001"

      t.text    :notes
      t.string  :status, null: false, default: 'active', limit: 16
      # status: active | inactive

      t.bigint  :created_by_id
      t.bigint  :updated_by_id
      t.bigint  :deleted_by_id
      t.datetime :deleted_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :financial_service_pricings, :account_id
    add_index :financial_service_pricings, %i[account_id agenda_service_id], unique: true,
              where: 'deleted_at IS NULL',
              name: 'idx_uniq_service_pricing_per_service'
    add_index :financial_service_pricings, %i[account_id financial_dre_category_id],
              where: 'deleted_at IS NULL',
              name: 'idx_service_pricings_dre_category'
    add_index :financial_service_pricings, %i[account_id tuss_code], unique: true,
              where: 'tuss_code IS NOT NULL AND deleted_at IS NULL',
              name: 'idx_uniq_service_pricings_tuss'
    add_index :financial_service_pricings, %i[account_id internal_code], unique: true,
              where: 'internal_code IS NOT NULL AND deleted_at IS NULL',
              name: 'idx_uniq_service_pricings_internal_code'

    add_foreign_key :financial_service_pricings, :accounts,
                    column: :account_id, on_delete: :restrict
    add_foreign_key :financial_service_pricings, :agenda_services,
                    column: :agenda_service_id, on_delete: :restrict
    add_foreign_key :financial_service_pricings, :financial_dre_categories,
                    column: :financial_dre_category_id, on_delete: :restrict
    add_foreign_key :financial_service_pricings, :financial_commission_rules,
                    column: :default_commission_rule_id, on_delete: :restrict

    add_check_constraint :financial_service_pricings,
                         'particular_price_cents >= 0',
                         name: 'chk_service_pricings_particular_nonneg'
    add_check_constraint :financial_service_pricings,
                         'convenio_price_cents IS NULL OR convenio_price_cents >= 0',
                         name: 'chk_service_pricings_convenio_nonneg'
    add_check_constraint :financial_service_pricings,
                         "status IN ('active','inactive')",
                         name: 'chk_service_pricings_status'
  end
end
