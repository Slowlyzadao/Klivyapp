module InternalChat
  class Engine < ::Rails::Engine
    isolate_namespace InternalChat
    engine_name 'internal_chat'

    initializer :append_internal_chat_migrations do |app|
      app.config.paths['db/migrate'] << root.join('db/migrate').to_s
      ActiveRecord::Migrator.migrations_paths << root.join('db/migrate').to_s
    end

    rake_tasks do
      load root.join('lib/tasks/internal_chat.rake').to_s
    end

    config.to_prepare do
      Account.class_eval do
        unless reflect_on_association(:internal_chat_rooms)
          has_many :internal_chat_rooms,
                   class_name: 'InternalChat::Room',
                   dependent: :destroy_async
        end
        unless reflect_on_association(:internal_chat_stickers)
          has_many :internal_chat_stickers,
                   class_name: 'InternalChat::Sticker',
                   dependent: :destroy_async
        end
      end

      User.class_eval do
        unless reflect_on_association(:internal_chat_memberships)
          has_many :internal_chat_memberships,
                   class_name: 'InternalChat::Membership',
                   dependent: :destroy_async
          has_many :internal_chat_rooms,
                   through: :internal_chat_memberships,
                   source: :room
          has_many :internal_chat_messages,
                   class_name: 'InternalChat::Message',
                   foreign_key: :sender_user_id,
                   dependent: :nullify
        end
        unless reflect_on_association(:internal_chat_sticker_favorites)
          has_many :internal_chat_sticker_favorites,
                   class_name: 'InternalChat::StickerFavorite',
                   dependent: :destroy
        end
      end

      # Decisão (Apêndice F): a clínica cria/organiza os grupos do Chat Interno
      # como quiser. Não há sala sistêmica criada automaticamente — usuário
      # adiciona a Beatriz aos grupos relevantes via NewRoomModal (checkbox)
      # ou via GroupSettingsDrawer ("Adicionar Beatriz"). Templates de
      # notificação interna nascem desativados e a clínica configura o destino
      # quando criar os grupos.
    end
  end
end
