# Dedupe das strings em `custom_attributes[attr_<id>]` (criadas pelo
# ClinicorpAgendaImporter) em `Agenda::Category` nativas, com backfill de
# `agenda_events.category_id` baseado no mapeamento canonical.
#
# Contexto:
# O importer cria UM `AgendaCustomAttribute` (dropdown "Categoria") com a
# união de todos os `CategoryDescription` únicos do CSV. Clínicas como a
# Streit usam esse campo de forma livre, gerando dezenas de variantes do
# mesmo conceito (Avaliação, AVALIAÇÃO (CRC), Avaliação Indicação, ...).
#
# Isso funciona pra exibição mas perde:
#   - Cor por categoria (`Agenda::Category.color`)
#   - Filtros nativos do calendário (mostrar/ocultar por categoria)
#   - Relatórios e dashboards que agregam por `category_id`
#   - Performance (FK indexada vs JSONB scan)
#
# Esta task migra. Estratégia:
#   1. Lê YAML `{ categories: [{ name, color, aliases: [...] }, ...] }`
#   2. Cria/encontra `Agenda::Category` pra cada `name` (idempotente)
#   3. Pra cada evento da conta, lê `custom_attributes[attr_<id>]`, casa com
#      `aliases` (case+accent-insensitive), seta `category_id`
#   4. Eventos cujo valor não bate em nenhum alias → permanecem com
#      `category_id: nil` mas o custom_attribute fica preservado (histórico)
#
# Multi-tenant: account_id obrigatório, todas as queries scoped.
# Idempotente: `find_or_create_by(name)` + `update_columns(category_id)`
# (pula callbacks pra não disparar timeline/notificações).
#
# Uso:
#   bundle exec rails 'migration:dedupe_categories[12274,plugins/xls/clinica-streit/agendamentos/categories_mapping.yml]'
#   DRY_RUN=true bundle exec rails 'migration:dedupe_categories[12274,/path/to/mapping.yml]'
#   DROP_ATTR=true bundle exec rails 'migration:dedupe_categories[12274,/path/file.yml]'
#
# DROP_ATTR=true remove o AgendaCustomAttribute "Categoria" e seus valores
# `custom_attributes[attr_<id>]` dos eventos APÓS o backfill ter sucesso.
# Use só depois de validar visualmente que ficou tudo certo.

