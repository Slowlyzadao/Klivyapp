# Calcula nível de restrição do paciente no portal por inadimplência
# (Sprint H, PRD §9.3 — "Bloqueio progressivo").
#
# Níveis (do menos restritivo pro mais):
#   :none              → sem restrição
#   :warn              → banner amarelo, todas as ações liberadas
#   :limit_scheduling  → bloqueia solicitar agendamento/reagendamento
#   :limit_messaging   → mensageria fica restrita ao canal `financial`
#   :full_block        → tudo bloqueado, exceto pagamento online
#
# A clínica decide o nível-alvo (`overdue_restriction_level`) e a janela
# (`block_portal_if_overdue_days`):
#   - Antes da janela: nível = :warn (paciente avisado, sem bloqueio)
#   - Depois da janela: nível = `overdue_restriction_level`
#
# Service idempotente, leitura pura. Pode ser chamado em qualquer ponto
# (controllers, home aggregation, etc) sem efeito colateral.
module PatientPortal
  class OverdueRestrictionChecker
    LEVELS = %i[none warn limit_scheduling limit_messaging full_block].freeze
    HIERARCHY = { none: 0, warn: 1, limit_scheduling: 2, limit_messaging: 3, full_block: 4 }.freeze

    Result = Struct.new(:level, :days_overdue, :overdue_count, :overdue_total_cents, :setting_level, :threshold_days, keyword_init: true) do
      def restricted?         = HIERARCHY[level].to_i >= HIERARCHY[:warn]
      def blocks_scheduling?  = HIERARCHY[level].to_i >= HIERARCHY[:limit_scheduling]
      def blocks_messaging?   = HIERARCHY[level].to_i >= HIERARCHY[:limit_messaging]
      def full_blocked?       = level == :full_block

      def to_h
        {
          level: level, days_overdue: days_overdue,
          overdue_count: overdue_count, overdue_total_cents: overdue_total_cents,
          blocks_scheduling: blocks_scheduling?, blocks_messaging: blocks_messaging?,
          full_blocked: full_blocked?
        }
      end
    end

    def initialize(account:, patient:, now: Time.current)
      @account = account
      @patient = patient
      @now     = now
    end

    def call
      overdue = overdue_installments
      return Result.new(level: :none, days_overdue: 0, overdue_count: 0, overdue_total_cents: 0,
                        setting_level: setting_level, threshold_days: threshold_days) if overdue.empty?

      days  = days_overdue_from(overdue)
      total = overdue.sum(&:remaining_cents)
      level = compute_level(days)

      Result.new(
        level: level, days_overdue: days,
        overdue_count: overdue.size, overdue_total_cents: total,
        setting_level: setting_level, threshold_days: threshold_days
      )
    end

    private

    def overdue_installments
      Financial::Installment.where(account_id: @account.id, patient_id: @patient.id)
                            .where(status: %w[pendente parcial vencido])
                            .where('due_date < ?', @now.to_date)
                            .to_a
    end

    def days_overdue_from(installments)
      oldest = installments.min_by(&:due_date)
      (@now.to_date - oldest.due_date).to_i
    end

    def compute_level(days)
      return :warn if threshold_days <= 0 || days < threshold_days
      return :warn if setting_level == 'warn' # never escalate past warn if configured so

      setting_level.to_sym
    end

    def setting_level
      @setting_level ||= begin
        v = financial_settings['overdue_restriction_level'].to_s.presence || 'warn'
        LEVELS.map(&:to_s).include?(v) ? v : 'warn'
      end
    end

    def threshold_days
      @threshold_days ||= financial_settings['block_portal_if_overdue_days'].to_i
    end

    def financial_settings
      @financial_settings ||= (@account.patient_portal_setting&.financial || {})
    end
  end
end
