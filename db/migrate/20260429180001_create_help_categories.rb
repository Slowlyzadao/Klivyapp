class CreateHelpCategories < ActiveRecord::Migration[7.1]
  DEFAULT_CATEGORIES = [
    {
      slug: 'conversas',
      name: 'Conversas',
      description: 'Caixa de entrada, atribuições, respostas prontas e fluxos de mensagem.',
      icon_class: 'i-lucide-message-circle',
      position: 0
    },
    {
      slug: 'agenda',
      name: 'Agenda',
      description: 'Agendamentos, lembretes, integração com calendários e disponibilidade.',
      icon_class: 'i-lucide-calendar',
      position: 1
    },
    {
      slug: 'pacientes',
      name: 'Pacientes',
      description: 'Cadastros, prontuários, histórico de atendimento e dados clínicos.',
      icon_class: 'i-lucide-users',
      position: 2
    },
    {
      slug: 'financeiro',
      name: 'Financeiro',
      description: 'Cobranças, recebimentos, planos, faturas e relatórios financeiros.',
      icon_class: 'i-lucide-wallet',
      position: 3
    },
    {
      slug: 'bea',
      name: 'BEA',
      description: 'Beatriz AI: assistente que automatiza atendimentos e classifica conversas.',
      icon_class: 'i-lucide-sparkles',
      position: 4
    },
    {
      slug: 'configuracoes',
      name: 'Configurações',
      description: 'Conta, times, canais, integrações, segurança e personalização do espaço.',
      icon_class: 'i-lucide-bolt',
      position: 5
    },
    {
      slug: 'outro',
      name: 'Outros',
      description: 'Artigos diversos e tópicos que não se encaixam nas categorias acima.',
      icon_class: 'i-lucide-folder-open',
      position: 99,
      hidden: true
    }
  ].freeze

  def change
    create_table :help_categories do |t|
      t.string :name, null: false
      t.string :description
      t.string :slug, null: false
      t.text :icon_svg
      t.string :icon_class
      t.integer :position, null: false, default: 0
      t.boolean :hidden, null: false, default: false

      t.timestamps
    end

    add_index :help_categories, :slug, unique: true
    add_index :help_categories, :position

    reversible do |dir|
      dir.up do
        DEFAULT_CATEGORIES.each do |attrs|
          execute(<<~SQL.squish)
            INSERT INTO help_categories
              (name, description, slug, icon_class, position, hidden, created_at, updated_at)
            VALUES
              (#{quote_value(attrs[:name])},
               #{quote_value(attrs[:description])},
               #{quote_value(attrs[:slug])},
               #{quote_value(attrs[:icon_class])},
               #{attrs[:position]},
               #{attrs[:hidden] ? true : false},
               NOW(), NOW())
          SQL
        end
      end
    end
  end

  def quote_value(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
