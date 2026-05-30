# frozen_string_literal: true

module DocumentTemplates
  module Seeds
    # Definições dos templates Klivy de consentimento (12 modelos). Cada
    # método retorna `{ name:, document_type:, content_json: }` consumido
    # pelo LibrarySeeder.
    #
    # **Aviso jurídico**: estes templates são padrões de mercado simplificados,
    # NÃO substituem orientação jurídica especializada. Clínicas devem revisar
    # com seu departamento jurídico antes de usar em produção, especialmente
    # cláusulas LGPD, riscos específicos e foro.
    module ConsentTemplates
      extend Builder

      module_function

      def all
        [
          termo_geral,
          termo_lgpd,
          autorizacao_imagem,
          consentimento_toxina_botulinica,
          consentimento_preenchimento_dermico,
          consentimento_laser,
          consentimento_fototerapia_led,
          consentimento_peeling_quimico,
          consentimento_dermoabrasao,
          autorizacao_paciente_menor,
          consentimento_cirurgia_menor,
          consentimento_anestesia_local
        ]
      end

      # ── Termo de consentimento geral ─────────────────────────────────────
      def termo_geral
        {
          name: 'Termo de Consentimento Geral',
          document_type: 'consentimento_geral',
          content_json: doc(
            heading(1, 'TERMO DE CONSENTIMENTO LIVRE E ESCLARECIDO', align: 'center'),
            paragraph(
              'Eu, ',
              variable('patient.full_name'),
              ', portador(a) do CPF ',
              variable('patient.cpf'),
              ', declaro que fui informado(a) de forma clara sobre o procedimento ',
              'a ser realizado, os benefícios esperados, os riscos envolvidos, os ',
              'cuidados pré e pós-procedimento e as alternativas disponíveis.',
              align: 'justify'
            ),
            paragraph(
              'Tive oportunidade de fazer perguntas, todas foram respondidas de forma ',
              'satisfatória, e autorizo o(a) profissional ',
              variable('professional.name'),
              ' (',
              variable('professional.council_full'),
              ') a realizar o procedimento conforme acordado.',
              align: 'justify'
            ),
            paragraph(
              italic('Declaro, ainda, ciência de que os resultados podem variar entre indivíduos.'),
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            patient_signature_block
          )
        }
      end

      # ── Termo LGPD ───────────────────────────────────────────────────────
      def termo_lgpd
        {
          name: 'Termo de Consentimento LGPD',
          document_type: 'consentimento_lgpd',
          content_json: doc(
            heading(1, 'TERMO DE CONSENTIMENTO — LGPD', align: 'center'),
            paragraph(
              'Em conformidade com a Lei nº 13.709/2018 (Lei Geral de Proteção de Dados ',
              'Pessoais — LGPD), eu, ',
              variable('patient.full_name'),
              ', CPF ',
              variable('patient.cpf'),
              ', autorizo a clínica ',
              variable('clinic.name'),
              ' a coletar, armazenar e tratar meus dados pessoais e dados sensíveis de saúde ',
              'para as finalidades descritas a seguir.',
              align: 'justify'
            ),
            paragraph(''),
            heading(2, 'Finalidades do tratamento de dados'),
            bullet_list(
              'Prestação de serviços de saúde e estética solicitados.',
              'Cumprimento de obrigações legais e regulatórias.',
              'Comunicação sobre consultas, retornos e procedimentos.',
              'Emissão de prescrições, atestados, laudos e relatórios.',
              'Faturamento, cobrança e questões fiscais.'
            ),
            heading(2, 'Direitos do titular'),
            paragraph(
              'Tenho ciência dos meus direitos previstos no art. 18 da LGPD, incluindo ',
              'acesso, correção, anonimização, portabilidade, eliminação e revogação ',
              'deste consentimento — esta última podendo ser exercida a qualquer tempo ',
              'mediante solicitação à clínica.',
              align: 'justify'
            ),
            heading(2, 'Compartilhamento'),
            paragraph(
              'Meus dados poderão ser compartilhados com profissionais envolvidos no meu ',
              'atendimento, laboratórios parceiros (quando necessário para exames), ',
              'operadoras de saúde, autoridades competentes (quando exigido por lei) e ',
              'sistemas tecnológicos contratados pela clínica para gestão de dados, sempre ',
              'sob obrigação de confidencialidade.',
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            patient_signature_block
          )
        }
      end

      # ── Autorização de uso de imagem ─────────────────────────────────────
      def autorizacao_imagem
        {
          name: 'Autorização de Uso de Imagem',
          document_type: 'consentimento_imagem',
          content_json: doc(
            heading(1, 'AUTORIZAÇÃO DE USO DE IMAGEM', align: 'center'),
            paragraph(
              'Eu, ',
              variable('patient.full_name'),
              ', CPF ',
              variable('patient.cpf'),
              ', autorizo de forma gratuita e por prazo indeterminado o uso da minha ',
              'imagem (fotos do antes/durante/depois) pela clínica ',
              variable('clinic.name'),
              ' para as finalidades selecionadas abaixo:',
              align: 'justify'
            ),
            paragraph(''),
            bullet_list(
              'Acompanhamento clínico e prontuário (USO INTERNO).',
              'Divulgação em redes sociais e site da clínica (uso público) — desmarque se NÃO autoriza.',
              'Material didático e científico (com identificação ocultada) — desmarque se NÃO autoriza.'
            ),
            paragraph(''),
            paragraph(
              italic(
                'Esta autorização pode ser revogada a qualquer momento mediante solicitação ' \
                'por escrito à clínica.'
              ),
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            patient_signature_block
          )
        }
      end

      # ── Consentimento — Toxina Botulínica ────────────────────────────────
      def consentimento_toxina_botulinica
        procedure_consent(
          name: 'Consentimento — Toxina Botulínica',
          document_type: 'consentimento_toxina',
          procedure_label: 'Aplicação de Toxina Botulínica',
          benefits: [
            'Suavização de rugas dinâmicas (testa, glabela, "pés de galinha").',
            'Efeito perceptível em 3-7 dias, com duração média de 4 a 6 meses.'
          ],
          risks: [
            'Hematomas, edema e sensibilidade no local da aplicação.',
            'Dor de cabeça leve, mais comum nas primeiras 24h.',
            'Pequena assimetria temporária — raramente persistente.',
            'Reações alérgicas (raras).',
            'Ptose palpebral (queda da pálpebra) em casos raros.'
          ],
          contraindications: [
            'Gestação e amamentação.',
            'Doenças neuromusculares (miastenia gravis, ELA).',
            'Hipersensibilidade conhecida à toxina ou seus componentes.',
            'Infecção ativa no local de aplicação.'
          ]
        )
      end

      # ── Consentimento — Preenchimento Dérmico ────────────────────────────
      def consentimento_preenchimento_dermico
        procedure_consent(
          name: 'Consentimento — Preenchimento Dérmico',
          document_type: 'consentimento_preenchimento',
          procedure_label: 'Aplicação de Preenchimento Dérmico (Ácido Hialurônico)',
          benefits: [
            'Restauração de volume facial perdido.',
            'Suavização de sulcos e harmonização de contornos.',
            'Resultados imediatos, com duração de 6 a 18 meses dependendo do produto.'
          ],
          risks: [
            'Hematomas, inchaço e sensibilidade no local.',
            'Assimetrias temporárias que podem precisar de retoque.',
            'Nódulos palpáveis (geralmente transitórios).',
            'Reações inflamatórias tardias (raras).',
            'Comprometimento vascular com risco de necrose ou embolia (raríssimo, ' \
              'mas grave — requer atendimento imediato).'
          ],
          contraindications: [
            'Gestação e amamentação.',
            'Infecção ativa ou processo inflamatório no local.',
            'Distúrbios de coagulação não controlados.',
            'Histórico de reações alérgicas graves a preenchedores.'
          ]
        )
      end

      # ── Consentimento — Laser ────────────────────────────────────────────
      def consentimento_laser
        procedure_consent(
          name: 'Consentimento — Tratamento a Laser',
          document_type: 'consentimento_laser',
          procedure_label: 'Tratamento a Laser',
          benefits: [
            'Melhora de textura, manchas e pequenas lesões cutâneas.',
            'Estímulo de colágeno e renovação celular.'
          ],
          risks: [
            'Vermelhidão, ardor e descamação temporária.',
            'Hiperpigmentação ou hipopigmentação (em alguns casos).',
            'Bolhas, queimaduras superficiais — raras.',
            'Eflorescências de acne ou herpes simples reativada (em predispostos).'
          ],
          contraindications: [
            'Bronzeamento recente (natural ou artificial).',
            'Gestação.',
            'Uso recente de isotretinoína oral (consultar período de pausa).',
            'Lesões ativas no local a tratar.'
          ]
        )
      end

      # ── Consentimento — Fototerapia LED ──────────────────────────────────
      def consentimento_fototerapia_led
        procedure_consent(
          name: 'Consentimento — Fototerapia LED',
          document_type: 'consentimento_fototerapia_led',
          procedure_label: 'Fototerapia com LED',
          benefits: [
            'Estímulo de regeneração celular.',
            'Ação anti-inflamatória e antibacteriana (acne).',
            'Procedimento indolor e sem tempo de recuperação.'
          ],
          risks: [
            'Leve ressecamento da pele.',
            'Sensibilidade ocular caso o protetor não seja utilizado.',
            'Pouquíssimos efeitos adversos relatados.'
          ],
          contraindications: [
            'Uso recente de medicações fotossensibilizantes.',
            'Câncer de pele em atividade na área a ser tratada.',
            'Lúpus eritematoso sistêmico ativo.'
          ]
        )
      end

      # ── Consentimento — Peeling Químico ──────────────────────────────────
      def consentimento_peeling_quimico
        procedure_consent(
          name: 'Consentimento — Peeling Químico',
          document_type: 'consentimento_peeling',
          procedure_label: 'Peeling Químico',
          benefits: [
            'Renovação celular e clareamento de manchas.',
            'Melhora de textura, brilho e uniformidade da pele.'
          ],
          risks: [
            'Vermelhidão e descamação por alguns dias.',
            'Hiperpigmentação pós-inflamatória (especialmente em peles mais pigmentadas).',
            'Sensibilidade aumentada ao sol nos primeiros 30 dias.',
            'Cicatrizes (raras, com peelings profundos).'
          ],
          contraindications: [
            'Gestação.',
            'Lesões herpéticas ativas.',
            'Uso recente de isotretinoína.',
            'Bronzeamento recente.'
          ]
        )
      end

      # ── Consentimento — Dermoabrasão ─────────────────────────────────────
      def consentimento_dermoabrasao
        procedure_consent(
          name: 'Consentimento — Dermoabrasão',
          document_type: 'consentimento_dermoabrasao',
          procedure_label: 'Dermoabrasão',
          benefits: [
            'Melhora de cicatrizes atróficas e marcas de acne.',
            'Atenuação de linhas finas e textura irregular.'
          ],
          risks: [
            'Vermelhidão prolongada.',
            'Alteração de pigmentação (hiper ou hipo).',
            'Infecção secundária se não houver cuidados adequados.',
            'Cicatrizes hipertróficas em pacientes predispostos.'
          ],
          contraindications: [
            'Distúrbios de cicatrização.',
            'Uso recente de isotretinoína.',
            'Lesões ativas no local.',
            'Bronzeamento recente.'
          ]
        )
      end

      # ── Autorização — Paciente Menor ─────────────────────────────────────
      def autorizacao_paciente_menor
        {
          name: 'Autorização — Paciente Menor de Idade',
          document_type: 'consentimento_menor',
          content_json: doc(
            heading(1, 'AUTORIZAÇÃO PARA ATENDIMENTO DE MENOR DE IDADE', align: 'center'),
            paragraph(
              'Eu, ',
              variable('patient.guardian_name'),
              ', portador(a) do CPF ',
              variable('patient.guardian_cpf'),
              ', responsável legal pelo(a) menor ',
              variable('patient.full_name'),
              ' (CPF ',
              variable('patient.cpf'),
              '), autorizo o atendimento profissional e os procedimentos indicados ',
              'pela clínica ',
              variable('clinic.name'),
              ' no(a) referido(a) menor.',
              align: 'justify'
            ),
            paragraph(
              'Declaro estar ciente dos riscos, benefícios e alternativas dos ',
              'procedimentos, e me comprometo a acompanhar o(a) menor durante o ',
              'atendimento e a seguir as orientações pós-procedimento.',
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            paragraph(text('_______________________________'), align: 'center'),
            paragraph(variable('patient.guardian_name'), align: 'center'),
            paragraph(italic('Responsável legal'), align: 'center'),
            paragraph(''),
            paragraph(
              bold('CPF: '),
              variable('patient.guardian_cpf'),
              ' · ',
              bold('RG: '),
              variable('patient.guardian_rg'),
              align: 'center'
            )
          )
        }
      end

      # ── Consentimento — Cirurgia Menor ───────────────────────────────────
      def consentimento_cirurgia_menor
        procedure_consent(
          name: 'Consentimento — Procedimento Cirúrgico (Pequeno Porte)',
          document_type: 'consentimento_cirurgico',
          procedure_label: 'Procedimento Cirúrgico de Pequeno Porte',
          benefits: [
            'Remoção/correção de lesão conforme indicação clínica.',
            'Resultado estético e funcional.'
          ],
          risks: [
            'Dor, edema e hematoma pós-operatório.',
            'Infecção da ferida operatória.',
            'Cicatrizes — qualidade pode variar conforme características da pele.',
            'Sangramento prolongado.',
            'Necessidade de retoque ou revisão cirúrgica.'
          ],
          contraindications: [
            'Distúrbios de coagulação não controlados.',
            'Infecção ativa no local.',
            'Diabetes descompensado.',
            'Uso de anticoagulantes não suspensos conforme orientação.'
          ]
        )
      end

      # ── Consentimento — Anestesia Local ──────────────────────────────────
      def consentimento_anestesia_local
        procedure_consent(
          name: 'Consentimento — Anestesia Local / Tópica',
          document_type: 'consentimento_anestesia',
          procedure_label: 'Uso de Anestésico Local ou Tópico',
          benefits: [
            'Conforto durante o procedimento.',
            'Possibilidade de realizar procedimentos sensíveis sem dor.'
          ],
          risks: [
            'Reações alérgicas (raras).',
            'Hematoma no local da aplicação.',
            'Toxicidade sistêmica (extremamente rara, com altas doses).',
            'Bradicardia, hipotensão ou outros efeitos cardiovasculares (raros).'
          ],
          contraindications: [
            'Alergia conhecida ao anestésico.',
            'Infecção ativa no local de aplicação.',
            'Distúrbios graves de condução cardíaca (avaliação caso a caso).'
          ]
        )
      end

      # ─────────────────────────────────────────────────────────────────────
      # Helpers compartilhados — geram o corpo padrão de consentimentos de
      # procedimento (estrutura comum: benefícios + riscos + contraindicações
      # + declaração final + assinatura).
      # ─────────────────────────────────────────────────────────────────────

      def procedure_consent(name:, document_type:, procedure_label:, benefits:, risks:, contraindications:)
        {
          name: name,
          document_type: document_type,
          content_json: doc(
            heading(1, 'TERMO DE CONSENTIMENTO LIVRE E ESCLARECIDO', align: 'center'),
            heading(3, procedure_label, align: 'center'),
            paragraph(''),
            paragraph(
              'Eu, ',
              variable('patient.full_name'),
              ', CPF ',
              variable('patient.cpf'),
              ', declaro que fui informado(a) de forma clara e em linguagem acessível ',
              'sobre o procedimento "',
              bold(procedure_label),
              '" que será realizado.',
              align: 'justify'
            ),
            paragraph(''),
            heading(2, 'Benefícios esperados'),
            bullet_list(*benefits),
            heading(2, 'Riscos e efeitos adversos possíveis'),
            bullet_list(*risks),
            heading(2, 'Contraindicações'),
            bullet_list(*contraindications),
            heading(2, 'Declaração final'),
            paragraph(
              'Tive a oportunidade de fazer perguntas, todas foram respondidas de forma ',
              'satisfatória, e estou ciente de que os resultados podem variar entre ',
              'indivíduos. Autorizo o(a) profissional ',
              variable('professional.name'),
              ' (',
              variable('professional.council_full'),
              ') a realizar o procedimento.',
              align: 'justify'
            ),
            paragraph(''),
            paragraph(variable('date.city_today'), align: 'right'),
            paragraph(''),
            patient_signature_block
          )
        }
      end

      def patient_signature_block
        [
          paragraph(text('_______________________________'), align: 'center'),
          paragraph(variable('patient.full_name'), align: 'center'),
          paragraph(italic('Assinatura do paciente'), align: 'center')
        ]
      end
    end
  end
end
