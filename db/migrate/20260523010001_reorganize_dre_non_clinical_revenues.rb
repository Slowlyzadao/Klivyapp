# Reorganiza Receita Não Clínica adicionando subgrupo "Outras" como L2.
#
# Wireframe 2026-05-23: estrutura canon de Receitas tem 3 níveis em todos
# os ramos (Grupo > Subgrupo > Item). Antes, Receita Não Clínica tinha
# apenas 2 níveis (Grupo > Item) — assimétrico.
#
# Antes:
#   Receita Não Clínica         (L1)
#     ├── Aluguel de Espaço     (L2)
#     ├── Venda de Produtos     (L2)
#     └── Outras Receitas       (L2)
#
# Depois:
#   Receita Não Clínica         (L1)
#     └── Outras                (L2) ← novo subgrupo intermediário
#         ├── Aluguel de Espaço (L3)
#         ├── Venda de Produtos (L3)
#         └── Outras Receitas   (L3)
#
# Para cada conta com Receita Não Clínica e seus 3 filhos diretos:
# 1. Criar "Outras" como L2 filho de Receita Não Clínica
# 2. Mover os 3 itens pra dentro de "Outras" (atualizar parent_id)
# 3. Recomputar path + level pros 3 itens (now L3)
#
# Idempotente: pula contas onde "Outras" L2 já existe sob Receita Não Clínica.
# Todas as 3 transformações em UMA transaction por conta.
class ReorganizeDreNonClinicalRevenues < ActiveRecord::Migration[7.1]
  def up
    Account.find_each do |account|
      reorganize_account!(account)
    end

    # Bonus fix 2026-05-23: contas que já tinham "Estornos" antes do seed canon
    # rodar ficaram com system_default=false (find_or_create_by não atualizou
    # o flag em registros pré-existentes). Marca todas como system_default
    # explicitamente — é categoria reservada do `RefundPayment` service.
    rows_updated = execute(<<~SQL).cmd_tuples
      UPDATE financial_dre_categories
      SET system_default = true, updated_at = NOW()
      WHERE LOWER(name) = 'estornos'
        AND deleted_at IS NULL
        AND parent_id IS NULL
        AND system_default = false;
    SQL
    say "Estornos system_default corrigido em #{rows_updated} categoria(s)"

    # Idem pra "Taxa de Maquininha e Cartão" — usada pelo ReceivePayment
    # pra criar Entry automática de MDR. Deve ser indelével.
    rows_mdr = execute(<<~SQL).cmd_tuples
      UPDATE financial_dre_categories
      SET system_default = true, updated_at = NOW()
      WHERE LOWER(name) = 'taxa de maquininha e cartão'
        AND deleted_at IS NULL
        AND system_default = false;
    SQL
    say "Taxa de Maquininha system_default corrigido em #{rows_mdr} categoria(s)"

    # Idem pra "Sem categoria" — fallback de categorização (canon §4.1).
    rows_sc = execute(<<~SQL).cmd_tuples
      UPDATE financial_dre_categories
      SET system_default = true, updated_at = NOW()
      WHERE LOWER(name) = 'sem categoria'
        AND deleted_at IS NULL
        AND parent_id IS NULL
        AND system_default = false;
    SQL
    say "'Sem categoria' system_default corrigido em #{rows_sc} categoria(s)"

    say 'Reorganização concluída.'
  end

  def down
    # Reverter desfaria a estrutura canon — não suportar.
    raise ActiveRecord::IrreversibleMigration,
          'Reorganização de hierarquia é forward-only. Restaurar via backup se necessário.'
  end

  private

  def reorganize_account!(account)
    parent = Financial::DreCategory
               .where(account_id: account.id, deleted_at: nil)
               .where('LOWER(name) = ?', 'receita não clínica')
               .where(parent_id: nil)
               .first
    return unless parent

    # Já reorganizado? Pula.
    existing_outras = Financial::DreCategory
                        .where(account_id: account.id, deleted_at: nil, parent_id: parent.id)
                        .where('LOWER(name) = ?', 'outras')
                        .first
    if existing_outras
      say "Account ##{account.id}: 'Outras' já existe — pulando reorganização"
      ensure_items_under_outras!(account, parent, existing_outras)
      return
    end

    # Items atuais (L2) que vão virar L3
    items = Financial::DreCategory
              .where(account_id: account.id, deleted_at: nil, parent_id: parent.id)
              .to_a
    if items.empty?
      say "Account ##{account.id}: Receita Não Clínica sem itens — criando só o subgrupo 'Outras'"
    end

    ActiveRecord::Base.transaction do
      # 1. Cria "Outras" como L2 sob Receita Não Clínica
      outras = Financial::DreCategory.create!(
        account_id: account.id,
        parent_id: parent.id,
        name: 'Outras',
        kind: 'receita',
        color: '#10b981'
      )

      # 2. Re-parent dos itens pra dentro de "Outras"
      items.each do |item|
        item.update!(parent_id: outras.id)
        # `update_descendants_path` é callback no model — vai propagar
        # mudanças se houver mais filhos abaixo. Como esses items são L2/folhas,
        # não há filhos pra propagar — mas o callback é resiliente.
      end

      say "Account ##{account.id}: 'Outras' criada (##{outras.id}), #{items.size} itens movidos"
    end
  end

  # Caso a migration rode 2x: garante que items continuam sob "Outras"
  def ensure_items_under_outras!(account, parent_receita_nao, outras)
    orphans = Financial::DreCategory
                .where(account_id: account.id, deleted_at: nil, parent_id: parent_receita_nao.id)
                .where.not(id: outras.id)
                .to_a
    return if orphans.empty?

    ActiveRecord::Base.transaction do
      orphans.each { |o| o.update!(parent_id: outras.id) }
      say "Account ##{account.id}: #{orphans.size} órfão(s) movidos pra 'Outras' (idempotência)"
    end
  end
end
