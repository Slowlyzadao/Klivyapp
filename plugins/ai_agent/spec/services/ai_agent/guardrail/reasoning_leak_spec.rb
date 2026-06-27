require 'rails_helper'

RSpec.describe AiAgent::Guardrail::ReasoningLeak do
  describe '.leaked?' do
    # Regressão 2026-06-11: vazamento REAL que chegou no WhatsApp do dono.
    # O padrão de 3ª pessoa era case-sensitive ("como" minúsculo) e o
    # chain-of-thought abre a frase com "Como..." maiúsculo.
    it 'detecta o vazamento real (frase começando com "Como" maiúsculo)' do
      leaked = 'Como o Leandro não possui cadastro anterior, preciso iniciar o processo ' \
               'de agendamento descobrindo para quem é a consulta e qual a queixa ou ' \
               'especialidade desejada, conforme o fluxo obrigatório de agendamento (Para quem + Queixa).'
      expect(described_class.leaked?(leaked)).to be(true)
    end

    it 'detecta narração de plano com nome de tool e found:' do
      leaked = 'Como o Leandro escolheu o horário das 10:00 e não possui cadastro ' \
               '(retornou found: false), preciso solicitar o Nome Completo e o CPF dele.'
      expect(described_class.leaked?(leaked)).to be(true)
    end

    it 'detecta vocabulário interno de fluxo/processo' do
      expect(described_class.leaked?('Preciso seguir o fluxo de cadastro antes de agendar.')).to be(true)
      expect(described_class.leaked?('Conforme as regras, não posso mencionar multa.')).to be(true)
      expect(described_class.leaked?('Vou usar os IDs internos do CONTEXTO ATUAL.')).to be(true)
    end

    # Regressão 2026-06-11: "Como os seus dados ficam totalmente protegidos
    # pela LGPD, você poderia me passar seu nome completo e o seu CPF?"
    it 'detecta jargão jurídico que recepcionista não fala (LGPD/CFM)' do
      expect(described_class.leaked?('Como os seus dados ficam totalmente protegidos pela LGPD, você poderia me passar seu nome completo e o seu CPF, por favor?')).to be(true)
      expect(described_class.leaked?('O CFM não permite que eu interprete exames.')).to be(true)
      expect(described_class.leaked?('Seus dados seguem a proteção de dados vigente.')).to be(true)
    end

    it 'NÃO acusa falas legítimas da Bia (falso positivo)' do
      legitimas = [
        'Boa tarde, Leandro! Vi que você tem 2 consultas marcadas no dia 12/06. Quer falar sobre alguma delas?',
        'Como a gente não tem horário às 17h, que tal às 9h ou 10h com o Dr. Henrique?',
        'Qual das duas consultas você deseja cancelar: a sua dia 12/06 às 10h ou a do Gabriel às 11h?',
        'Prontinho! A consulta do Gabriel foi cancelada. Posso te ajudar em mais alguma coisa?',
        'Vou precisar do seu CPF pra completar seu cadastro; fica tudo guardado com segurança aqui na clínica, tá?',
        'Sua avaliação ficou marcada para sexta-feira, dia 12/06, às 9h, com o Dr. Henrique Carvalho.',
        'A clínica fica na Rua das Acácias, 4575. Como você conheceu a gente?'
      ]
      legitimas.each do |fala|
        expect(described_class.leaked?(fala)).to be(false), "falso positivo: #{fala}"
      end
    end
  end

  describe '.strip' do
    it 'remove só a frase vazada e preserva a pergunta legítima' do
      misto = 'Como o Leandro não possui cadastro anterior, preciso iniciar o processo de agendamento. ' \
              'Essa avaliação é pra você mesmo ou pra outra pessoa?'
      expect(described_class.strip(misto)).to eq('Essa avaliação é pra você mesmo ou pra outra pessoa?')
    end
  end
end
