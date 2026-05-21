// Metadados das categorias — ícone, nome, descrição.
// Os artigos são carregados dinamicamente via API (/public/api/v1/help_articles).
// Os artigos abaixo servem como fallback estático enquanto a API não tiver conteúdo.
export const CATEGORIES_META = [
  {
    id: 'conversas',
    name: 'Conversas',
    description: 'Caixa de entrada, atribuições, respostas prontas e fluxos de mensagem.',
    icon: 'i-lucide-message-circle',
    articles: [
      { id: 'c1', title: 'Como atribuir uma conversa para um agente', time: '3 min', body: '<p>Atribua conversas manualmente ou via regras automáticas para garantir que cada cliente seja atendido pelo agente certo.</p><p>Acesse a conversa, clique em "Agente atribuído" no painel lateral e escolha o membro do time.</p>' },
      { id: 'c2', title: 'Configurar respostas prontas', time: '5 min', body: '<p>Respostas prontas economizam tempo em perguntas frequentes.</p><p>Vá em Configurações → Respostas Prontas e crie atalhos com "/".</p>' },
      { id: 'c3', title: 'Marcar uma conversa como resolvida', time: '1 min', body: '<p>Clique em "Resolver" no topo da conversa para encerrar o atendimento.</p><p>Conversas resolvidas podem ser reabertas a qualquer momento.</p>' },
      { id: 'c4', title: 'Usar etiquetas para organizar atendimentos', time: '4 min' },
      { id: 'c5', title: 'Mensagens privadas entre agentes', time: '2 min' },
      { id: 'c6', title: 'Configurar SLA para conversas', time: '6 min' },
    ],
  },
  {
    id: 'agenda',
    name: 'Agenda',
    description: 'Agendamentos, lembretes, integração com calendários e disponibilidade.',
    icon: 'i-lucide-calendar',
    articles: [
      { id: 'a1', title: 'Como criar um novo agendamento', time: '3 min', body: '<p>Vá até Agenda → Novo agendamento, escolha o paciente, profissional, data e horário.</p><p>O sistema verifica conflitos automaticamente.</p>' },
      { id: 'a2', title: 'Sincronizar com Google Calendar', time: '4 min' },
      { id: 'a3', title: 'Configurar lembretes automáticos por WhatsApp', time: '5 min' },
      { id: 'a4', title: 'Bloquear horários para almoço ou folga', time: '2 min' },
      { id: 'a5', title: 'Reagendar ou cancelar consulta', time: '2 min' },
    ],
  },
  {
    id: 'pacientes',
    name: 'Pacientes',
    description: 'Cadastros, prontuários, histórico de atendimento e dados clínicos.',
    icon: 'i-lucide-users',
    articles: [
      { id: 'p1', title: 'Cadastrar novo paciente', time: '3 min', body: '<p>Acesse Pacientes → Novo, preencha os dados básicos e clique em salvar.</p><p>Campos personalizados podem ser adicionados em Configurações → Atributos Personalizados.</p>' },
      { id: 'p2', title: 'Importar lista de pacientes via CSV', time: '7 min' },
      { id: 'p3', title: 'Adicionar um arquivo ao prontuário', time: '2 min' },
      { id: 'p4', title: 'LGPD: consentimento e exclusão de dados', time: '8 min' },
      { id: 'p5', title: 'Mesclar pacientes duplicados', time: '3 min' },
    ],
  },
  {
    id: 'financeiro',
    name: 'Financeiro',
    description: 'Cobranças, recebimentos, planos, faturas e relatórios financeiros.',
    icon: 'i-lucide-wallet',
    articles: [
      { id: 'f1', title: 'Como emitir uma cobrança via Pix', time: '4 min', body: '<p>No menu Financeiro, clique em "Nova cobrança", selecione o paciente e o valor.</p><p>Escolha "Pix" como método e o QR Code será gerado automaticamente.</p>' },
      { id: 'f2', title: 'Configurar pagamento recorrente', time: '5 min' },
      { id: 'f3', title: 'Gerenciar assinatura e upgrade de plano', time: '3 min', body: '<p>Acesse Configurações → Cobrança para ver seu plano atual.</p><p>Você pode fazer upgrade, downgrade ou cancelar a qualquer momento sem multa.</p>' },
      { id: 'f4', title: 'Exportar relatório de faturamento', time: '2 min' },
      { id: 'f5', title: 'Comprar mais créditos para a Beatriz AI', time: '2 min' },
    ],
  },
  {
    id: 'bea',
    name: 'BEA',
    description: 'Beatriz AI: assistente que automatiza atendimentos e classifica conversas.',
    icon: 'i-lucide-sparkles',
    articles: [
      { id: 'b1', title: 'O que é a Beatriz AI?', time: '3 min', body: '<p>Beatriz é a assistente de IA integrada ao seu sistema. Ela responde perguntas frequentes, qualifica leads e ajuda a redigir mensagens.</p><p>Funciona 24/7 e aprende com as conversas anteriores do seu time.</p>' },
      { id: 'b2', title: 'Treinar a Beatriz com a base de conhecimento', time: '8 min' },
      { id: 'b3', title: 'Configurar quando a IA assume a conversa', time: '5 min' },
      { id: 'b4', title: 'Entender consumo de créditos da BEA', time: '4 min' },
      { id: 'b5', title: 'Personalizar tom de voz e personalidade', time: '6 min' },
    ],
  },
  {
    id: 'configuracoes',
    name: 'Configurações',
    description: 'Conta, times, canais, integrações, segurança e personalização do espaço.',
    icon: 'i-lucide-bolt',
    articles: [
      { id: 's1', title: 'Convidar novos agentes para o time', time: '3 min', body: '<p>Vá em Configurações → Agentes e clique em "Adicionar agente". Insira o e-mail e selecione o nível de permissão.</p><p>O convite é enviado por e-mail e expira em 7 dias.</p>' },
      { id: 's2', title: 'Conectar canal de WhatsApp Business', time: '10 min' },
      { id: 's3', title: 'Habilitar autenticação de dois fatores', time: '4 min' },
      { id: 's4', title: 'Personalizar atributos de contato', time: '5 min' },
      { id: 's5', title: 'Configurar webhook para automações', time: '8 min' },
      { id: 's6', title: 'Ajustar permissões de equipe', time: '5 min' },
    ],
  },
  {
    id: 'outro',
    name: 'Outros',
    description: 'Artigos diversos e tópicos que não se encaixam nas categorias acima.',
    icon: 'i-lucide-folder-open',
    hidden: true,
    articles: [],
  },
];

