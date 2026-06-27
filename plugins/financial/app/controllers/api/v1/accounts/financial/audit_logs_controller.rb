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

          # Auditoria 2026-05-22 (`ALTO-CTL-02`): antes era síncrono sem
          # rate limit nem range máximo. AUDITOR com má-fé podia:
          #   1. DoS via export sem range (OOM/timeout em accounts com 100M logs)
          #   2. Exfiltrar PII (before/after.to_json contém telefones, emails)
          #
          # Agora:
          #   - Max 90 dias por export (forçado server-side)
          #   - Rate limit: 3 exports / 24h por user (via cache)
          #   - Estimativa de tamanho — se > 50k linhas, ASYNC obrigatório
          #     (job envia link assinado por email, expira em 24h)
          #   - PII sanitization: `before`/`after` JSON é compactado pra mostrar
          #     apenas chaves alteradas (não dump completo da entidade)
          MAX_DAYS_PER_EXPORT = 90
          MAX_SYNC_ROWS = 50_000
          MAX_EXPORTS_PER_DAY = 3

          def export_csv
            return unless ensure_export_rate_limit!
            return unless ensure_max_range!

            scope = export_scope
            row_count = scope.count

            if row_count > MAX_SYNC_ROWS
              # Fase 5: async via AuditLogsExportJob — job gera CSV, sobe pro R2
              # via ActiveStorage e envia email com signed URL (24h).
              ::Financial::AuditLogsExportJob.perform_later(
                account_id: current_account.id,
                user_id: current_user.id,
                from: params[:from],
                to: params[:to],
                filters: {
                  entity_type: params[:entity_type],
                  action: params[:action],
                  user_id: params[:user_id]
                }.compact
              )

              mark_export_used!

              return render(json: {
                async: true,
                message: "Exportação tem #{row_count} linhas (limite síncrono: #{MAX_SYNC_ROWS}). " \
                         "Você receberá um email em #{current_user.email} quando o CSV estiver pronto " \
                         '(link expira em 24h).',
                row_count: row_count,
                notification_email: current_user.email
              }, status: :accepted)
            end

            csv = CSV.generate do |out|
              out << %w[created_at user_id user_name action entity_type entity_id ip changed_keys before after]
              scope.find_each do |log|
                # Sanitização leve: limita JSON dump pra evitar export gigante
                # com payloads inteiros. Mostra apenas chaves alteradas.
                changed_keys = compute_diff_keys(log.before, log.after)
                user_name = User.where(id: log.user_id).pick(:name) if log.user_id

                out << [
                  log.created_at.iso8601,
                  log.user_id,
                  user_name,
                  log.action,
                  log.entity_type,
                  log.entity_id,
                  log.ip_address,
                  changed_keys.join(','),
                  sanitized_json(log.before, changed_keys),
                  sanitized_json(log.after, changed_keys)
                ]
              end
            end

            mark_export_used!
            send_data csv, type: 'text/csv', filename: "financial_audit_#{Date.current}.csv"
          end

          private

          def require_admin_or_auditor!
            render(json: { error: 'forbidden' }, status: :forbidden) unless user_has_any_role?(%w[ADMIN AUDITOR GERENTE])
          end

          # ── Export safety helpers (ALTO-CTL-02) ─────────────────────────────

          def export_scope
            scope = ::Financial::AuditLog.for_account(current_account.id).recent_first
            from = params[:from].presence && Date.parse(params[:from])
            to = params[:to].presence && Date.parse(params[:to])
            scope = scope.where(created_at: from.beginning_of_day..to.end_of_day) if from && to
            scope
          rescue ArgumentError
            ::Financial::AuditLog.none
          end

          def ensure_max_range!
            from = params[:from].presence && Date.parse(params[:from])
            to = params[:to].presence && Date.parse(params[:to])

            unless from && to
              render(json: {
                error: 'date_range_required',
                message: "Export requer 'from' e 'to' (formato YYYY-MM-DD). " \
                         "Range máximo: #{MAX_DAYS_PER_EXPORT} dias."
              }, status: :unprocessable_entity)
              return false
            end

            days = (to - from).to_i
            if days > MAX_DAYS_PER_EXPORT
              render(json: {
                error: 'date_range_too_large',
                message: "Range máximo é #{MAX_DAYS_PER_EXPORT} dias. Recebido: #{days} dias.",
                max_days: MAX_DAYS_PER_EXPORT
              }, status: :unprocessable_entity)
              return false
            end

            true
          rescue ArgumentError
            render(json: {
              error: 'invalid_date_format',
              message: "Datas devem estar no formato YYYY-MM-DD."
            }, status: :unprocessable_entity)
            false
          end

          def export_rate_limit_key
            "financial:audit_export:#{current_account.id}:#{current_user.id}:#{Date.current}"
          end

          def ensure_export_rate_limit!
            count = Rails.cache.read(export_rate_limit_key).to_i
            if count >= MAX_EXPORTS_PER_DAY
              render(json: {
                error: 'rate_limit_exceeded',
                message: "Limite de #{MAX_EXPORTS_PER_DAY} exports por dia atingido. Tente novamente amanhã.",
                used: count,
                max_per_day: MAX_EXPORTS_PER_DAY
              }, status: :too_many_requests)
              return false
            end
            true
          end

          def mark_export_used!
            count = Rails.cache.read(export_rate_limit_key).to_i
            Rails.cache.write(export_rate_limit_key, count + 1, expires_in: 24.hours)
          end

          # Sanitiza dump JSON pra incluir apenas chaves que mudaram + remover
          # campos sensíveis conhecidos (email, telefone, CPF, etc). Reduz
          # superfície de exfiltração de PII.
          PII_KEYS_DROP = %w[email phone telefone cpf cnpj rg full_name name].freeze
          def sanitized_json(payload, changed_keys)
            return '{}' if payload.blank?
            return '{}' unless payload.is_a?(Hash)

            relevant = payload.slice(*changed_keys.map(&:to_s))
            sanitized = relevant.each_with_object({}) do |(k, v), h|
              h[k] = PII_KEYS_DROP.include?(k.to_s.downcase) ? '<redacted>' : v
            end
            sanitized.to_json
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
