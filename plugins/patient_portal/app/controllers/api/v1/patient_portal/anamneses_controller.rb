# Anamneses do paciente — read-only no MVP (PRD §8.3). Opt-in via setting
# `clinical.expose_anamnesis_to_patient` (default false).
#
# Quando o setting é false, o endpoint retorna `exposed: false` em vez de 403
# — isso permite ao front mostrar a mensagem "sua clínica não habilitou esta
# visualização" sem precisar interpretar erros.
class Api::V1::PatientPortal::AnamnesesController < Api::V1::PatientPortal::BaseController
  before_action :load_anamnesis, only: [:show]

  def index
    vis = PatientPortal::AnamnesisVisibility.new(patient: current_patient, account: current_account)
    render json: {
      data: {
        exposed: vis.exposed?,
        has_any: vis.has_any?,
        items:   vis.exposed? ? vis.all.map { |a| serialize(a) } : []
      }
    }
  end

  def show
    render json: { data: serialize(@anamnesis, detailed: true) }
  end

  private

  def load_anamnesis
    vis = PatientPortal::AnamnesisVisibility.new(patient: current_patient, account: current_account)
    @anamnesis = vis.find(params[:id])
  end

  def serialize(a, detailed: false)
    base = {
      id:             a.id,
      version_number: a.version_number,
      specialty:      a.specialty,
      status:         a.status,
      finalized_at:   a.finalized_at,
      created_at:     a.created_at,
      professional:   a.professional ? { id: a.professional.id, name: a.professional.name } : nil
    }
    return base unless detailed

    base.merge(
      chief_complaint:     a.chief_complaint,
      medical_history:     a.medical_history,
      allergies:           a.allergies,
      current_medications: a.current_medications,
      surgical_history:    a.surgical_history,
      family_history:      a.family_history,
      pregnancy:           a.pregnancy,
      relevant_habits:     a.relevant_habits,
      contraindications:   a.contraindications,
      additional_notes:    a.additional_notes
    )
  end
end