namespace :migration do
  desc 'Dedupe das categorias do CSV em Agenda::Category nativas + backfill category_id'
  task :dedupe_categories, [:account_id, :mapping_path] => :environment do |_t, args|
    account_id   = args[:account_id].to_i
    mapping_path = args[:mapping_path].to_s
    abort 'Uso: rails "migration:dedupe_categories[<account_id>,<path/to/mapping.yml>]"' if account_id.zero? || mapping_path.blank?
    abort "Arquivo YAML não encontrado: #{mapping_path}" unless File.file?(mapping_path)

    dry_run   = ENV['DRY_RUN'] == 'true'
    drop_attr = ENV['DROP_ATTR'] == 'true'

    account = Account.find(account_id)
    yaml = YAML.safe_load_file(mapping_path)
    categories_yaml = yaml['categories'] || []
    abort "YAML inválido — esperava chave 'categories: [...]'" if categories_yaml.empty?

    puts ''
    puts '=== Migration — Dedupe Agenda Categories ==='
    puts "Conta:        #{account.id} (#{account.name})"
    puts "YAML:         #{mapping_path}"
    puts "Modo:         #{dry_run ? 'DRY-RUN (sem alterações)' : 'APLICANDO'}"
    puts "Drop attr:    #{drop_attr ? 'SIM (removerá custom_attribute pós-backfill)' : 'NÃO (preserva custom_attribute)'}"
    puts ''

    # Encontra o AgendaCustomAttribute "Categoria" criado pelo importer
    cat_attr = AgendaCustomAttribute.where(account_id: account.id)
                                    .where('LOWER(name) = ?', 'categoria').first
    if cat_attr.nil?
      puts '⚠ Nenhum AgendaCustomAttribute "Categoria" encontrado nesta conta.'
      puts '  Nada a migrar — talvez já tenha sido removido ou nunca foi importado.'
      next
    end
    attr_key = "attr_#{cat_attr.id}"
    puts "AgendaCustomAttribute fonte: id=#{cat_attr.id}, key=#{attr_key}"

    # Constrói índice alias_norm → canonical_name
    alias_to_canonical = {}
    categories_yaml.each do |cat|
      canonical = cat['name'].to_s.strip
      next if canonical.empty?
      Array(cat['aliases']).each do |al|
        alias_to_canonical[normalize(al)] = canonical
      end
      # O próprio nome canonical também é um alias implícito
      alias_to_canonical[normalize(canonical)] = canonical
    end
    puts "Mapeamento carregado: #{categories_yaml.size} canonical / #{alias_to_canonical.size} aliases"
    puts ''

    # 1) Cria/encontra cada Agenda::Category canonical
    canonical_to_category_id = {}
    categories_yaml.each do |cat|
      name = cat['name'].to_s.strip
      next if name.empty?
      color = cat['color'].to_s.presence || '#3b82f6'

      if dry_run
        existing = Agenda::Category.where(account_id: account.id).where('LOWER(name) = ?', name.downcase).first
        status = existing ? "existe (id=#{existing.id})" : 'CRIARIA'
        canonical_to_category_id[normalize(name)] = existing&.id || 0
        puts "  [#{status}] #{name.ljust(40)} #{color}"
      else
        record = Agenda::Category.where(account_id: account.id)
                                  .where('LOWER(name) = ?', name.downcase)
                                  .first_or_create!(name: name, color: color)
        canonical_to_category_id[normalize(name)] = record.id
        action = record.previously_new_record? ? 'criada' : 'existe'
        puts "  [#{action}] #{name.ljust(40)} #{color} id=#{record.id}"
      end
    end
    puts ''

    # 2) Backfill agenda_events.category_id
    puts '--- Backfill agenda_events.category_id ---'
    scope = AgendaEvent.where(account_id: account.id)
                       .where("custom_attributes ? :k", k: attr_key)
    total = scope.count
    puts "Eventos com valor em #{attr_key}: #{total}"

    matched = 0
    unmatched = Hash.new(0)
    already_set = 0
    updated = 0

    scope.find_each(batch_size: 1000) do |event|
      raw_value = event.custom_attributes[attr_key].to_s.strip
      next if raw_value.empty?

      canonical = alias_to_canonical[normalize(raw_value)]
      if canonical.nil?
        unmatched[raw_value] += 1
        next
      end

      target_id = canonical_to_category_id[normalize(canonical)]
      matched += 1

      if event.category_id == target_id
        already_set += 1
        next
      end

      unless dry_run
        # update_columns pula callbacks pra não disparar timeline/notification
        event.update_columns(category_id: target_id, updated_at: Time.current)
      end
      updated += 1
    end

    puts "  Match (string → canonical):   #{matched}"
    puts "  Já estavam com category_id:   #{already_set}"
    puts "  #{dry_run ? 'Atualizariam' : 'Atualizados'}:                  #{updated}"
    puts "  Sem match (preservados):      #{unmatched.values.sum}"
    if unmatched.any?
      puts ''
      puts '  Strings que não bateram em nenhum alias (top 20):'
      unmatched.sort_by { |_, c| -c }.first(20).each do |val, count|
        puts "    #{count.to_s.rjust(6)} × #{val}"
      end
      puts '  Pra cobrir essas: adicione no YAML em "aliases:" da categoria correspondente.'
    end
    puts ''

    # 3) DROP_ATTR (opcional)
    if drop_attr
      if dry_run
        puts '[DRY-RUN] CRIARIA: remover AgendaCustomAttribute e limpar attr_xxx dos custom_attributes.'
      else
        puts "Removendo AgendaCustomAttribute id=#{cat_attr.id} e limpando #{attr_key} dos eventos..."
        ActiveRecord::Base.transaction do
          # SQL direto pra performance: remove a chave do JSONB em todos os eventos
          AgendaEvent.where(account_id: account.id)
                     .where("custom_attributes ? :k", k: attr_key)
                     .update_all(["custom_attributes = custom_attributes - ?", attr_key])
          cat_attr.destroy!
        end
        puts '  AgendaCustomAttribute removida e custom_attributes limpos.'
      end
    end

    puts ''
    if dry_run
      puts 'Pra aplicar:'
      puts "  bundle exec rails 'migration:dedupe_categories[#{account.id},#{mapping_path}]'"
    end
    puts ''
  end

  # Match case+accent-insensitive: "AVALIAÇÃO (CRC)" → "avaliacao (crc)"
  def normalize(value)
    value.to_s.strip.downcase.tr('áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc')
  end
end
