class AddCategoryToInternalChatStickers < ActiveRecord::Migration[7.1]
  def change
    # Categoria das figurinhas padrão (dentista, bem_estar, estetica). NULL para
    # figurinhas criadas pelas clínicas (não são categorizadas).
    add_column :internal_chat_stickers, :category, :string, limit: 40
    add_index  :internal_chat_stickers, [:kind, :category]
  end
end
