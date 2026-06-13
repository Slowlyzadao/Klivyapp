/**
 * Constants do módulo Consentimentos.
 *
 * Extraído de ConsentsTab.vue (Roadmap #11). Templates de termos jurídicos
 * mantidos em pt-BR FIXO (não i18n-izáveis — validade legal exige texto
 * canônico). Labels podem migrar para i18n no futuro mas as descrições
 * e templates ficam aqui como source of truth.
 *
 * Backfill legacy → 'signed' rodado em 2026-05-04 (entry CHANGELOG 1.5.1.82+).
 * `mode` ('local_tablet'/'remote_link') diferencia o canal — exposto como
 * `signature_method` ('local'/'remote') no JSON do consent_record.
 */

export const EXPIRY_OPTIONS = [
  { value: 1, label: '1 mês' },
  { value: 3, label: '3 meses' },
  { value: 6, label: '6 meses' },
  { value: 12, label: '12 meses (1 ano)' },
  { value: 24, label: '24 meses (2 anos)' },
  { value: 60, label: '60 meses (5 anos)' },
  { value: 0, label: 'Sem vencimento' },
];

export const CONSENT_TYPES = [
  {
    value: 'lgpd',
    label: 'Termo LGPD / Privacidade de Dados',
    icon: 'i-lucide-shield-check',
    color: 'blue',
    description:
      'Autorização para coleta, uso e armazenamento de dados pessoais conforme LGPD (Lei 13.709/2018).',
    template:
      'TERMO DE CONSENTIMENTO PARA USO DE DADOS PESSOAIS (LGPD)\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], declaro que fui devidamente informado(a) sobre:\n\n1. DADOS COLETADOS: nome, data de nascimento, CPF, endereço, contatos, histórico de saúde, fotos e registros de atendimento.\n2. FINALIDADE: gestão do prontuário, agendamento, comunicação sobre tratamentos e emissão de documentos.\n3. ARMAZENAMENTO: servidores com criptografia e acesso restrito.\n4. COMPARTILHAMENTO: não ocorre sem autorização prévia, salvo exigência legal.\n5. DIREITOS: acesso, correção, exclusão ou revogação a qualquer momento.\n\nConsinto expressamente com o tratamento dos meus dados pessoais.',
  },
  {
    value: 'autorizacao_imagem',
    label: 'Autorização de Uso de Imagem',
    icon: 'i-lucide-camera',
    color: 'purple',
    description:
      'Autorização para captura e uso de fotos e vídeos para documentação clínica.',
    template:
      'AUTORIZAÇÃO DE USO DE IMAGEM\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], AUTORIZO a clínica a fotografar e/ou filmar minha imagem durante e após procedimentos estéticos para fins de documentação clínica e acompanhamento de resultados.\n\nDeclaro ciência de que as imagens são armazenadas com segurança e acesso restrito ao corpo clínico.',
  },
  {
    value: 'botox',
    label: 'Consentimento - Toxina Botulínica (Botox)',
    icon: 'i-lucide-syringe',
    color: 'emerald',
    description:
      'Termo de consentimento informado para aplicação de toxina botulínica.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - TOXINA BOTULÍNICA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], declaro ter sido informado(a) sobre:\n\n1. Aplicação de toxina botulínica tipo A em músculos-alvo para relaxamento temporário.\n2. Efeito esperado: início em 3-7 dias; duração de 3-6 meses.\n3. Riscos: hematoma, ptose palpebral, assimetria, cefaleia, reação alérgica (rara).\n4. Contraindicações: gestantes, lactantes, miastenia gravis.\n5. Sem garantia de resultado (obrigação de meios).\n\nDeclaro compreensão plena e consinto com o procedimento.',
  },
  {
    value: 'preenchimento',
    label: 'Consentimento - Preenchimento Dérmico (Filler)',
    icon: 'i-lucide-droplet',
    color: 'cyan',
    description:
      'Termo de consentimento para aplicação de preenchedores dérmicos.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - PREENCHIMENTO DÉRMICO\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de PREENCHIMENTO DÉRMICO com ácido hialurônico.\n\n1. Riscos: edema, equimose, assimetria, nódulos, migração, oclusão vascular (rara mas grave), cegueira (extremamente raro).\n2. Duração: 6 meses a 2 anos conforme produto e área.\n3. Contraindicações: gestação, lactação, doenças autoimunes ativas.\n4. Sem garantia de resultado.\n\nDeclaro ter entendido os riscos e alternativas ao tratamento.',
  },
  {
    value: 'fototerapia',
    label: 'Consentimento - Laser / Fototerapia / LED',
    icon: 'i-lucide-zap',
    color: 'amber',
    description:
      'Termo para procedimentos com laser, luz pulsada, LED ou radiofrequência.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - LASER / FOTOTERAPIA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de LASER / LUZ PULSADA / LED / RADIOFREQUÊNCIA.\n\n1. Riscos: eritema, edema, hiperpigmentação pós-inflamatória, hipopigmentação, queimaduras (raros).\n2. Cuidados: protetor solar FPS 60+ por 30 dias; evitar sol direto.\n3. Contraindicações: bronzeamento recente, gestação, fotossensibilizantes.\n\nDeclaro ciência dos riscos e autorizo o procedimento.',
  },
  {
    value: 'peeling',
    label: 'Consentimento - Peeling Químico / Dermabrasão',
    icon: 'i-lucide-layers',
    color: 'rose',
    description: 'Termo para peelings químicos de diferentes profundidades.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - PEELING QUÍMICO\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de PEELING QUÍMICO.\n\n1. Riscos: eritema prolongado, descamação, hiperpigmentação, herpes recorrente, cicatrizes (raros).\n2. Cuidados: fotoproteção rigorosa por 60 dias; evitar maquiagem por 7 dias.\n3. Contraindicações: gestação, lactação, herpes ativo, isotretinoína nos últimos 6 meses.\n\nDeclaro compreensão e concordo com o procedimento.',
  },
  {
    value: 'menor_idade',
    label: 'Autorização - Paciente Menor de Idade',
    icon: 'i-lucide-baby',
    color: 'orange',
    description:
      'Autorização do responsável legal para tratamento de menor de 18 anos.',
    template:
      'AUTORIZAÇÃO PARA TRATAMENTO DE MENOR DE IDADE\n\nEu, [NOME DO RESPONSÁVEL], portador(a) do CPF [CPF], responsável legal de [NOME DO PACIENTE], AUTORIZO os procedimentos indicados.\n\n1. Tenho ciência plena dos procedimentos e seus riscos.\n2. Fui informado(a) sobre benefícios e alternativas.\n3. Autorizo uso de imagens apenas para documentação clínica.\n\nEm conformidade com ECA (Lei 8.069/90) e normativas do CFM/CFF.',
  },
  {
    value: 'procedimento_cirurgico',
    label: 'Consentimento - Procedimento Cirúrgico Minor',
    icon: 'i-lucide-activity',
    color: 'red',
    description:
      'Termo para pequenas cirurgias ambulatoriais (biópsia, exérese, etc.).',
    template:
      'TERMO DE CONSENTIMENTO - PROCEDIMENTO CIRÚRGICO MENOR\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com o procedimento cirúrgiico indicado.\n\n1. Fui informado sobre o tipo de procedimento, anestesia local e riscos de sangramento, infecção e cicatriz.\n2. Compreendo os cuidados pós-operatórios necessários.\n3. Aceito os riscos inerentes ao procedimento proposto.',
  },
  {
    value: 'anestesia',
    label: 'Consentimento - Anestesia Local/Tópica',
    icon: 'i-lucide-pill',
    color: 'violet',
    description:
      'Consentimento específico para uso de anestesia local ou tópica.',
    template:
      'TERMO DE CONSENTIMENTO - ANESTESIA LOCAL/TÓPICA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], fui informado(a) sobre o uso de anestesia local ou tópica.\n\n1. Reações possíveis: ardência, eritema, edema, tonturas, reações alérgicas (raras).\n2. Alergias conhecidas: [ ] NÃO POSSUO / [ ] POSSUO: ___________\n3. Medicamentos em uso: ___________\n\nConsinto com o uso da anestesia necessária para o procedimento indicado.',
  },
  {
    value: 'geral',
    label: 'Termo de Consentimento Geral',
    icon: 'i-lucide-file-check',
    color: 'slate',
    description:
      'Termo geral para procedimentos não cobertos pelos tipos específicos acima.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO GERAL\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], concordo com a realização do procedimento/tratamento indicado.\n\n1. Fui informado(a) sobre objetivos, riscos, benefícios e alternativas.\n2. Tive oportunidade de esclarecer todas as minhas dúvidas.\n3. Compreendo que resultados não são garantidos.\n4. Poderei revogar este consentimento a qualquer momento antes do procedimento.\n\nElaborado conforme resoluções do CFM e normas da ANVISA.',
  },
];

export const CONSENT_STATUS_CONFIG = {
  pendente: {
    label: 'Pendente',
    cls: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
    icon: 'i-lucide-clock',
  },
  signed: {
    label: 'Assinado',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    icon: 'i-lucide-check-circle',
  },
  vencido: {
    label: 'Vencido',
    cls: 'bg-red-500/10 text-red-400 border-red-500/20',
    icon: 'i-lucide-alert-triangle',
  },
  revogado: {
    label: 'Revogado',
    cls: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
    icon: 'i-lucide-x-circle',
  },
};

export const consentStatusConfig = status =>
  CONSENT_STATUS_CONFIG[status] || CONSENT_STATUS_CONFIG.pendente;

export const consentTypeLabel = type =>
  CONSENT_TYPES.find(t => t.value === type)?.label ||
  type ||
  'Consentimento';
