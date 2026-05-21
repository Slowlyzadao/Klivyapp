module Patients
  # Atualiza o status do TreatmentPlan com base nos itens filhos.
  # Lógica:
  #   - Se todos os itens estiverem "concluido" → plano "concluido"
  #   - Se algum item está "em_execucao" ou "concluido" (e há outros não concluídos) → "em_execucao"
  #   - Se nenhuma mudança relevante → mantém status atual
  class TreatmentPlanStatusUpdater
    def initialize(plan)
      @plan = plan
    end

    def call
      return unless @plan.status_aprovado? || @plan.status_em_execucao?

      items = @plan.treatment_items.where(deleted_at: nil)
      return if items.empty?

      if all_concluded?(items)
        @plan.update!(status: 'concluido')
      elsif any_in_progress?(items)
        @plan.update!(status: 'em_execucao') unless @plan.status_em_execucao?
      end
    end

    private

    def all_concluded?(items)
      items.all? { |i| i.status_concluido? || i.status_cancelado? }
    end

    def any_in_progress?(items)
      items.any? { |i| i.status_em_execucao? || i.status_concluido? }
    end
  end
end
