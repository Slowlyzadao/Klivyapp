module Financial
  module Reports
    # Metas vs Realizado — canon Hub Relatórios + §4.5 Setup #8 (2026-05-23).
    #
    # Lista todas as Metas (RevenueGoal) ATIVAS cobrindo o período solicitado
    # com o valor REALIZADO calculado on-the-fly (Entry.cash_date no período
    # da meta). Comparativo dos 3 tiers (Mínima / Principal / Desafio) e
    # cálculo de % atingido.
    #
    # Não filtra por start/end do request — mostra todas metas ATIVAS HOJE.
    # O filtro de período do request é informativo (passa adiante pro frontend
    # mostrar o range usado). Cada Meta tem seu próprio período (start_date/
    # end_date) e o `actual_value` da própria Meta respeita esse período.
    #
    # Retorno:
    #   {
    #     period:   { from:, to: },
    #     summary:  { goals_count:, achieved_principal_count:, total_actual_cents:,
    #                 total_target_principal_cents: },
    #     items:    [{
    #       id:, name:, kind:, kind_label:, metric:,
    #       category: {id, name} | nil,
    #       professional: {id, name} | nil,
    #       period: { start_date:, end_date: },
    #       targets: {
    #         min_cents:, principal_cents:, stretch_cents:,
    #         min_qty:, principal_qty:, stretch_qty:
    #       },
    #       actual: { value:, value_cents: | value_qty: },
    #       progress: {
    #         percent_min:, percent_principal:, percent_stretch:,
    #         status: 'sem_meta' | 'abaixo_min' | 'entre_min_e_principal' |
    #                 'atingiu_principal' | 'atingiu_desafio'
    #       }
    #     }]
    #   }
    class GoalsVsActualReport
      KIND_LABELS = {
        'total'         => 'Total da clínica',
        'por_categoria' => 'Por categoria',
        'por_agente'    => 'Por profissional'
      }.freeze

      def self.call(**kwargs) = new(**kwargs).call

      def initialize(account:, from:, to:)
        @account = account
        @from = from.to_date
        @to   = to.to_date
      end

      def call
        goals = scope.includes(:financial_dre_category, :professional).to_a

        items = goals.map { |g| serialize_goal(g) }

        achieved_principal = items.count { |i| %w[atingiu_principal atingiu_desafio].include?(i[:progress][:status]) }
        currency_items = items.select { |i| i[:metric] == 'currency' }
        total_actual_cents = currency_items.sum { |i| i[:actual][:value_cents].to_i }
        total_target_principal = currency_items.sum { |i| i[:targets][:principal_cents].to_i }

        {
          period: { from: @from.iso8601, to: @to.iso8601 },
          summary: {
            goals_count: items.size,
            achieved_principal_count: achieved_principal,
            total_actual_cents: total_actual_cents,
            total_target_principal_cents: total_target_principal
          },
          items: items
        }
      end

      private

      # Metas ativas + que tenham QUALQUER overlap com o período solicitado.
      # Overlap simples: NÃO ((meta.end < from) OR (meta.start > to)).
      def scope
        Financial::RevenueGoal
          .for_account(@account.id)
          .active_goals
          .where.not('end_date < :from OR start_date > :to', from: @from, to: @to)
          .order(:start_date)
      end

      def serialize_goal(goal)
        actual = goal.actual_value.to_i

        targets_cents = {
          min_cents:       goal.min_target_cents.to_i,
          principal_cents: goal.target_cents.to_i,
          stretch_cents:   goal.stretch_target_cents.to_i
        }
        targets_qty = {
          min_qty:       goal.min_target_qty.to_i,
          principal_qty: goal.target_qty.to_i,
          stretch_qty:   goal.stretch_target_qty.to_i
        }

        progress = build_progress(goal, actual, targets_cents, targets_qty)
        actual_payload = goal.metric == 'currency' ? { value_cents: actual } : { value_qty: actual }

        {
          id: goal.id,
          name: goal.name,
          kind: goal.kind,
          kind_label: KIND_LABELS[goal.kind] || goal.kind,
          metric: goal.metric,
          category: goal.financial_dre_category ? { id: goal.financial_dre_category.id, name: goal.financial_dre_category.name } : nil,
          professional: goal.professional ? { id: goal.professional.id, name: goal.professional.name, avatar_url: goal.professional.try(:avatar_url) } : nil,
          period: { start_date: goal.start_date.iso8601, end_date: goal.end_date.iso8601 },
          targets: targets_cents.merge(targets_qty),
          actual: { value: actual }.merge(actual_payload),
          progress: progress
        }
      end

      def build_progress(goal, actual, targets_cents, targets_qty)
        principal = goal.metric == 'currency' ? targets_cents[:principal_cents] : targets_qty[:principal_qty]
        min       = goal.metric == 'currency' ? targets_cents[:min_cents]       : targets_qty[:min_qty]
        stretch   = goal.metric == 'currency' ? targets_cents[:stretch_cents]   : targets_qty[:stretch_qty]

        percent_min       = min.to_i.positive?       ? ((actual.to_f / min)       * 100).round(2) : nil
        percent_principal = principal.to_i.positive? ? ((actual.to_f / principal) * 100).round(2) : nil
        percent_stretch   = stretch.to_i.positive?   ? ((actual.to_f / stretch)   * 100).round(2) : nil

        status =
          if principal.to_i.zero? && min.to_i.zero?
            'sem_meta'
          elsif stretch.to_i.positive? && actual >= stretch
            'atingiu_desafio'
          elsif actual >= principal.to_i
            'atingiu_principal'
          elsif actual >= min.to_i
            'entre_min_e_principal'
          else
            'abaixo_min'
          end

        {
          percent_min:       percent_min,
          percent_principal: percent_principal,
          percent_stretch:   percent_stretch,
          status: status
        }
      end
    end
  end
end
