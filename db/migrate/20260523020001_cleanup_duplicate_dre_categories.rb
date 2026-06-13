# Limpa duplicatas root de DreCategory criadas pelo "Restaurar padrão"
# da tela legacy (antes do refactor canon).
#
# Bug histórico: o `SettingsCategoriesTab.vue` antigo tinha
# `DEFAULT_CATEGORIES` hardcoded em JS com kinds diferentes do canon
# (`despesa_fixa`, `custo_variavel`). Quando o user clicava em "Restaurar
# padrão", criava categorias root com nomes conflitantes (ex: "Pessoal"
# com kind=despesa_fixa, enquanto o seed canon cria "Pessoal" com
# kind=outra_despesa).
#
# Resultado: tela hierárquica nova mostra ambas porque agrupa por
# `kind != 'receita' AND != 'transfer_internal'`.
#
# Esta migration apaga (soft-delete) APENAS duplicates que:
#   - Têm o mesmo nome de outra categoria root no mesmo account
#   - Têm 0 children (alive)
#   - Têm 0 entries / installments / expenses vinculados (não foram usadas)
#
# Casos especiais (entries > 0): NÃO toca, deixa pro operador decidir
# manualmente. Apenas LOGA aviso pro Rails.logger.
#
# Idempotente: rodar 2× não causa dano.
class CleanupDuplicateDreCategories < ActiveRecord::Migration[7.1]
  def up
    Account.find_each do |account|
      cleanup_account!(account)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Soft-delete de duplicatas. Restaurar via UPDATE deleted_at=NULL se necessário.'
  end

  private

  def cleanup_account!(account)
    # Acha grupos root com nomes duplicados
    duplicated_names = ::Financial::DreCategory
                         .for_account(account.id)
                         .alive
                         .where(parent_id: nil)
                         .group(:name)
                         .having('COUNT(*) > 1')
                         .pluck(:name)
    return if duplicated_names.empty?

    duplicated_names.each do |name|
      candidates = ::Financial::DreCategory
                     .for_account(account.id)
                     .alive
                     .where(parent_id: nil, name: name)
                     .order(:id)
                     .to_a

      # Mantém a que tem MAIS filhos (canon tem children completos). Em
      # caso de empate, mantém a mais antiga (id menor).
      keeper = candidates.max_by { |c| [c.children.alive.count, -c.id] }
      to_remove = candidates - [keeper]

      to_remove.each do |dup|
        child_count = dup.children.alive.count
        entry_count = (dup.respond_to?(:entries) ? dup.entries.count : 0) +
                      (dup.respond_to?(:installments) ? dup.installments.count : 0) +
                      (dup.respond_to?(:expenses) ? dup.expenses.count : 0)

        if child_count.positive? || entry_count.positive?
          say(
            "⚠ Account ##{account.id}: '#{dup.name}' id=#{dup.id} tem #{child_count} children + " \
            "#{entry_count} entries — NÃO removida. Manual review necessário."
          )
          next
        end

        dup.update_columns(
          deleted_at: Time.current,
          deleted_by_id: nil,
          updated_at: Time.current
        )
        say "Account ##{account.id}: '#{dup.name}' id=#{dup.id} kind=#{dup.kind} → soft-deleted (mantida id=#{keeper.id})"
      end
    end
  end
end
