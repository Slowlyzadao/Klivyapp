# Encapsula "quem está agindo em nome de quem" (Sprint I, PRD §13.2).
#
# Recebe um PatientPortalSession e expõe:
#   - acting_patient   : quem logou (responsável OU paciente single-self)
#   - active_patient   : quem está sendo acessado (self OU dependente)
#   - accessible_patients : lista do que o acting pode acessar (self + dependentes ativos)
#   - can_act_on?(target) : valida se uma troca para `target` é permitida
#
# Toda a lógica de "pode acessar quem?" mora aqui — controllers só consomem.
module PatientPortal
  class SessionContext
    Result = Struct.new(:acting_patient, :active_patient, :accessible_patients, keyword_init: true) do
      def acting_on_dependent?
        active_patient.id != acting_patient.id
      end

      def to_h
        {
          acting:  serialize(acting_patient),
          active:  serialize(active_patient),
          on_dependent: acting_on_dependent?,
          accessible: accessible_patients.map { |p| serialize(p) }
        }
      end

      private

      def serialize(p)
        return nil unless p

        { id: p.id, name: p.name, email: p.email, is_self: p.id == acting_patient.id }
      end
    end

    def initialize(session:)
      @session = session
      @account = session.account
    end

    def resolve
      acting = @session.patient
      active = @session.active_patient || acting

      Result.new(
        acting_patient:      acting,
        active_patient:      active,
        accessible_patients: accessible_patients_for(acting)
      )
    end

    # Verifica se o acting pode trocar pra esse target.
    def can_act_on?(target_patient)
      return false if target_patient.blank?
      return true  if target_patient.id == @session.patient_id # self

      PatientResponsibleLink.active
                            .for_responsible(@session.patient)
                            .for_dependent(target_patient)
                            .where(account_id: @account.id)
                            .exists?
    end

    def accessible_patients_for(acting)
      dependents = PatientResponsibleLink.active
                                          .for_responsible(acting)
                                          .where(account_id: @account.id)
                                          .includes(:dependent)
                                          .map(&:dependent)
                                          .compact
      [acting, *dependents].uniq(&:id)
    end
  end
end
