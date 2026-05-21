module Api
  module V1
    module Accounts
      module Financial
        class AuditLogsController < BaseController
          before_action :require_admin_or_auditor!

          def index
            scope = ::Financial::AuditLog.for_account(current_account.id).recent_first
            scope = scope.where(entity_type: params[:entity_type]) if params[:entity_type].present?
            scope = scope.where(entity_id: params[:entity_id]) if params[:entity_id].present?
            scope = scope.where(action: params[:action]) if params[:action].present?
            scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?
            scope = scope.where('created_at >= ?', params[:from]) if params[:from].present?
            scope = scope.where('created_at <= ?', params[:to]) if params[:to].present?
            if params[:q].present?
              like = "%#{params[:q].to_s.downcase}%"
              scope = scope.where(
                'LOWER(entity_type) LIKE :q OR CAST(entity_id AS TEXT) LIKE :q OR LOWER(ip_address) LIKE :q',
                q: like
              )
            end

            page = (params[:page] || 1).to_i
            per = [(params[:per_page] || 50).to_i, 200].min
            total = scope.count
            entries = scope.offset((page - 1) * per).limit(per)
            user_ids = entries.map(&:user_id).compact.uniq
            users_index = ::User.where(id: user_ids).index_by(&:id)

            render json: {
              data: entries.map { |log| serialize(log, users_index) },
              meta: {
                page: page, per_page: per, total: total,
                # Filtros úteis pro frontend popular dropdowns sem chamada extra.
                facets: build_facets
              }
            }
          end

          def export_csv
            require_admin_or_auditor!
            scope = ::Financial::AuditLog.for_account(current_account.id).recent_first
            scope = scope.where(created_at: params[:from]..params[:to]) if params[:from].present? && params[:to].present?
            csv = CSV.generate do |out|
              out << %w[created_at user_id action entity_type entity_id ip before after]
              scope.find_each do |log|
                out << [
                  log.created_at.iso8601, log.user_id, log.action, log.entity_type, log.entity_id,
                  log.ip_address, log.before.to_json, log.after.to_json
                ]
              end
            end
            send_data csv, type: 'text/csv', filename: "financial_audit_#{Date.current}.csv"
          end

          private

          def require_admin_or_auditor!
            render(json: { error: 'forbidden' }, status: :forbidden) unless user_has_any_role?(%w[ADMIN AUDITOR GERENTE])
          end

          ENTITY_LABELS = {
            'Financial::Budget'           => 'Orçamento',
            'Financial::Installment'      => 'Parcela',
            'Financial::PaymentReceipt'   => 'Recibo',
            'Financial::Expense'          => 'Despesa',
            'Financial::Entry'            => 'Lançamento',
            'Financial::CashRegister'     => 'Caixa',
            'Financial::CashMovement'     => 'Mov. de caixa',
            'Financial::PatientCredit'    => 'Crédito do paciente',
            'Financial::CommissionRule'   => 'Regra de comissão',
            'Financial::CommissionEntry'  => 'Comissão',
            'Financial::RecurringExpense' => 'Despesa recorrente',
            'Financial::RevenueGoal'      => 'Meta de receita',
            'Financial::BankAccount'      => 'Conta bancária',
            'Financial::DreCategory'      => 'Categoria DRE',
            'Financial::GatewaySetting'   => 'Configuração gateway'
          }.freeze

          ACTION_LABELS = {
            'create'  => 'Criação',
            'update'  => 'Edição',
            'destroy' => 'Exclusão',
            'restore' => 'Restauração',
            'denied'  => 'Acesso negado'
          }.freeze

          def serialize(log, users_index = {})
            user = users_index[log.user_id]
            {
              id: log.id,
              created_at: log.created_at,
              user_id: log.user_id,
              user: user ? {
                id: user.id,
                name: user.name,
                avatar_url: user.try(:resolved_avatar_url)
              } : nil,
              action: log.action,
              action_label: ACTION_LABELS[log.action] || log.action.to_s.humanize,
              entity_type: log.entity_type,
              entity_label: ENTITY_LABELS[log.entity_type] || log.entity_type.to_s.split('::').last,
              entity_id: log.entity_id,
              ip: log.ip_address,
              user_agent: log.user_agent,
              before: log.before,
              after: log.after,
              changed_keys: compute_diff_keys(log.before, log.after),
              metadata: log.metadata
            }
          end

          # Facets pra dropdowns: tipos de entidade + ações + usuários presentes
          # no histórico. Limita a últimos 90 dias pra não escanear tudo.
          def build_facets
            window = ::Financial::AuditLog.for_account(current_account.id)
                                          .where('created_at >= ?', 90.days.ago)
            entity_types = window.distinct.pluck(:entity_type).compact.sort
            actions      = window.distinct.pluck(:action).compact.sort
            user_ids     = window.distinct.pluck(:user_id).compact
            users = ::User.where(id: user_ids).pluck(:id, :name).map { |id, name| { id: id, name: name } }

            {
              entity_types: entity_types.map { |t| { value: t, label: ENTITY_LABELS[t] || t.split('::').last } },
              actions:      actions.map      { |a| { value: a, label: ACTION_LABELS[a] || a.humanize } },
              users:        users.sort_by { |u| u[:name].to_s }
            }
          end

          # Diff simples: chaves cujos valores divergem entre before e after.
          # Útil pra UI destacar campos alterados sem reprocessar no client.
          def compute_diff_keys(before, after)
            return [] if before.blank? && after.blank?
            b = before.is_a?(Hash) ? before : {}
            a = after.is_a?(Hash) ? after : {}
            (b.keys | a.keys).select { |k| b[k] != a[k] }
          end
        end
      end
    end
  end
end
