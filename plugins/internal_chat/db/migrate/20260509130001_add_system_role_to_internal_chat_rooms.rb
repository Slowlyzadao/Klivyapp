class AddSystemRoleToInternalChatRooms < ActiveRecord::Migration[7.1]
  # `system_role` marca salas geridas pelo sistema (não criadas pela equipe).
  # Hoje só existe 'reception': canal automático onde a Bea posta avisos do
  # Pipeline A (notificações templated) e onde toda a equipe é membro por
  # padrão. Index único parcial garante uma sala por papel por conta.
  #
  # O backfill cria a sala "Recepção" pra cada Account existente, adiciona
  # todos os AccountUsers como membros (admin do Chatwoot vira admin da sala)
  # e adiciona a Bea (Captain::Assistant "Beatriz") se já existir. Falhas por
  # conta não bloqueiam outras — log e segue.
  def up
    add_column :internal_chat_rooms, :system_role, :string
    add_index :internal_chat_rooms,
              [:account_id, :system_role],
              unique: true,
              where: 'system_role IS NOT NULL',
              name: 'idx_internal_chat_rooms_system_role'

    backfill_reception_rooms
  end

  def down
    remove_index :internal_chat_rooms, name: 'idx_internal_chat_rooms_system_role'
    remove_column :internal_chat_rooms, :system_role
    # Não removemos as salas — ficam órfãs do papel sistêmico mas preservam
    # histórico. Operador limpa via console se quiser.
  end

  private

  def backfill_reception_rooms
    return unless defined?(::Account)

    ::Account.find_each do |account|
      create_reception_room_for(account)
    rescue StandardError => e
      Rails.logger.warn(
        "[AddSystemRoleToInternalChatRooms] backfill falhou para account #{account.id}: #{e.class}: #{e.message}"
      )
    end
  end

  def create_reception_room_for(account)
    return if InternalChat::Room.exists?(account_id: account.id, system_role: 'reception')

    creator_user_id = ::AccountUser.where(account_id: account.id).order(:id).limit(1).pick(:user_id)

    room = InternalChat::Room.create!(
      account_id: account.id,
      kind: 'group',
      name: 'Recepção',
      description: 'Canal interno automático: avisos da Beatriz e coordenação da recepção.',
      system_role: 'reception',
      created_by_user_id: creator_user_id
    )

    ::AccountUser.where(account_id: account.id).find_each do |au|
      role = au.administrator? ? 'admin' : 'member'
      room.memberships.create!(
        user_id: au.user_id,
        role: role,
        joined_at: Time.current
      )
    end

    return unless defined?(::Captain::Assistant)

    bea = ::Captain::Assistant.find_by(account_id: account.id, name: 'Beatriz')
    return unless bea

    room.memberships.create!(
      ai_agent_id: bea.id,
      role: 'member',
      joined_at: Time.current
    )
  end
end
