module Api
  module V1
    module Accounts
      module Financial
        # Lançamentos manuais avulsos no Fluxo de Caixa (canon F-25).
        # NÃO vincula a paciente nem a parcela — é entrada/saída livre que
        # afeta saldo de conta + DRE (se a categoria for receita/despesa).
        #
        # Casos de uso:
        #   • Aporte de sócio (entrada, sem categoria de receita — vai pra "Outras")
        #   • Compra avulsa de material (saída, categoria custo_variavel ou despesa_fixa)
        #   • Multa bancária recebida (entrada, categoria despesa_fixa negativa? não — fica em "Outras receitas")
        #   • Reembolso pago (saída)
        #
        # Lançamentos automáticos (gerados por ReceivePayment, RefundPayment,
        # CashRegister.withdraw/supplement) NÃO passam por aqui — vêm com
        # `source_type` setado e `kind` próprio (recebimento, estorno_receita,
        # transfer, etc.). Aqui é exclusivamente `kind: 'manual_entry'`.
        class EntriesController < BaseController
          before_action :set_entry, only: %i[show update destroy]

          # GET /financial/v2/entries — lista de Entries (todas as movimentações
          # do Fluxo de Caixa, manual + automático).
          def index
            scope = ::Financial::Entry.for_account(current_account.id)
            scope = scope.where(direction: params[:direction]) if params[:direction].present?
            scope = scope.where(kind: params[:kind]) if params[:kind].present?
            scope = scope.where(financial_bank_account_id: params[:bank_account_id]) if params[:bank_account_id].present?
            scope = scope.where(financial_dre_category_id: params[:category_id]) if params[:category_id].present?
            scope = scope.where(patient_id: params[:patient_id]) if params[:patient_id].present?

            # Filtro especial: "sem categoria" (canon F-28 — reclassificação em massa).
            scope = scope.where(financial_dre_category_id: nil) if params[:uncategorized] == 'true'

            scope = scope.where('cash_date >= ?', params[:from]) if params[:from].present?
            scope = scope.where('cash_date <= ?', params[:to])   if params[:to].present?
            if params[:q].present?
              scope = scope.where('LOWER(description) LIKE ?', "%#{params[:q].to_s.downcase}%")
            end

            sort = params[:sort] || 'cash_date'
            direction = params[:direction_order] == 'asc' ? :asc : :desc
            scope = scope.order(sort => direction, created_at: :desc)

            page = (params[:page] || 1).to_i
            per_page = [(params[:per_page] || 25).to_i, 100].min
            total = scope.count
            entries = scope.includes(:financial_bank_account, :financial_dre_category, :patient)
                           .offset((page - 1) * per_page).limit(per_page)

            render json: {
              data: entries.map { |e| serialize(e) },
              meta: {
                page: page, per_page: per_page, total: total,
                total_in_cents: scope.where(direction: 'in').sum(:amount_cents),
                total_out_cents: scope.where(direction: 'out').sum(:amount_cents),
              }
            }
          end

          def show
            render json: serialize(@entry)
          end

          # POST /financial/v2/entries — Cria lançamento manual (canon F-25).
          # Só aceita criação de `kind: 'manual_entry'` por aqui — outros tipos
          # (recebimento, estorno_receita, etc.) são gerados por services.
          def create
            idempotent! do
              attrs = entry_params.to_h.symbolize_keys
              attrs[:account_id] = current_account.id
              attrs[:kind] = 'manual_entry'
              attrs[:registered_by_id] = current_user&.id
              # Default: cash_date = competence_date se não informado.
              attrs[:cash_date] ||= attrs[:competence_date] || Date.current
              attrs[:competence_date] ||= attrs[:cash_date]
              attrs[:affects_dre] = true if attrs[:affects_dre].nil?
              attrs[:affects_cashflow] = true if attrs[:affects_cashflow].nil?

              entry = ::Financial::Entry.new(attrs)
              if entry.save
                render json: serialize(entry), status: :created
              else
                render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          # PATCH /financial/v2/entries/:id — usado especialmente por F-28
          # (reclassificação: muda só `financial_dre_category_id`). Não permite
          # alterar entries automáticas (kind != manual_entry).
          def update
            if @entry.kind != 'manual_entry' && !category_only_update?
              render json: { errors: ['Apenas reclassificação de categoria é permitida em entries automáticas'] },
                     status: :unprocessable_entity
              return
            end

            if @entry.update(entry_params)
              render json: serialize(@entry)
            else
              render json: { errors: @entry.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # POST /financial/v2/entries/bulk_reclassify — F-28.
          # Atribui uma categoria a vários entries de uma vez.
          # Body: { entry_ids: [1,2,3], category_id: 42 }
          def bulk_reclassify
            ids = Array(params[:entry_ids]).map(&:to_i).reject(&:zero?)
            return render(json: { errors: ['Selecione ao menos 1 lançamento'] }, status: :unprocessable_entity) if ids.empty?

            category_id = params[:category_id].presence&.to_i
            # category_id pode ser nil (limpa categoria) — aceitar.
            updated = ::Financial::Entry.for_account(current_account.id)
                                         .where(id: ids)
                                         .update_all(
                                           financial_dre_category_id: category_id,
                                           updated_at: Time.current,
                                           updated_by_id: current_user&.id
                                         )

            render json: { updated: updated, category_id: category_id }
          end

          # DELETE — só permite excluir entries manuais.
          def destroy
            unless @entry.kind == 'manual_entry'
              render json: { errors: ['Lançamentos automáticos não podem ser excluídos. Use o estorno do recibo/despesa de origem.'] },
                     status: :unprocessable_entity
              return
            end

            @entry.destroy
            head :no_content
          end

          private

          def set_entry
            @entry = ::Financial::Entry.for_account(current_account.id).find(params[:id])
          end

          def entry_params
            params.require(:entry).permit(
              :direction, :amount_cents, :description,
              :competence_date, :cash_date,
              :financial_bank_account_id, :financial_dre_category_id,
              :payment_method, :patient_id,
              :affects_dre, :affects_cashflow,
              metadata: {}
            )
          end

          # Detecta se o PATCH é só pra mudar categoria (F-28 reclassificação).
          # Permite isso mesmo em entries automáticas (preserva histórico, só
          # ajusta o DRE).
          def category_only_update?
            return false unless params[:entry].is_a?(ActionController::Parameters) || params[:entry].is_a?(Hash)
            keys = params[:entry].respond_to?(:keys) ? params[:entry].keys.map(&:to_s) : []
            keys.sort == ['financial_dre_category_id']
          end

          def serialize(e)
            bank = e.financial_bank_account
            cat  = e.financial_dre_category
            {
              id: e.id,
              direction: e.direction,
              kind: e.kind,
              kind_label: kind_label(e.kind),
              amount_cents: e.amount_cents.to_i,
              description: e.description,
              competence_date: e.competence_date,
              cash_date: e.cash_date,
              payment_method: e.payment_method,
              bank_account: bank ? { id: bank.id, name: bank.name, kind: bank.kind } : nil,
              category: cat ? { id: cat.id, name: cat.name, kind: cat.kind } : nil,
              patient: e.patient ? {
                id: e.patient.id,
                name: e.patient.name,
                avatar_url: e.patient.try(:resolved_avatar_url),
              } : nil,
              source_type: e.source_type,
              source_id: e.source_id,
              source_label: source_label(e.source_type),
              affects_dre: e.affects_dre,
              affects_cashflow: e.affects_cashflow,
              created_at: e.created_at,
              registered_by_id: e.registered_by_id,
              # Manual entries são as únicas excluíveis/editáveis livres.
              editable: e.kind == 'manual_entry'
            }
          end

          KIND_LABELS = {
            'receita'         => 'Receita',
            'despesa'         => 'Despesa',
            'transferencia'   => 'Transferência',
            'sangria'         => 'Sangria',
            'suprimento'      => 'Suprimento',
            'quebra_caixa'    => 'Quebra de caixa',
            'estorno_receita' => 'Estorno de receita',
            'estorno_despesa' => 'Estorno de despesa',
            'juros'           => 'Juros',
            'multa'           => 'Multa',
            'desconto'        => 'Desconto',
            'manual_entry'    => 'Lançamento avulso'
          }.freeze

          SOURCE_LABELS = {
            'Financial::PaymentReceipt' => 'Recibo',
            'Financial::Expense'        => 'Despesa',
            'Financial::CashRegister'   => 'Caixa',
            'Financial::CashMovement'   => 'Mov. caixa'
          }.freeze

          def kind_label(kind)
            KIND_LABELS[kind] || kind.to_s.humanize
          end

          def source_label(source_type)
            return nil if source_type.blank?

            SOURCE_LABELS[source_type] || source_type.split('::').last
          end
        end
      end
    end
  end
end
