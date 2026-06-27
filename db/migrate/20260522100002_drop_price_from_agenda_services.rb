# Remove coluna `price` de `agenda_services`.
#
# Decisão arquitetural (2026-05-22, doc `financial-2026-05-implementation.md` §0):
# Separação de domínio entre `agenda` e `financial`:
#   - Nome / duração / cor / sala / profissionais vinculados ficam em
#     `AgendaService` (plugin `agenda`).
#   - Preço particular, preço convênio, DRE category e regra de comissão
#     padrão ficam em `Financial::ServicePricing` (plugin `financial`,
#     1-to-1 com AgendaService).
#
# UI de `/agenda/settings > aba Serviços` deixa de exibir/editar preço.
# UI de `/financial/v2/settings > tab Serviços` (nova) controla pricing.
#
# Sem cliente real usando — clean break. Importação Clinicorp/Eddental via
# `/super_admin/migrations` já populará ServicePricing diretamente quando
# vier valor da clínica origem.
class DropPriceFromAgendaServices < ActiveRecord::Migration[7.1]
  def up
    return unless column_exists?(:agenda_services, :price)
    remove_column :agenda_services, :price
  end

  def down
    return if column_exists?(:agenda_services, :price)
    add_column :agenda_services, :price, :decimal, precision: 10, scale: 2, default: 0
  end
end
