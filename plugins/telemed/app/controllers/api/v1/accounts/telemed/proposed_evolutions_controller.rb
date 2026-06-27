# CRUD da proposta de evolução clínica gerada pela IA.
#
# Endpoints:
#   PATCH /:id           — edita SOAP/markdown antes de aprovar
#   POST  /:id/approve   — aprova → cria ClinicalNote(source='telemed_ai')
#   POST  /:id/reject    — descarta (reviewer_notes obrigatório)
#
# Autorização: apenas o profissional responsável pelo evento pode
# revisar/aprovar — `record.telemed_recording.agenda_event.user_id ==
# current_user.id`. Admin com beclinic_scope='all' também passa.
class Api::V1::Accounts::Telemed::ProposedEvolutionsController < Api::V1::Accounts::BaseController
  before_action :load_proposed_evolution

  # PATCH /api/v1/accounts/:account_id/telemed/proposed_evolutions/:id
  def update
    authorize @proposed_evolution, :update?

    @proposed_evolution.apply_edit!(
      soap_structure:   soap_structure_params,
      raw_markdown:     params[:raw_markdown],
      procedure_fields: procedure_fields_params,
      actor:            Current.user
    )

    render json: { data: serialize(@proposed_evolution) }
  rescue ActiveRecord::RecordInvalid, RuntimeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/accounts/:account_id/telemed/proposed_evolutions/:id/approve
  def approve
    authorize @proposed_evolution, :approve?

    note = @proposed_evolution.approve!(actor: Current.user)
    render json: {
      data: serialize(@proposed_evolution.reload),
      clinical_note: { id: note.id, status: note.status }
    }
  rescue ActiveRecord::RecordInvalid, RuntimeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/accounts/:account_id/telemed/proposed_evolutions/:id/reject
  def reject
    authorize @proposed_evolution, :approve?

    @proposed_evolution.reject!(actor: Current.user, reason: params[:reason].to_s)
    render json: { data: serialize(@proposed_evolution) }
  rescue ActiveRecord::RecordInvalid, RuntimeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Whitelist explícita das chaves SOAP. Antes usava `permit!` que aceitava
  # qualquer chave nested — vetor de mass assignment. As 4 chaves abaixo são
  # as únicas que ProposedEvolution#build_clinical_note_for consome.
  SOAP_PERMITTED_KEYS = %i[subjetivo objetivo avaliacao plano].freeze

  def soap_structure_params
    return nil if params[:soap_structure].blank?

    params.require(:soap_structure).permit(*SOAP_PERMITTED_KEYS).to_h
  end

  # Audit 2026-05-26 — Registro de Procedimento (14 chaves fixas). Mesmo
  # padrão de whitelist do SOAP: bloqueia mass assignment via JSONB. Aceita
  # strings vazias e nil (retorno_em_dias) como valores válidos.
  PROCEDURE_PERMITTED_KEYS = %i[
    queixa_do_dia avaliacao_clinica procedimento_realizado area_tratada
    produto_utilizado quantidade_dose unidade lote validade
    intercorrencias resultado_imediato detalhes_proxima_consulta
    retorno_em_dias observacao
  ].freeze

  def procedure_fields_params
    return nil if params[:procedure_fields].blank?

    params.require(:procedure_fields).permit(*PROCEDURE_PERMITTED_KEYS).to_h
  end

  def load_proposed_evolution
    # Scope obrigatório por account — garante isolamento mesmo se o ID
    # vazar entre tenants.
    @proposed_evolution = ProposedEvolution
                            .joins(:telemed_recording)
                            .where(telemed_recordings: { account_id: Current.account.id })
                            .find(params[:id])
  end

  def serialize(evolution)
    {
      id:               evolution.id,
      status:           evolution.status,
      provider:         evolution.provider,
      soap_structure:   evolution.soap_structure,
      raw_markdown:     evolution.raw_markdown,
      attention_points: evolution.attention_points,
      procedure_fields: evolution.procedure_fields || {},
      summary:          evolution.summary.to_s,
      reviewed_by:      evolution.reviewed_by&.name,
      reviewed_at:      evolution.reviewed_at,
      clinical_note_id: evolution.clinical_note_id,
      updated_at:       evolution.updated_at
    }
  end
end
