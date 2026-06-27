# Avalia "posso agendar?" combinando 3 sinais (PRD §7.3):
#   1. consent_ok       — paciente tem `portal_terms` aceito? (gate jurídico)
#   2. financial_clear  — paciente sem parcelas vencidas? (configurável via
#                          `scheduling.block_if_overdue`)
#   3. anamnesis_ok     — anamnese finalizada? (configurável via
#                          `scheduling.require_anamnesis_before_scheduling`)
#
# A flag `can_schedule` é o AND de todos os checks ativos. O front decide:
#   - exibe banner de aviso e CTA "Resolver" para cada problema; ou
#   - libera o botão "Solicitar agendamento".
#
# Importante: a regra por si NÃO bloqueia a criação de PortalAppointmentRequest
# no backend (a clínica pode aprovar à mão mesmo com pendência). Isso é uma
# decisão consciente — preflight é UX, segurança real fica nos endpoints.
module PatientPortal
  class PreflightChecker
    Result = Struct.new(:can_schedule, :checks, :overdue_amount_cents, keyword_init: true) do
      def to_h
        { can_schedule: can_schedule, checks: checks, overdue_amount_cents: overdue_amount_cents }
      end
    end

    def initialize(patient:, account:)
      @patient = patient
      @account = account
      @resolver = ConfigResolver.new(account: account)
    end

    def call
      checks = {
        consent:          consent_check,
        financial:        financial_check,
        anamnesis:        anamnesis_check
      }

      all_ok = checks.values.all? { |c| c[:status] == 'ok' || c[:status] == 'skipped' }

      Result.new(
        can_schedule:           all_ok,
        checks:                 checks,
        overdue_amount_cents:   overdue_cents
      )
    end

    private

    def consent_check
      ok = PatientPortalConsent.active
                                .where(account_id: @account.id,
                                       patient_id: @patient.id,
                                       term_type:  'portal_terms')
                                .exists?
      { status: ok ? 'ok' : 'blocked',
        label: 'Termo de uso do portal',
        message: ok ? nil : 'Você precisa aceitar o Termo de Uso para solicitar agendamento.' }
    end

    def financial_check
      block = @resolver.get(:scheduling, :block_if_overdue)
      return { status: 'skipped', label: 'Financeiro', message: nil } unless block

      cents = overdue_cents
      ok    = cents.zero?
      { status: ok ? 'ok' : 'blocked',
        label: 'Financeiro em dia',
        message: ok ? nil : 'Você tem parcelas vencidas. Regularize antes de solicitar novo agendamento.' }
    end

    def anamnesis_check
      required = @resolver.get(:scheduling, :require_anamnesis_before_scheduling)
      return { status: 'skipped', label: 'Anamnese', message: nil } unless required

      has = if defined?(Anamnesis)
              Anamnesis.active
                       .where(account_id: @account.id, patient_id: @patient.id, status: 'finalized')
                       .exists?
            else
              true # plugin desabilitado — não bloqueia
            end

      { status: has ? 'ok' : 'warning',
        label: 'Anamnese',
        message: has ? nil : 'A clínica pedirá para você preencher uma anamnese antes da consulta.' }
    end

    def overdue_cents
      return @overdue_cents if defined?(@overdue_cents)

      @overdue_cents = if defined?(Financial::Installment)
                        Financial::Installment.where(account_id: @account.id, patient_id: @patient.id)
                                              .where('status = ? OR (status = ? AND due_date < ?)',
                                                     'vencido', 'pendente', Date.current)
                                              .sum(:amount_cents)
                      else
                        0
                      end
    rescue StandardError
      0
    end
  end
end
