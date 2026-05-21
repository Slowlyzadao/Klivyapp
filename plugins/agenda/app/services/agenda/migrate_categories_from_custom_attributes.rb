module Agenda
  # Migra dados antigos de "categoria" guardados em AgendaEvent#custom_attributes
  # para a entidade Agenda::Category.
  #
  # Heurística:
  #   - Lê `custom_attributes['category']` (chave plana) ou qualquer chave
  #     `attr_<id>` cujo AgendaCustomAttribute associado tenha nome
  #     case-insensitive "categoria" — esses são os dois caminhos pelos quais
  #     uma categoria provisória pôde ter sido salva.
  #   - Cria Agenda::Category por nome (idempotente: find_or_create_by) na
  #     account do evento.
  #   - Atualiza event.category_id apontando para a categoria criada.
  #
  # Idempotente: pode rodar múltiplas vezes sem efeito colateral. Não roda
  # automaticamente — chame manualmente:
  #
  #   Agenda::MigrateCategoriesFromCustomAttributes.new(Account.find(<id>)).call
  #   # ou para todas as contas:
  #   Account.find_each { |acc| Agenda::MigrateCategoriesFromCustomAttributes.new(acc).call }
  class MigrateCategoriesFromCustomAttributes
    DEFAULT_COLORS = %w[#3b82f6 #22c55e #f59e0b #ef4444 #a855f7 #ec4899 #14b8a6 #f97316 #6366f1 #64748b].freeze

    def initialize(account)
      @account = account
      @category_attr_ids = lookup_category_attribute_ids
      @cache = {}
      @stats = { events_scanned: 0, categories_created: 0, events_linked: 0 }
    end

    def call
      @account.agenda_events.where(category_id: nil).find_each do |event|
        @stats[:events_scanned] += 1
        name = extract_category_name(event)
        next if name.blank?

        category = find_or_create_category(name)
        event.update_columns(category_id: category.id, updated_at: Time.current)
        @stats[:events_linked] += 1
      end
      @stats
    end

    private

    def lookup_category_attribute_ids
      @account.agenda_custom_attributes
              .where(field_type: 'select')
              .where('LOWER(name) IN (?)', %w[categoria categoria* category])
              .pluck(:id)
    end

    def extract_category_name(event)
      attrs = event.custom_attributes || {}
      direct = attrs['category'] || attrs[:category]
      return direct.to_s.strip if direct.present?

      @category_attr_ids.each do |attr_id|
        val = attrs["attr_#{attr_id}"]
        return val.to_s.strip if val.present?
      end
      nil
    end

    def find_or_create_category(name)
      key = name.downcase
      @cache[key] ||= begin
        existing = @account.agenda_categories.where('LOWER(name) = ?', key).first
        if existing
          existing
        else
          color = DEFAULT_COLORS[@stats[:categories_created] % DEFAULT_COLORS.size]
          created = @account.agenda_categories.create!(name: name, color: color, active: true)
          @stats[:categories_created] += 1
          created
        end
      end
    end
  end
end
