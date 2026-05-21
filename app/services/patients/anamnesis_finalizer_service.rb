# app/services/patients/anamnesis_finalizer.rb
#
# Responsabilidade: Finalizar uma anamnese e gerar CriticalAlerts
# automáticos baseados em alergias severas e condições marcadas.
#
# Uso:
#   result = Patients::AnamnesisFinalizerService.call(anamnesis: @anamnesis, actor: current_user)
#   result.success? # => true
#   result.critical_alerts_created # => [CriticalAlert, ...]

module Patients
  class AnamnesisFinalizerService
    Result = Struct.new(:success, :anamnesis, :critical_alerts_created, :error, keyword_init: true) do
      def success? = success
    end

    def self.call(anamnesis:, actor:)
      new(anamnesis: anamnesis, actor: actor).call
    end

    def initialize(anamnesis:, actor:)
      @anamnesis = anamnesis
      @actor     = actor
      @alerts    = []
    end

    def call
      return error_result('Anamnese já finalizada.') if @anamnesis.status_finalized?

      ActiveRecord::Base.transaction do
        # 1. Gerar e anexar o PDF da anamnese ANTES de finalizar (evita bloqueio no 'prevent_edit_if_finalized')
        Patients::AnamnesisPdfGenerator.call(anamnesis: @anamnesis, actor: @actor)

        # 2. Finaliza a anamnese
        @anamnesis.finalize!(actor: @actor)

        # 3. Extrai e cria alertas críticos
        extract_allergy_alerts
        extract_contraindication_alerts
        extract_medication_alerts

        # 4. Dispara job assíncrono para processamento pesado (ex: integrações futuras)
        Patients::AnamnesisAlertExtractorJob.perform_later(@anamnesis.id)

        Result.new(
          success: true,
          anamnesis: @anamnesis,
          critical_alerts_created: @alerts
        )
      end
    rescue StandardError => e
      Result.new(success: false, anamnesis: @anamnesis, critical_alerts_created: [], error: e.message)
    end

    private

    # ---------- Extratores ----------

    def extract_allergy_alerts
      Array(@anamnesis.allergies).each do |allergy|
        next unless allergy.is_a?(Hash)
        next unless %w[high medium].include?(allergy['severity'].to_s)

        create_alert(
          alert_type: 'allergy',
          severity: allergy['severity'].to_s == 'high' ? 'high' : 'medium',
          title: "Alergia: #{allergy['substance'] || allergy['name']}",
          description: allergy['reaction'] || allergy['description']
        )
      end
    end

    def extract_contraindication_alerts
      Array(@anamnesis.contraindications).each do |contra|
        next if contra.blank?

        text = contra.is_a?(Hash) ? contra['name'] || contra['description'] : contra.to_s
        next if text.blank?

        create_alert(
          alert_type: 'contraindication',
          severity: 'high',
          title: "Contraindicação: #{text}",
          description: contra.is_a?(Hash) ? contra['details'] : nil
        )
      end
    end

    def extract_medication_alerts
      Array(@anamnesis.current_medications).each do |med|
        next unless med.is_a?(Hash)
        next unless med['alert'].present? || med['interaction_risk'].present?

        create_alert(
          alert_type: 'medication',
          severity: 'medium',
          title: "Medicamento de atenção: #{med['name']}",
          description: med['alert'] || med['interaction_risk']
        )
      end
    end

    # ---------- Criação do alerta com deduplicação ----------

    def create_alert(alert_type:, severity:, title:, description:)
      # Evita duplicar alertas idênticos já existentes e ativos
      existing = @anamnesis.patient.critical_alerts.active.find_by(
        alert_type: CriticalAlert.alert_types[alert_type],
        title: title
      )
      return if existing

      alert = CriticalAlert.create!(
        account: @anamnesis.account,
        patient: @anamnesis.patient,
        created_by: @actor,
        alert_type: alert_type,
        severity: severity,
        title: title,
        description: description,
        active: true
      )
      @alerts << alert

      PatientAuditLog.log!(
        account: @anamnesis.account,
        patient: @anamnesis.patient,
        actor: @actor,
        action: 'create',
        resource: alert,
        changes: { auto_generated_from: 'anamnesis_finalizer' }
      )
    end

    def error_result(msg)
      Result.new(success: false, anamnesis: @anamnesis, critical_alerts_created: [], error: msg)
    end
  end
end
