module Api
  module V1
    module Accounts
      module Financial
        # Precificação financeira 1-to-1 com AgendaService.
        # Decisão arquitetural 2026-05-22: nome em agenda, preço aqui.
        #
        # Endpoint `index` retorna TODOS os AgendaServices da conta, mesmo
        # os SEM pricing — frontend mostra warning "Falta configurar preço"
        # e botão "Configurar agora".
        #
        # `upsert` substitui create+update porque é 1-to-1 — operador
        # pensa "configurar preço do serviço X" não "criar pricing #123".
        class ServicePricingsController < BaseController
          skip_before_action :ensure_setup_complete!, only: %i[index]

          before_action :authorize_write!, only: %i[upsert deactivate]

          # GET /financial/v2/service_pricings
          # Retorna [{agenda_service, pricing, stats}] — pricing pode ser null
          # pra serviços não configurados. Stats sempre presente (pode ser zero).
          #
          # Stats agregados em batch pra evitar N+1:
          # - historical_qty: count de Installments executados por service
          # - has_real_data: bool (qty > 0) — vira badge "REAL" na UI
          # - price_min_cents / price_max_cents: faixa real de unit_amount_cents
          #   nos BudgetItems históricos (ou null se não houver dado)
          def index
            agenda_services = ::AgendaService
                                .where(account_id: current_account.id, deleted_at: nil)
                                .order(:position, :name)
            service_ids = agenda_services.map(&:id)

            pricings_by_service = ::Financial::ServicePricing
                                    .for_account(current_account.id)
                                    .alive
                                    .includes(:financial_dre_category)
                                    .where(agenda_service_id: service_ids)
                                    .index_by(&:agenda_service_id)

            stats_by_service = aggregate_stats(service_ids)

            data = agenda_services.each_with_index.map do |service, idx|
              pricing = pricings_by_service[service.id]
              stats = stats_by_service[service.id] || empty_stats
              {
                # Código sequencial preferindo internal_code, fallback pra posição (001, 002...)
                code: pricing&.internal_code.presence || format('%03d', idx + 1),
                agenda_service: serialize_service(service),
                pricing: pricing ? serialize_pricing(pricing) : nil,
                stats: stats
              }
            end
            render json: { data: data }
          end

          # GET /financial/v2/service_pricings/:agenda_service_id
          def show
            service = ::AgendaService.find_by(id: params[:id], account_id: current_account.id)
            return render(json: { error: 'agenda_service_not_found' }, status: :not_found) unless service

            pricing = ::Financial::ServicePricing
                        .for_account(current_account.id)
                        .alive
                        .find_by(agenda_service_id: service.id)

            render json: {
              agenda_service: serialize_service(service),
              pricing: pricing ? serialize_pricing(pricing) : nil
            }
          end

          # PUT /financial/v2/service_pricings/:agenda_service_id
          # Cria ou atualiza pricing pro agenda_service.
          def upsert
            service = ::AgendaService.find_by(id: params[:id], account_id: current_account.id)
            return render(json: { error: 'agenda_service_not_found' }, status: :not_found) unless service

            idempotent! do
              pricing = ::Financial::ServicePricing
                          .for_account(current_account.id)
                          .alive
                          .find_or_initialize_by(agenda_service_id: service.id)
              pricing.assign_attributes(pricing_params.merge(account_id: current_account.id))

              if pricing.save
                render json: serialize_pricing(pricing), status: pricing.previously_new_record? ? :created : :ok
              else
                render json: { errors: pricing.errors.full_messages }, status: :unprocessable_entity
              end
            end
          end

          # DELETE /financial/v2/service_pricings/:agenda_service_id
          # Inativa pricing — AgendaService permanece intacto. Sem pricing,
          # o serviço deixa de aparecer em selects de Budget até reconfigurar.
          def deactivate
            service = ::AgendaService.find_by(id: params[:id], account_id: current_account.id)
            return render(json: { error: 'agenda_service_not_found' }, status: :not_found) unless service

            pricing = ::Financial::ServicePricing
                        .for_account(current_account.id)
                        .alive
                        .find_by(agenda_service_id: service.id)
            return render(json: { ok: true, already_unconfigured: true }) unless pricing

            idempotent_optional! do
              pricing.soft_delete!(user: current_user)
              render json: { ok: true }
            end
          end

          private

          def authorize_write!
            require_role!('ADMIN', 'GERENTE') and return unless user_has_any_role?(%w[ADMIN GERENTE])
          end

          def pricing_params
            params.require(:service_pricing).permit(
              :financial_dre_category_id,
              :particular_price_cents,
              :convenio_price_cents,
              :default_commission_rule_id,
              :tuss_code,
              :internal_code,
              :notes,
              :status
            )
          end

          def serialize_service(s)
            {
              id: s.id,
              uuid: s.uuid,
              name: s.name,
              duration_minutes: s.duration_minutes,
              color: s.color,
              requires_room: s.requires_room
            }
          end

          def serialize_pricing(p)
            # `category_name` expõe o nome da DreCategory no payload pra UI
            # mostrar sem N+1 (ex.: tab Serviços da Agenda exibe "R$ 5.000 ·
            # Implantes" como status financeiro). Eager-load via
            # `belongs_to :financial_dre_category` do model.
            cat = p.financial_dre_category
            {
              id: p.id,
              agenda_service_id: p.agenda_service_id,
              financial_dre_category_id: p.financial_dre_category_id,
              category_name: cat&.name,
              particular_price_cents: p.particular_price_cents,
              convenio_price_cents: p.convenio_price_cents,
              accepts_convenio: p.accepts_convenio?,
              default_commission_rule_id: p.default_commission_rule_id,
              tuss_code: p.tuss_code,
              internal_code: p.internal_code,
              notes: p.notes,
              status: p.status,
              created_at: p.created_at,
              updated_at: p.updated_at
            }
          end

          def empty_stats
            {
              historical_qty: 0,
              has_real_data: false,
              price_min_cents: nil,
              price_max_cents: nil,
              last_used_at: nil
            }
          end

          # Agrega stats históricos por AgendaService.
          #
          # Vínculo atual: BudgetItem → TreatmentItem.agenda_service_id (caminho
          # indireto via plugin patients). O canon de implementação prevê
          # `BudgetItem.agenda_service_id` direto, mas o schema atual usa
          # apenas o caminho via TreatmentItem. JOIN explícito por isso.
          #
          # Estatísticas calculadas (Budgets aprovados/concluídos apenas):
          #   historical_qty  = COUNT(BudgetItem) por agenda_service
          #   has_real_data   = qty > 0 → vira badge "REAL" na UI
          #   price_min/max   = MIN/MAX(unit_price_cents) histórico real
          #   last_used_at    = MAX(BudgetItem.created_at)
          #
          # Safe contra schema variations — captura erros silenciosamente e
          # retorna stats vazias se o vínculo não existir (UI degrada bem).
          def aggregate_stats(service_ids)
            return {} if service_ids.empty?

            # Vínculo via TreatmentItem (schema atual). Caso o TreatmentItem
            # não tenha agenda_service_id em algum ambiente, o rescue abaixo
            # devolve {} e a UI mostra "—" em todos os stats.
            agg = ::Financial::BudgetItem
                    .joins('INNER JOIN financial_budgets ON financial_budgets.id = financial_budget_items.financial_budget_id')
                    .joins('LEFT JOIN treatment_items ON treatment_items.id = financial_budget_items.treatment_item_id')
                    .where(financial_budget_items: { account_id: current_account.id })
                    .where('treatment_items.agenda_service_id IN (?)', service_ids)
                    .where(financial_budgets: { status: %w[aprovado concluido] })
                    .group('treatment_items.agenda_service_id')
                    .pluck(
                      'treatment_items.agenda_service_id',
                      Arel.sql('COUNT(*) AS qty'),
                      Arel.sql('MIN(financial_budget_items.unit_price_cents) AS price_min'),
                      Arel.sql('MAX(financial_budget_items.unit_price_cents) AS price_max'),
                      Arel.sql('MAX(financial_budget_items.created_at) AS last_at')
                    )

            agg.each_with_object({}) do |row, h|
              service_id, qty, p_min, p_max, last_at = row
              h[service_id] = {
                historical_qty: qty.to_i,
                has_real_data: qty.to_i.positive?,
                price_min_cents: p_min&.to_i,
                price_max_cents: p_max&.to_i,
                last_used_at: last_at
              }
            end
          rescue ActiveRecord::StatementInvalid, ActiveRecord::ConfigurationError => e
            # Schema sem o vínculo esperado (ex: TreatmentItem sem coluna
            # agenda_service_id em ambiente legacy). UI degrada graciosamente
            # mostrando "—" em vez de 500.
            Rails.logger.warn("[ServicePricings#aggregate_stats] #{e.class}: #{e.message}")
            {}
          end
        end
      end
    end
  end
end
