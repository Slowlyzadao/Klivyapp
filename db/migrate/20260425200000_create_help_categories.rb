class CreateHelpCategories < ActiveRecord::Migration[7.0]
  def up
    create_table :help_categories do |t|
      t.string  :name,        null: false
      t.string  :description
      t.string  :slug,        null: false
      t.text    :icon_svg
      t.string  :icon_class
      t.integer :position,    default: 0, null: false
      t.boolean :hidden,      default: false, null: false
      t.timestamps
    end

    add_index :help_categories, :slug, unique: true

    now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
    defaults = [
      { slug: 'conversas',     name: 'Conversas',     description: 'Caixa de entrada, atribuições, respostas prontas e fluxos de mensagem.', icon_class: 'i-lucide-message-circle', position: 1,  hidden: false },
      { slug: 'agenda',        name: 'Agenda',        description: 'Agendamentos, lembretes, integração com calendários e disponibilidade.', icon_class: 'i-lucide-calendar',        position: 2,  hidden: false },
      { slug: 'pacientes',     name: 'Pacientes',     description: 'Cadastros, prontuários, histórico de atendimento e dados clínicos.',     icon_class: 'i-lucide-users',           position: 3,  hidden: false },
      { slug: 'financeiro',    name: 'Financeiro',    description: 'Cobranças, recebimentos, planos, faturas e relatórios financeiros.',     icon_class: 'i-lucide-wallet',          position: 4,  hidden: false },
      { slug: 'bea',           name: 'BEA',           description: 'Beatriz AI: assistente que automatiza atendimentos e classifica conversas.', icon_class: 'i-lucide-sparkles',   position: 5,  hidden: false },
      { slug: 'configuracoes', name: 'Configurações', description: 'Conta, times, canais, integrações, segurança e personalização do espaço.', icon_class: 'i-lucide-bolt',        position: 6,  hidden: false },
      { slug: 'outro',         name: 'Outros',        description: 'Artigos diversos e tópicos que não se encaixam nas categorias acima.',   icon_class: 'i-lucide-folder-open',     position: 99, hidden: true  },
    ]

    defaults.each do |cat|
      execute(
        "INSERT INTO help_categories (name, description, slug, icon_class, position, hidden, created_at, updated_at) " \
        "VALUES (#{connection.quote(cat[:name])}, #{connection.quote(cat[:description])}, #{connection.quote(cat[:slug])}, " \
        "#{connection.quote(cat[:icon_class])}, #{cat[:position]}, #{cat[:hidden] ? 'TRUE' : 'FALSE'}, " \
        "#{connection.quote(now)}, #{connection.quote(now)})"
      )
    end
  end

  def down
    drop_table :help_categories
  end
end
