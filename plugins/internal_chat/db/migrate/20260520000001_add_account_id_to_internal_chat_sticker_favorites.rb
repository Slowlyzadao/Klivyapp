# MT-11 (auditoria 2026-05-18): StickerFavorite estava sem account_id,
# permitindo que favoritos de um user em uma conta vazassem visualmente
# pra outra conta do mesmo user (multi-account user). Adiciona a coluna,
# faz backfill em 2 passes (sticker custom → sticker.account_id; defaults
# → primeira account_user do user) e migra a unique constraint pra incluir
# account_id (mesmo user pode favoritar mesmo default em N contas).
class AddAccountIdToInternalChatStickerFavorites < ActiveRecord::Migration[7.1]
  def up
    # 1) Coluna nullable + index pra performance dos backfills e queries futuras.
    add_reference :internal_chat_sticker_favorites,
                  :account,
                  null: true,
                  foreign_key: { on_delete: :cascade },
                  index: true

    # 2) Backfill stickers custom — pega a account direto do sticker.
    execute <<~SQL.squish
      UPDATE internal_chat_sticker_favorites sf
      SET account_id = s.account_id
      FROM internal_chat_stickers s
      WHERE sf.sticker_id = s.id
        AND s.account_id IS NOT NULL
        AND sf.account_id IS NULL
    SQL

    # 3) Backfill defaults (sticker.account_id NULL) — heurística: usa a
    # primeira account_user do user (account_id mais antigo). Multi-account
    # users perdem favoritos nas outras contas, mas isso só afeta defaults
    # globais — paciente pode re-favoritar facilmente. Decisão pragmática
    # vs alternativa "duplicar registro por account_user" que poluiria
    # muito a tabela.
    execute <<~SQL.squish
      UPDATE internal_chat_sticker_favorites sf
      SET account_id = (
        SELECT au.account_id
        FROM account_users au
        WHERE au.user_id = sf.user_id
        ORDER BY au.id ASC
        LIMIT 1
      )
      WHERE sf.account_id IS NULL
    SQL

    # 4) Limpa órfãos (user sem nenhuma account_user — não pode favoritar
    # legitimamente em qualquer cenário multi-tenant).
    execute <<~SQL.squish
      DELETE FROM internal_chat_sticker_favorites WHERE account_id IS NULL
    SQL

    # 5) NOT NULL após backfill completo.
    change_column_null :internal_chat_sticker_favorites, :account_id, false

    # 6) Migra unique: antes era (user_id, sticker_id) — agora inclui
    # account_id pra suportar mesmo user/mesmo default em N contas.
    remove_index :internal_chat_sticker_favorites, name: 'idx_sticker_fav_uniq'
    add_index :internal_chat_sticker_favorites,
              %i[user_id account_id sticker_id],
              unique: true,
              name: 'idx_sticker_fav_uniq_per_account'
  end

  def down
    remove_index :internal_chat_sticker_favorites, name: 'idx_sticker_fav_uniq_per_account'
    add_index :internal_chat_sticker_favorites,
              %i[user_id sticker_id],
              unique: true,
              name: 'idx_sticker_fav_uniq'
    remove_reference :internal_chat_sticker_favorites, :account, foreign_key: true, index: true
  end
end
