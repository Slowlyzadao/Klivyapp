# Arquivar conversa passa a ser POR-USUÁRIO (per-membership), igual ao mute.
# Antes `archived_at` vivia no Room (global) → arquivar uma DM escondia a
# conversa dos DOIS participantes. Agora cada membro arquiva só a própria visão
# (estilo WhatsApp). A coluna `internal_chat_rooms.archived_at` deixa de ser
# usada pelas ações (mantida sem uso por ora; nenhuma migração de dados é
# necessária — módulo novo, sem registros em produção).
class AddArchivedAtToInternalChatMemberships < ActiveRecord::Migration[7.1]
  def change
    add_column :internal_chat_memberships, :archived_at, :datetime
    add_index :internal_chat_memberships, %i[user_id archived_at]
  end
end
