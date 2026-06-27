module Api
  module V1
    module Accounts
      module Financial
        class DreCategoriesController < BaseController
          # Setup wizard precisa criar categorias antes do setup estar completo.
          skip_before_action :ensure_setup_complete!
          before_action :set_category, only: %i[show update destroy set_default]

          def index
            categories = scope.ordered
            categories = categories.where(kind: params[:kind]) if params[:kind].present?
            categories = categories.where(active: true) if params[:active] == 'true'
            # Filtra `system_default` da listagem normal — wireframe 2026-05-23.
            # Categorias reservadas (Estornos, Taxa de Maquininha, Sem categoria)
            # não devem aparecer pra edição.
            categories = categories.where(system_default: [false, nil]) if params[:include_system] != 'true'

            cats = categories.to_a

            # has_children calculado em batch pra evitar N+1 — junta count de
            # children por parent_id e injeta no serializer.
            parent_ids_with_children = ::Financial::DreCategory
                                         .for_account(current_account.id)
                                         .alive
                                         .where.not(parent_id: nil)
                                         .distinct
                                         .pluck(:parent_id)
                                         .to_set

            # Contagem de vínculos por categoria (batch, sem N+1). Filtra por
            # `financial_dre_category_id IN (ids da conta)` → já fica account-scoped.
            # Alimenta o badge "em uso" e a desativação do botão excluir na UI.
            ids = cats.map(&:id)
            entry_counts   = ::Financial::Entry.where(financial_dre_category_id: ids).group(:financial_dre_category_id).count
            inst_counts    = ::Financial::Installment.where(financial_dre_category_id: ids).group(:financial_dre_category_id).count
            exp_counts     = ::Financial::Expense.where(financial_dre_category_id: ids).group(:financial_dre_category_id).count
            pricing_counts = ::Financial::ServicePricing.where(financial_dre_category_id: ids).group(:financial_dre_category_id).count

            data = cats.map do |c|
              serialize(
                c,
                has_children: parent_ids_with_children.include?(c.id),
                entries_count: entry_counts.fetch(c.id, 0) + inst_counts.fetch(c.id, 0) + exp_counts.fetch(c.id, 0),
                pricings_count: pricing_counts.fetch(c.id, 0)
              )
            end
            render json: { data: data }
          end

          def show
            render json: serialize(@category)
          end

          def create
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            idempotent_optional! do
              category = scope.new(category_params)
              if category.save
                render json: serialize(category), status: :created
              else
                render json: { errors: category.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          def update
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            if @category.update(category_params)
              render json: serialize(@category)
            else
              render json: { errors: @category.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN])

            # Cadeia de validação de integridade — falha rápido na primeira
            # restrição encontrada, com mensagem específica pra UI exibir.
            if @category.default?
              return render(json: { error: 'Categoria reservada do sistema (não excluível).' }, status: :unprocessable_entity)
            end
            if @category.has_children?
              return render(json: { error: 'Categoria possui subcategorias. Exclua os filhos antes.' }, status: :unprocessable_entity)
            end
            if @category.has_entries?
              return render(json: { error: 'Categoria possui lançamentos vinculados (receitas, despesas ou parcelas). Migre os lançamentos pra outra categoria antes de excluir.' }, status: :unprocessable_entity)
            end
            if @category.has_pricings?
              return render(json: { error: 'Categoria está vinculada a um ou mais procedimentos (preço configurado). Atualize esses serviços em Financeiro → Procedimentos antes de excluir.' }, status: :unprocessable_entity)
            end

            @category.soft_delete!(user: current_user)
            head :no_content
          end

          # Restaura o canon do Plano de Contas. ADITIVO/IDEMPOTENTE: recria apenas
          # as categorias padrão que estiverem faltando (via SeedDefaultCategories,
          # o mesmo service do bootstrap de conta nova). NÃO apaga nem renomeia
          # categorias personalizadas e NÃO mexe em lançamentos. A resposta traz
          # { created, skipped, total } pra UI mostrar o efeito real (sem mentir
          # sucesso quando nada mudou).
          def restore_defaults
            require_role!('ADMIN') and return unless user_has_any_role?(%w[ADMIN])

            idempotent_optional! do
              result = ::Financial::Bootstrap::SeedDefaultCategories.call(account: current_account)
              if result.success?
                render json: { data: result.data }
              else
                render json: { errors: result.errors }, status: :unprocessable_entity
              end
            end
          end

          # Define qual categoria de RECEITA é a padrão da conta — a que recebe
          # os lançamentos sem categoria explícita (avulso à vista, plano de
          # tratamento, mensalidade recorrente), via `default_revenue_category_id`
          # em ApproveBudget/ReceivePayment/GenerateRecurringInstallments.
          #
          # Sem uma padrão definida, o fallback (`receitas.pick(:id)`) pega uma
          # receita ARBITRÁRIA — a primeira do banco, sem ORDER BY — fazendo toda
          # receita empilhar numa categoria sem querer. Esta ação dá controle:
          # só UMA receita é padrão por conta (marcar outra limpa a anterior).
          # Categorias reservadas (system_default, ex: Estornos) e inativas não
          # podem ser padrão.
          def set_default
            require_role!('GERENTE', 'ADMIN') and return unless user_has_any_role?(%w[GERENTE ADMIN])

            if @category.kind != 'receita'
              return render(json: { error: 'Só categorias de receita podem ser a receita padrão.' }, status: :unprocessable_entity)
            end
            if @category.system_default
              return render(json: { error: 'Categoria reservada do sistema não pode ser a receita padrão.' }, status: :unprocessable_entity)
            end
            if @category.active == false
              return render(json: { error: 'Categoria inativa não pode ser a receita padrão. Reative antes.' }, status: :unprocessable_entity)
            end

            idempotent_optional! do
              ::Financial::DreCategory.transaction do
                scope.where(kind: 'receita', is_default: true)
                     .where.not(id: @category.id)
                     .update_all(is_default: false, updated_at: Time.current)
                @category.update!(is_default: true)
              end
              render json: serialize(@category)
            end
          end

          private

          def scope
            ::Financial::DreCategory.for_account(current_account.id)
          end

          def set_category
            @category = scope.find(params[:id])
          end

          def category_params
            params.require(:category).permit(:name, :kind, :parent_id, :color, :icon, :active, :position)
                  .merge(account_id: current_account.id)
          end

          def serialize(c, has_children: nil, entries_count: nil, pricings_count: nil)
            # Pré-calculados em batch pelo index pra evitar N+1. Quando vierem nil
            # (show/create/update single), calcula sob demanda.
            entries_count  ||= c.entries.count + c.installments.count + c.expenses.count
            pricings_count ||= c.service_pricings.count
            {
              id: c.id,
              name: c.name,
              kind: c.kind,
              parent_id: c.parent_id,
              # Campos da hierarquia 4 níveis (Fase 1B + hotfix de path)
              level: c.level,
              path: c.path,
              system_default: c.system_default,
              # has_children: pré-calculado em batch pelo index pra evitar N+1.
              # Quando vier nil (show/create/update single), calcula sob demanda.
              has_children: has_children.nil? ? c.children.alive.exists? : has_children,
              # Vínculos — UI mostra badge "em uso" e desabilita excluir.
              entries_count: entries_count,
              pricings_count: pricings_count,
              color: c.color,
              icon: c.icon,
              is_default: c.is_default,  # legacy compat
              active: c.active,
              position: c.position
            }
          end
        end
      end
    end
  end
end
