class Api::V1::Accounts::InternalChat::StickersController < Api::V1::Accounts::BaseController
  before_action :fetch_sticker, only: [:destroy, :favorite, :unfavorite]
  before_action :authorize_action

  def authorize_action
    target = @sticker || InternalChat::Sticker
    authorize(target, "#{action_name}?".to_sym)
  end

  # GET /internal_chat/stickers?filter=all|mine|recent&category=dentista|bem_estar|estetica
  # Retorna:
  #  - filter=recent: top 10 stickers que o user mais enviou (ordenados por frequência DESC)
  #  - filter=all (default): defaults da Klivy + stickers salvos na coleção do user
  #  - filter=mine: só os que o user criou
  #  - category: filtra por categoria (apenas defaults têm categoria)
  def index
    filter = params[:filter].presence || 'all'
    category = params[:category].presence
    # MT-11: scope explicito por account_id. Antes pluck retornava
    # sticker_ids de TODAS as contas que o user é membro (multi-account
    # user vê favoritos cruzados). Agora só os desta conta.
    favorite_ids = Current.user.internal_chat_sticker_favorites
                              .where(account_id: Current.account.id)
                              .pluck(:sticker_id)

    if filter == 'recent'
      data = recent_stickers_for(Current.user, favorite_ids.to_set)
      return render json: { data: data }
    end

    account_scope = InternalChat::Sticker.where(account_id: Current.account.id, id: favorite_ids)
    default_scope = InternalChat::Sticker.where(account_id: nil, kind: 'default')
    visible_ids = account_scope.pluck(:id) + default_scope.pluck(:id)

    base = InternalChat::Sticker.where(id: visible_ids).recent
    scope =
      case filter
      when 'mine' then base.where(created_by_user_id: Current.user.id)
      else base
      end
    scope = scope.where(category: category) if category && InternalChat::Sticker::CATEGORIES.include?(category)

    render json: {
      data: scope.map { |s| InternalChat::StickerSerializer.new(s, current_user: Current.user, favorite_ids: favorite_ids.to_set).as_json },
    }
  end

  # POST /internal_chat/stickers
  # Espera multipart com `image` (já redimensionado/convertido pelo client).
  # Cria sticker + auto-salva na coleção do criador (favorite implícito).
  def create
    return render json: { error: I18n.t('internal_chat.controllers.stickers.image_missing') }, status: :unprocessable_entity if params[:image].blank?

    sticker = Current.account.internal_chat_stickers.new(
      created_by_user_id: Current.user.id,
      name: params[:name].to_s.strip.presence,
      kind: 'account',
      width: params[:width].presence&.to_i,
      height: params[:height].presence&.to_i,
      file_size: params[:image].size,
    )
    sticker.image.attach(params[:image])
    if sticker.save
      # MT-11: account_id explícito.
      InternalChat::StickerFavorite.create!(
        user_id: Current.user.id,
        sticker_id: sticker.id,
        account_id: Current.account.id
      )
      InternalChat::Telemetry.track('sticker_created',
                                    account_id: Current.account.id,
                                    user_id: Current.user.id,
                                    sticker_id: sticker.id,
                                    file_size: sticker.file_size)
      render json: { data: InternalChat::StickerSerializer.new(sticker, current_user: Current.user, favorite_ids: Set[sticker.id]).as_json },
             status: :created
    else
      render json: { errors: sticker.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    return render json: { error: I18n.t('internal_chat.controllers.stickers.default_cannot_delete') }, status: :forbidden if @sticker.kind == 'default'

    @sticker.destroy!
    head :ok
  end

  # POST /internal_chat/stickers/:id/favorite
  def favorite
    # FE-22 (auditoria 2026-05-18): defaults já são visíveis automaticamente
    # — não há persistência de favorito a fazer. Mas semanticamente o user
    # "favoritou" → retornar `is_favorite: true, default: true` evita UI
    # inconsistente (antes retornava `is_favorite: false`, fazendo o
    # frontend mostrar o botão de "favoritar" de novo). Frontend store
    # também detecta `kind === 'default'` e faz no-op (defesa em
    # profundidade — caso alguém chame a API direto sem store).
    if @sticker.kind == 'default'
      return render json: { data: { sticker_id: @sticker.id, is_favorite: true, default: true } }
    end

    # MT-11: account_id explícito — mesmo user pode favoritar mesmo default
    # em N contas, então a unicidade é por (user, account, sticker).
    InternalChat::StickerFavorite.find_or_create_by!(
      user_id: Current.user.id,
      sticker_id: @sticker.id,
      account_id: Current.account.id
    )
    render json: { data: { sticker_id: @sticker.id, is_favorite: true } }
  end

  # DELETE /internal_chat/stickers/:id/favorite
  # Remove o sticker da coleção do user. Se ninguém mais tiver ele salvo,
  # apaga fisicamente do banco. Defaults da Klivy não podem ser removidos.
  def unfavorite
    if @sticker.kind == 'default'
      return render json: { error: I18n.t('internal_chat.controllers.stickers.default_cannot_remove') }, status: :forbidden
    end

    deleted = false
    sticker_id = @sticker.id

    InternalChat::Sticker.transaction do
      # Lock pra serializar com outros unfavorites concorrentes (evita
      # 2 users desfavoritando ao mesmo tempo lerem 1 favorito stale).
      locked = InternalChat::Sticker.lock.find_by(id: sticker_id)
      next unless locked

      # MT-11: scoped por account_id — unfavorite só do registro desta
      # conta. Outras contas (multi-account user) mantêm o favorito.
      InternalChat::StickerFavorite.where(
        user_id: Current.user.id,
        sticker_id: sticker_id,
        account_id: Current.account.id
      ).destroy_all

      # Cascade-delete do sticker custom continua global — se ninguém em
      # NENHUMA conta favorita mais, apaga o blob físico. Defaults nunca
      # caem aqui (kind='default' já é rejeitado no return acima).
      if InternalChat::StickerFavorite.where(sticker_id: sticker_id).none?
        locked.destroy!
        deleted = true
      end
    end

    InternalChat::Telemetry.track('sticker_unfavorited',
                                  account_id: Current.account.id,
                                  user_id: Current.user.id,
                                  sticker_id: sticker_id,
                                  cascade_deleted: deleted)
    render json: { data: { sticker_id: sticker_id, is_favorite: false, deleted: deleted } }
  end

  private

  # Top 10 stickers que o user mais enviou. Agrupa Messages.sticker_id por
  # contagem DESC. Stickers cuja referência foi cascade-deletada (sticker_id
  # virou NULL) são automaticamente excluídos via `where.not(sticker_id: nil)`.
  #
  # PERF-3 (auditoria 2026-05-18): ordenação + limit no SQL em vez de
  # `sort_by/first(10)` em Ruby. User com 5000 sticker usages fazia full
  # sort em memória; agora PG ordena com index parcial e retorna só 10
  # linhas. Hash preserva ordem de inserção (Ruby 2.0+), então `counts.keys`
  # já vem ordenado.
  def recent_stickers_for(user, favorite_ids)
    counts = InternalChat::Message
             .joins(:room)
             .where(sender_user_id: user.id)
             .where(internal_chat_rooms: { account_id: Current.account.id })
             .where.not(sticker_id: nil)
             .group(:sticker_id)
             .order(Arel.sql('COUNT(*) DESC'))
             .limit(10)
             .count
    return [] if counts.empty?

    sorted_ids = counts.keys
    found = InternalChat::Sticker.where(id: sorted_ids).index_by(&:id)
    sorted_ids.map { |id| found[id] }.compact.map do |s|
      InternalChat::StickerSerializer.new(s, current_user: user, favorite_ids: favorite_ids).as_json
    end
  end

  def fetch_sticker
    # Aceita tanto stickers da conta quanto defaults globais (account_id NULL).
    @sticker = InternalChat::Sticker
               .where(account_id: [Current.account.id, nil])
               .find(params[:id])
  end
end
