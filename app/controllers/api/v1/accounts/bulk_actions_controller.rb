class Api::V1::Accounts::BulkActionsController < Api::V1::Accounts::BaseController
  def create
    case normalized_type
    when 'Conversation'
      enqueue_conversation_job
      head :ok
    when 'Contact'
      check_authorization_for_contact_action
      process_contact_action
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def normalized_type
    params[:type].to_s.camelize
  end

  def enqueue_conversation_job
    ::BulkActionsJob.perform_later(
      account: @current_account,
      user: current_user,
      params: conversation_params
    )
  end

  def process_contact_action
    if delete_contact_action?
      # Exclusão SÍNCRONA (não enfileira). O cascade pesado (conversas,
      # mensagens) já é `dependent: :destroy_async` no Contact, então o destroy
      # do contato em si é rápido, e a seleção é limitada ao tamanho da página
      # (<= 100). Rodar inline elimina a corrida entre o job assíncrono e o
      # refetch imediato do front, que fazia a contagem exibida não bater com a
      # seleção ("selecionou 100, excluiu ~10"). Responde com o total real.
      deleted = Contacts::BulkDeleteService.new(
        account: @current_account,
        contact_ids: contact_ids
      ).perform
      render json: { deleted: deleted }
    else
      enqueue_contact_job
      head :ok
    end
  end

  def enqueue_contact_job
    Contacts::BulkActionJob.perform_later(
      @current_account.id,
      current_user.id,
      contact_params
    )
  end

  def contact_ids
    Array(contact_params[:ids]).compact
  end

  def delete_contact_action?
    params[:action_name] == 'delete'
  end

  def check_authorization_for_contact_action
    authorize(Contact, :destroy?) if delete_contact_action?
  end

  def conversation_params
    # TODO: Align conversation payloads with the `{ action_name, action_attributes }`
    # and then remove this method in favor of a common params method.
    base = params.permit(
      :snoozed_until,
      fields: [:status, :assignee_id, :team_id]
    )
    append_common_bulk_attributes(base)
  end

  def contact_params
    # TODO: remove this method in favor of a common params method.
    # once legacy conversation payloads are migrated.
    append_common_bulk_attributes({})
  end

  def append_common_bulk_attributes(base_params)
    # NOTE: Conversation payloads historically diverged per action. Going forward we
    # want all objects to share a common contract: `{ action_name, action_attributes }`
    common = params.permit(:type, :action_name, ids: [], labels: [add: [], remove: []])
    base_params.merge(common)
  end
end