// Alias retrocompatível — componentes que importam CATEGORIES continuam funcionando
// durante a transição para dados dinâmicos.
export const CATEGORIES = CATEGORIES_META;

export const FAQS = [
  {
    id: 'q1',
    cat: 'configuracoes',
    catName: 'Configurações',
    question: 'Como faço upgrade do meu plano?',
    answer: 'Você pode fazer upgrade do seu plano a qualquer momento, sem precisar falar com o nosso time. Acesse Configurações → Cobrança e clique em Atualizar plano. O valor proporcional é calculado automaticamente, e você só paga a diferença até o próximo ciclo.',
    tags: ['plano', 'cobrança', 'trial'],
  },
  {
    id: 'q2',
    cat: 'bea',
    catName: 'BEA',
    question: 'Como a Beatriz AI cobra os créditos?',
    answer: 'Cada interação da Beatriz consome créditos com base no tamanho da resposta gerada. Mensagens curtas (até 200 caracteres): 1 crédito. Respostas longas com contexto: 3 a 5 créditos. Resumos de conversa: 8 créditos. Você acompanha o consumo em tempo real no painel da BEA.',
    tags: ['créditos', 'beatriz', 'ia'],
  },
  {
    id: 'q3',
    cat: 'conversas',
    catName: 'Conversas',
    question: 'Posso transferir uma conversa para outro agente sem perder o histórico?',
    answer: 'Sim. Toda conversa carrega seu histórico completo, independente de quantas vezes for transferida ou atribuída para times diferentes. Para transferir, abra a conversa, clique em "Agente atribuído" no painel lateral e selecione o novo responsável.',
    tags: ['atribuição', 'histórico'],
  },
  {
    id: 'q4',
    cat: 'agenda',
    catName: 'Agenda',
    question: 'Como evito que dois pacientes marquem o mesmo horário?',
    answer: 'Quando o link público de agendamento está ativo, o sistema bloqueia automaticamente o horário no momento em que alguém confirma. Você pode ajustar o tempo de bloqueio em Agenda → Configurações → Buffer entre consultas.',
    tags: ['agendamento', 'online'],
  },
  {
    id: 'q5',
    cat: 'financeiro',
    catName: 'Financeiro',
    question: 'Como faço para emitir nota fiscal automaticamente?',
    answer: 'A emissão automática está disponível nos planos Pro e Business. Após conectar o seu emissor (NFE.io, eNotas ou Bling) em Integrações, toda cobrança paga gera a nota automaticamente. Notas avulsas também podem ser emitidas manualmente no menu Financeiro.',
    tags: ['nota fiscal', 'integração'],
  },
  {
    id: 'q6',
    cat: 'pacientes',
    catName: 'Pacientes',
    question: 'Como meus pacientes podem solicitar exclusão de dados (LGPD)?',
    answer: 'Cada paciente tem direito de solicitar a exclusão dos seus dados a qualquer momento. Atenda ao pedido pelo menu Paciente → Mais opções → Excluir dados pessoais. O sistema mantém apenas os dados clínicos exigidos por lei (CFM) e remove o restante de forma irreversível.',
    tags: ['lgpd', 'privacidade'],
  },
  {
    id: 'q7',
    cat: 'configuracoes',
    catName: 'Configurações',
    question: 'Posso usar o sistema em mais de um dispositivo ao mesmo tempo?',
    answer: 'Sim. Sua conta pode estar logada em quantos dispositivos quiser simultaneamente. Notificações chegam em todos eles, e o estado das conversas é sincronizado em tempo real.',
    tags: ['dispositivos', 'login'],
  },
];
