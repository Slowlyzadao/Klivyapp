class CreateHelpFaqs < ActiveRecord::Migration[7.1]
  DEFAULT_FAQS = [
    {
      category: 'configuracoes',
      question: 'Como faço upgrade do meu plano?',
      answer: 'Você pode fazer upgrade do seu plano a qualquer momento, sem precisar falar com o nosso time. Acesse Configurações → Cobrança e clique em Atualizar plano. O valor proporcional é calculado automaticamente, e você só paga a diferença até o próximo ciclo.',
      tags: 'plano, cobrança, trial',
      position: 0
    },
    {
      category: 'bea',
      question: 'Como a Beatriz AI cobra os créditos?',
      answer: 'Cada interação da Beatriz consome créditos com base no tamanho da resposta gerada. Mensagens curtas (até 200 caracteres): 1 crédito. Respostas longas com contexto: 3 a 5 créditos. Resumos de conversa: 8 créditos. Você acompanha o consumo em tempo real no painel da BEA.',
      tags: 'créditos, beatriz, ia',
      position: 1
    },
    {
      category: 'conversas',
      question: 'Posso transferir uma conversa para outro agente sem perder o histórico?',
      answer: 'Sim. Toda conversa carrega seu histórico completo, independente de quantas vezes for transferida ou atribuída para times diferentes. Para transferir, abra a conversa, clique em "Agente atribuído" no painel lateral e selecione o novo responsável.',
      tags: 'atribuição, histórico',
      position: 2
    },
    {
      category: 'agenda',
      question: 'Como evito que dois pacientes marquem o mesmo horário?',
      answer: 'Quando o link público de agendamento está ativo, o sistema bloqueia automaticamente o horário no momento em que alguém confirma. Você pode ajustar o tempo de bloqueio em Agenda → Configurações → Buffer entre consultas.',
      tags: 'agendamento, online',
      position: 3
    },
    {
      category: 'financeiro',
      question: 'Como faço para emitir nota fiscal automaticamente?',
      answer: 'A emissão automática está disponível nos planos Pro e Business. Após conectar o seu emissor (NFE.io, eNotas ou Bling) em Integrações, toda cobrança paga gera a nota automaticamente. Notas avulsas também podem ser emitidas manualmente no menu Financeiro.',
      tags: 'nota fiscal, integração',
      position: 4
    },
    {
      category: 'pacientes',
      question: 'Como meus pacientes podem solicitar exclusão de dados (LGPD)?',
      answer: 'Cada paciente tem direito de solicitar a exclusão dos seus dados a qualquer momento. Atenda ao pedido pelo menu Paciente → Mais opções → Excluir dados pessoais. O sistema mantém apenas os dados clínicos exigidos por lei (CFM) e remove o restante de forma irreversível.',
      tags: 'lgpd, privacidade',
      position: 5
    },
    {
      category: 'configuracoes',
      question: 'Posso usar o sistema em mais de um dispositivo ao mesmo tempo?',
      answer: 'Sim. Sua conta pode estar logada em quantos dispositivos quiser simultaneamente. Notificações chegam em todos eles, e o estado das conversas é sincronizado em tempo real.',
      tags: 'dispositivos, login',
      position: 6
    }
  ].freeze

  def change
    create_table :help_faqs do |t|
      t.string :question, null: false, limit: 500
      t.text :answer, null: false
      t.string :category, null: false
      t.string :tags
      t.integer :position, null: false, default: 0
      t.boolean :hidden, null: false, default: false

      t.timestamps
    end

    add_index :help_faqs, :category
    add_index :help_faqs, :position
    add_index :help_faqs, :hidden

    reversible do |dir|
      dir.up do
        DEFAULT_FAQS.each do |attrs|
          execute(<<~SQL.squish)
            INSERT INTO help_faqs
              (question, answer, category, tags, position, hidden, created_at, updated_at)
            VALUES
              (#{quote_value(attrs[:question])},
               #{quote_value(attrs[:answer])},
               #{quote_value(attrs[:category])},
               #{quote_value(attrs[:tags])},
               #{attrs[:position]},
               false,
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
