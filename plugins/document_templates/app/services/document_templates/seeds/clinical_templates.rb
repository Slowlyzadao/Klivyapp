# frozen_string_literal: true

module DocumentTemplates
  module Seeds
    # Definições dos templates Klivy clínicos (10 modelos). Cada método
    # retorna `{ name:, document_type:, content_json: }` pra ser consumido
    # pelo LibrarySeeder.
    #
    # Variáveis usadas devem existir em `DocumentTemplates::Catalog` (ver
    # variables/*_definitions.rb). Quando o profissional gerar o documento,
    # o Resolver substitui pelos valores reais do paciente/clínica/profissional.
    module ClinicalTemplates
      extend Builder

      module_function

      def all
        [
          atestado_medico,
          receita_medica,
          pedido_exame,
          declaracao_comparecimento,
          relatorio_clinico,
          encaminhamento_medico,
          contrato_estetico,
          orcamento_padrao,
          instrucao_pos_procedimento,
          questionario_admissao
        ]
      end

      def atestado_medico
        {
          name: 'Atestado Médico Padrão',
          document_type: 'atestado',
          content_json: doc(
            heading(1, 'ATESTADO MÉDICO', align: 'center'),
            paragraph(
              'Atesto, para os devidos fins, que o(a) Sr(a). ',
              variable('patient.full_name'),
              ', portador(a) do CPF ',
              variable('patient.cpf'),
              ', esteve sob meus cuidados profissionais na presente data, ',
              'necessitando de afastamento de suas atividades habituais.',
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            paragraph(''),
            *signature_block('professional.name', 'Profissional Responsável'),
            paragraph(variable('professional.council_full'), align: 'center')
          )
        }
      end

      def receita_medica
        {
          name: 'Receita Médica Padrão',
          document_type: 'receita',
          content_json: doc(
            heading(1, 'RECEITUÁRIO MÉDICO', align: 'center'),
            paragraph(
              bold('Paciente: '),
              variable('patient.full_name'),
              hard_break,
              bold('CPF: '),
              variable('patient.cpf'),
              hard_break,
              bold('Data de Nascimento: '),
              variable('patient.birthdate')
            ),
            paragraph(''),
            heading(2, 'Prescrição'),
            paragraph('Substitua este parágrafo pela posologia detalhada (medicamento, dose, frequência e duração).'),
            paragraph(''),
            heading(3, 'Orientações'),
            paragraph('Use este espaço para orientações ao paciente — administração, alimentação, retorno.'),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            *signature_block('professional.name', 'Profissional Prescritor'),
            paragraph(variable('professional.council_full'), align: 'center')
          )
        }
      end

      def pedido_exame
        {
          name: 'Pedido de Exame Padrão',
          document_type: 'pedido_exame',
          content_json: doc(
            heading(1, 'PEDIDO DE EXAMES', align: 'center'),
            paragraph(
              bold('Paciente: '),
              variable('patient.full_name'),
              hard_break,
              bold('CPF: '),
              variable('patient.cpf'),
              hard_break,
              bold('Idade: '),
              variable('patient.age')
            ),
            paragraph(''),
            heading(2, 'Indicação Clínica'),
            paragraph('Descreva aqui a hipótese diagnóstica e o motivo dos exames solicitados.'),
            paragraph(''),
            heading(2, 'Exames Solicitados'),
            bullet_list(
              'Exame 1 (substitua)',
              'Exame 2 (substitua)',
              'Exame 3 (substitua)'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            *signature_block('professional.name', 'Profissional Solicitante'),
            paragraph(variable('professional.council_full'), align: 'center')
          )
        }
      end

      def declaracao_comparecimento
        {
          name: 'Declaração de Comparecimento',
          document_type: 'declaracao',
          content_json: doc(
            heading(1, 'DECLARAÇÃO DE COMPARECIMENTO', align: 'center'),
            paragraph(
              'Declaro, para os devidos fins, que o(a) Sr(a). ',
              variable('patient.full_name'),
              ', portador(a) do CPF ',
              variable('patient.cpf'),
              ', compareceu a esta clínica em ',
              variable('date.today'),
              ' para atendimento profissional.',
              align: 'justify'
            ),
            paragraph(''),
            paragraph(
              'Esta declaração é emitida para apresentação onde se fizer necessário.',
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            *signature_block('professional.name', 'Profissional Responsável'),
            paragraph(variable('professional.council_full'), align: 'center')
          )
        }
      end

      def relatorio_clinico
        {
          name: 'Relatório Clínico Padrão',
          document_type: 'relatorio_clinico',
          content_json: doc(
            heading(1, 'RELATÓRIO CLÍNICO', align: 'center'),
            paragraph(
              bold('Paciente: '),
              variable('patient.full_name'),
              hard_break,
              bold('CPF: '),
              variable('patient.cpf'),
              hard_break,
              bold('Data de Nascimento: '),
              variable('patient.birthdate'),
              hard_break,
              bold('Idade: '),
              variable('patient.age')
            ),
            paragraph(''),
            heading(2, 'Histórico Clínico'),
            paragraph('Descreva o histórico clínico relevante, queixa principal, evolução.'),
            paragraph(''),
            heading(2, 'Exame Físico / Avaliação'),
            paragraph('Achados do exame físico, avaliações específicas, sinais e sintomas.'),
            paragraph(''),
            heading(2, 'Hipótese Diagnóstica'),
            paragraph('Hipóteses diagnósticas, diagnósticos firmados (CID quando aplicável).'),
            paragraph(''),
            heading(2, 'Conduta'),
            paragraph('Plano terapêutico, prescrições, orientações, seguimento.'),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            *signature_block('professional.name', 'Profissional Responsável'),
            paragraph(variable('professional.council_full'), align: 'center')
          )
        }
      end

      def encaminhamento_medico
        {
          name: 'Encaminhamento Médico',
          document_type: 'encaminhamento',
          content_json: doc(
            heading(1, 'ENCAMINHAMENTO', align: 'center'),
            paragraph(
              'Encaminho o(a) paciente ',
              variable('patient.full_name'),
              ', portador(a) do CPF ',
              variable('patient.cpf'),
              ', para avaliação especializada.',
              align: 'justify'
            ),
            paragraph(''),
            heading(2, 'Motivo do Encaminhamento'),
            paragraph('Descreva o motivo clínico, hipótese diagnóstica e exames já realizados.'),
            paragraph(''),
            heading(2, 'Solicitação'),
            paragraph(
              'Solicito avaliação, exames complementares e conduta terapêutica conforme ',
              'parecer do colega especialista. Atenciosamente.',
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            *signature_block('professional.name', 'Profissional Solicitante'),
            paragraph(variable('professional.council_full'), align: 'center')
          )
        }
      end

      def contrato_estetico
        {
          name: 'Contrato de Tratamento Estético',
          document_type: 'contrato',
          content_json: doc(
            heading(1, 'CONTRATO DE PRESTAÇÃO DE SERVIÇOS', align: 'center'),
            heading(3, 'Tratamento Estético', align: 'center'),
            paragraph(''),
            paragraph(
              bold('CONTRATANTE: '),
              variable('patient.full_name'),
              ', portador(a) do CPF ',
              variable('patient.cpf'),
              ', residente em ',
              variable('patient.address_full'),
              '.',
              align: 'justify'
            ),
            paragraph(
              bold('CONTRATADA: '),
              variable('clinic.name'),
              ', CNPJ ',
              variable('clinic.cnpj'),
              ', com sede em ',
              variable('clinic.address_full'),
              '.',
              align: 'justify'
            ),
            paragraph(''),
            heading(2, 'Cláusula 1ª — Objeto'),
            paragraph(
              'O presente contrato tem por objeto a prestação de serviços estéticos ',
              'definidos no plano de tratamento anexo, incluindo os procedimentos, ',
              'sessões e materiais especificados.',
              align: 'justify'
            ),
            heading(2, 'Cláusula 2ª — Valor e Forma de Pagamento'),
            paragraph(
              'O valor total e as condições de pagamento foram previamente acordados ',
              'entre as partes e estão registrados no orçamento que acompanha este contrato.',
              align: 'justify'
            ),
            heading(2, 'Cláusula 3ª — Riscos e Contraindicações'),
            paragraph(
              'O(a) contratante declara ter sido informado(a) sobre a natureza, os ',
              'benefícios, os riscos, os efeitos adversos possíveis e as alternativas ',
              'aos procedimentos contratados.',
              align: 'justify'
            ),
            heading(2, 'Cláusula 4ª — Foro'),
            paragraph(
              'Fica eleito o foro da comarca de ',
              variable('clinic.address_city'),
              ' para dirimir quaisquer dúvidas decorrentes deste contrato.',
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            paragraph(''),
            paragraph(text('_______________________________'), align: 'center'),
            paragraph(variable('patient.full_name'), align: 'center'),
            paragraph(italic('Contratante'), align: 'center'),
            paragraph(''),
            paragraph(text('_______________________________'), align: 'center'),
            paragraph(variable('clinic.name'), align: 'center'),
            paragraph(italic('Contratada'), align: 'center')
          )
        }
      end

      def orcamento_padrao
        {
          name: 'Orçamento Padrão',
          document_type: 'orcamento',
          content_json: doc(
            heading(1, 'ORÇAMENTO', align: 'center'),
            paragraph(
              bold('Paciente: '),
              variable('patient.full_name'),
              hard_break,
              bold('CPF: '),
              variable('patient.cpf'),
              hard_break,
              bold('Data: '),
              variable('date.today')
            ),
            paragraph(''),
            heading(2, 'Procedimentos / Serviços'),
            paragraph(
              'Liste aqui os procedimentos com descrição, quantidade de sessões e valor ',
              'individual. (Substitua este texto pelos itens reais — em versões futuras ',
              'esses dados podem vir automaticamente do plano de tratamento.)'
            ),
            paragraph(''),
            heading(2, 'Valor Total'),
            paragraph(bold('R$ _______')),
            paragraph(''),
            heading(2, 'Condições de Pagamento'),
            paragraph('Descreva forma de pagamento, parcelamento e descontos aplicáveis.'),
            paragraph(''),
            heading(3, 'Validade do Orçamento'),
            paragraph('Este orçamento é válido por 30 dias a partir da data de emissão.'),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            *signature_block('professional.name', 'Profissional Responsável')
          )
        }
      end

      def instrucao_pos_procedimento
        {
          name: 'Instruções Pós-Procedimento (Padrão)',
          document_type: 'instrucao_procedimento',
          content_json: doc(
            heading(1, 'ORIENTAÇÕES PÓS-PROCEDIMENTO', align: 'center'),
            paragraph(
              bold('Paciente: '),
              variable('patient.full_name'),
              hard_break,
              bold('Data do procedimento: '),
              variable('date.today')
            ),
            paragraph(''),
            heading(2, 'Cuidados nas primeiras 24 horas'),
            bullet_list(
              'Evite exposição solar direta na região tratada.',
              'Não toque ou massageie a área tratada.',
              'Mantenha a região higienizada com água e sabão neutro.',
              'Evite atividade física intensa.'
            ),
            paragraph(''),
            heading(2, 'Nos primeiros dias'),
            bullet_list(
              'Use protetor solar (FPS 50+) caso saia de casa.',
              'Hidrate bem a pele com os produtos indicados.',
              'Mantenha alimentação leve e boa hidratação.'
            ),
            paragraph(''),
            heading(2, 'Sinais de alerta — procure a clínica se notar'),
            bullet_list(
              'Dor intensa que não cede com analgésicos comuns.',
              'Vermelhidão excessiva, calor local, ou febre.',
              'Sangramento prolongado.',
              'Qualquer sinal de infecção.'
            ),
            paragraph(''),
            paragraph(
              bold('Contato da clínica: '),
              variable('clinic.phone'),
              ' · ',
              variable('clinic.email')
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            *signature_block('professional.name', 'Profissional Responsável')
          )
        }
      end

      def questionario_admissao
        {
          name: 'Questionário de Admissão',
          document_type: 'questionario',
          content_json: doc(
            heading(1, 'QUESTIONÁRIO DE ADMISSÃO', align: 'center'),
            paragraph(
              bold('Paciente: '),
              variable('patient.full_name'),
              hard_break,
              bold('Data de nascimento: '),
              variable('patient.birthdate'),
              hard_break,
              bold('Data: '),
              variable('date.today')
            ),
            paragraph(''),
            heading(2, '1. Histórico de saúde'),
            paragraph('1.1. Possui alguma doença crônica? Qual?'),
            paragraph('_______________________________________________'),
            paragraph('1.2. Faz uso contínuo de algum medicamento? Qual?'),
            paragraph('_______________________________________________'),
            paragraph('1.3. Possui alergia a medicamentos, anestésicos ou produtos? Qual?'),
            paragraph('_______________________________________________'),
            paragraph(''),
            heading(2, '2. Histórico estético / clínico'),
            paragraph('2.1. Já realizou algum procedimento estético? Qual e quando?'),
            paragraph('_______________________________________________'),
            paragraph('2.2. Já teve reação adversa em algum procedimento?'),
            paragraph('_______________________________________________'),
            paragraph(''),
            heading(2, '3. Hábitos'),
            paragraph('3.1. Fuma? Frequência: ____'),
            paragraph('3.2. Consome bebida alcoólica? Frequência: ____'),
            paragraph('3.3. Pratica atividade física? Qual e com que frequência?'),
            paragraph('_______________________________________________'),
            paragraph(''),
            paragraph(
              italic(
                'Declaro que as informações prestadas neste questionário são verdadeiras ' \
                'e estou ciente de que omissões podem comprometer os resultados do tratamento.'
              ),
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            paragraph(text('_______________________________'), align: 'center'),
            paragraph(variable('patient.full_name'), align: 'center'),
            paragraph(italic('Assinatura do paciente'), align: 'center')
          )
        }
      end
    end
  end
end
