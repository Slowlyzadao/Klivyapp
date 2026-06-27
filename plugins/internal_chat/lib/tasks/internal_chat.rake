namespace :internal_chat do
  desc 'Importa figurinhas padrão da Klivy a partir de plugins/internal_chat/db/seed_stickers/<categoria>/*'
  task seed_default_stickers: :environment do
    seed_dir = InternalChat::Engine.root.join('db', 'seed_stickers')

    unless seed_dir.directory?
      puts "[stickers] pasta #{seed_dir} não existe — nada a fazer"
      next
    end

    accepted = %w[.webp .png .gif].freeze
    valid_categories = InternalChat::Sticker::CATEGORIES

    seen_keys = Set.new # rastreia "<category>/<basename>" pra GC

    seed_dir.children.select(&:directory?).each do |cat_dir|
      category = cat_dir.basename.to_s.downcase

      unless valid_categories.include?(category)
        puts "[stickers] subpasta '#{category}' não é uma categoria válida — pulando (esperado: #{valid_categories.join(', ')})"
        next
      end

      files = cat_dir.children.select { |f| f.file? && accepted.include?(f.extname.downcase) }
      puts "[stickers] [#{category}] #{files.size} arquivo(s) detectado(s)"

      files.each do |path|
        basename = path.basename.to_s.sub(/\.[^.]+\z/, '')
        key = "#{category}/#{basename}"
        seen_keys << key

        content_type = case path.extname.downcase
                       when '.webp' then 'image/webp'
                       when '.png'  then 'image/png'
                       when '.gif'  then 'image/gif'
                       end
        file_size = path.size

        if file_size > InternalChat::Sticker::MAX_BYTES
          puts "  [skip] #{basename} excede #{InternalChat::Sticker::MAX_BYTES / 1024}KB (#{file_size / 1024}KB)"
          next
        end

        sticker = InternalChat::Sticker.find_or_initialize_by(
          kind: 'default', account_id: nil, category: category,
          name: human_name(basename),
        )

        if sticker.persisted? && sticker.file_size == file_size
          puts "  [keep] #{basename}"
          next
        end

        sticker.kind = 'default'
        sticker.category = category
        sticker.file_size = file_size
        sticker.image.purge if sticker.image.attached?
        sticker.image.attach(io: path.open('rb'), filename: path.basename.to_s, content_type: content_type)
        if sticker.save
          action = sticker.previously_new_record? ? 'created' : 'updated'
          puts "  [#{action}] #{basename}"
        else
          puts "  [error] #{basename}: #{sticker.errors.full_messages.join(', ')}"
        end
      end
    end

    # Garbage collect: remove defaults cuja "categoria/nome" sumiu da pasta.
    InternalChat::Sticker.where(kind: 'default', account_id: nil).find_each do |s|
      key = "#{s.category}/#{s.name.to_s.tr(' ', '_').downcase}"
      next if seen_keys.include?(key)

      # Tenta com human_name reverso (com espaços) também.
      alt_key = "#{s.category}/#{s.name.to_s.tr('_-', ' ').squish}"
      next if seen_keys.any? { |k| k == alt_key || human_name(k.split('/').last) == s.name }

      puts "  [delete] #{s.category}/#{s.name || '(sem nome)'} — arquivo removido da pasta"
      s.destroy!
    end

    breakdown = InternalChat::Sticker.where(kind: 'default', account_id: nil).group(:category).count
    puts "[stickers] total por categoria: #{breakdown.inspect}"
  end

  # Converte 'dentista_01' → 'dentista 01'; 'coracao_rosa' → 'coracao rosa'.
  def human_name(basename)
    basename.tr('_-', ' ').squish.presence
  end
end

# ARCH-15 (audit 2026-05-19): a task acima é executada em todo deploy
# via `docker/Dockerfile` (CMD `bundle exec rails db:chatwoot_prepare &&
# bundle exec rails internal_chat:seed_default_stickers && ...`). Sem
# isso, deploys novos sobem com lista vazia até alguém invocar a task
# manualmente (BUG já observado em staging em 2026-05).
#
# A task é idempotente: `find_or_initialize_by(kind: 'default', account_id: nil, ...)`
# + skip se `file_size` bater. Custo típico: ~2s sem mudanças, ~10s com
# arquivos novos. Use `|| true` no final do comando se quiser que falha
# no seed NÃO derrube o deploy (atualmente, falha PARA o boot — comportamento
# desejado pra detectar drift do blob storage cedo).
