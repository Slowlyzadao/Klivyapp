module Financial
  module Commissions
    # Gera CommissionEntry com snapshot completo da regra de comissão.
    # Canon `mapa-financeiro.json` step 5 + Parte 6 §"Imutabilidade primeiro".
    #
    # Chamado por:
    #   - ReceivePayment       quando trigger='pagamento_confirmado'
    #   - ApproveBudget        quando trigger='orcamento_aceito'
    #   - (futuros)            paciente_comparece, profissional_realizou
    #
    # Imutabilidade: snapshot da regra é gravado em `rule_snapshot` jsonb +
    # nos campos derivados (`percent_basis_points`, `mdr_deduction_cents`,
    # `commission_amount_cents`). Mudança POSTERIOR na CommissionRule NÃO
    # afeta entries já criadas — `frozen_attributes` no model bloqueia.
    #
    # Idempotência: o unique index
    # `idx_uniq_commission_entry_per_rule_inst_prof` no banco impede
    # duplicação. Se já existir, retorna a existente.
    class GenerateCommission
      Result = Financial::ServiceResult

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(account:, installment:, applied_cents:, trigger_event:, actor: nil)
        @account = account
        @installment = installment
        @applied_cents = applied_cents.to_i
        @trigger_event = trigger_event.to_s
        @actor = actor
      end

      def call
        return Result.failure('installment required') if @installment.nil?
        return Result.failure('applied_cents must be > 0') if @applied_cents <= 0

        rules = applicable_rules
        return Result.success(commission_entries: []) if rules.empty?

        created = []
        ActiveRecord::Base.transaction do
          rules.each do |rule|
            entry = build_entry(rule)
            next unless entry  # rule_snapshot vazio = pula

            # Idempotência via unique index (idx_uniq_commission_entry_per_rule_inst_prof)
            # — `find_or_create_by` faz lookup primeiro, evita RecordNotUnique.
            existing = ::Financial::CommissionEntry
                         .for_account(@account.id)
                         .where(
                           financial_installment_id: @installment.id,
                           financial_commission_rule_id: rule.id,
                           professional_id: entry.professional_id
                         )
                         .where.not(status: 'estornada')
                         .where(reverses_commission_entry_id: nil)
                         .first
            if existing
              created << existing
              next
            end

            entry.save!
            created << entry
          end
        end

        Result.success(commission_entries: created)
      rescue ActiveRecord::RecordInvalid => e
        Result.failure(e.record.errors.full_messages.join('; '))
      end

      private

      # Busca regras vigentes que casam com o gatilho desta operação.
      # Por enquanto, usa o sistema legacy (CommissionRule sem trigger_event
      # explícito como enum — Fase 2A pendente). Em Fase 4 vai usar o role
      # + trigger_event enum quando o schema for refatorado.
      def applicable_rules
        professional_id = @installment.professional_id
        return [] if professional_id.blank?

        date = @installment.received_at || Date.current

        rules = ::Financial::CommissionRule
                  .for_account(@account.id)
                  .alive
                  .where(professional_id: professional_id, active: true)
                  .where('valid_from <= ?', date)
                  .where('valid_until IS NULL OR valid_until >= ?', date)
                  .order(valid_from: :desc)

        # Pega só a regra mais recente vigente — canon: "Regra mais recente
        # vigente na data do recebimento é a aplicada"
        latest = rules.first
        latest ? [latest] : []
      end

      def build_entry(rule)
        # Snapshot da regra como jsonb. Inclui TUDO o que é necessário
        # pra recalcular sem ler o rule original (auditoria).
        snapshot = {
          rule_id: rule.id,
          kind: rule.kind,
          base: rule.base,
          percent_basis_points: rule.percent_basis_points,
          fixed_amount_cents: rule.fixed_amount_cents,
          deduct_mdr: rule.deduct_mdr,
          deduct_lab: rule.deduct_lab,
          procedure_name: rule.procedure_name,
          specialty: rule.specialty,
          valid_from: rule.valid_from.iso8601,
          captured_at: Time.current.iso8601
        }

        # MDR snapshot: já está congelado no installment (Fase 1B)
        mdr = rule.deduct_mdr ? @installment.fee_amount_cents.to_i : 0
        lab = 0  # placeholder — Lab por procedimento em Fase 4
        calc_base = @applied_cents - mdr - lab

        commission_cents =
          if rule.kind == 'valor_fixo'
            @installment.fully_paid? ? rule.fixed_amount_cents.to_i : 0
          else
            ((calc_base * rule.percent_basis_points.to_i) / 10_000.0).round
          end

        ::Financial::CommissionEntry.new(
          account_id: @account.id,
          financial_installment_id: @installment.id,
          financial_budget_id: @installment.financial_budget_id,
          professional_id: @installment.professional_id,
          financial_commission_rule_id: rule.id,
          rule_snapshot: snapshot,
          base_amount_cents: @applied_cents,
          mdr_deduction_cents: mdr,
          lab_deduction_cents: lab,
          calc_base_cents: calc_base,
          commission_amount_cents: commission_cents,
          percent_basis_points: rule.percent_basis_points,
          status: 'devida',
          competence_date: @installment.received_at || Date.current,
          triggered_at: Time.current
        )
      end
    end
  end
end
