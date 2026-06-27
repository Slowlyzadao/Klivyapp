/**
 * Constants do módulo Documentos.
 *
 * Extraído de DocumentsTab.vue (Roadmap #11).
 */

export const DOC_TYPE_LABELS = {
  receita: 'Receita Médica',
  atestado: 'Atestado Médico',
  pedido_exame: 'Pedido de Exame',
  declaracao: 'Declaração',
  relatorio_clinico: 'Relatório Clínico',
  encaminhamento: 'Encaminhamento',
  contrato: 'Contrato',
  orcamento: 'Orçamento',
  instrucao_procedimento: 'Instruções de Procedimento',
  questionario: 'Questionário',
  outro: 'Outro',
};

export const DOC_TYPE_OPTIONS = Object.entries(DOC_TYPE_LABELS).map(
  ([value, label]) => ({ value, label })
);

export const DOC_STATUS_CONFIG = {
  gerado: {
    label: 'Gerado',
    cls: 'bg-blue-500/15 text-blue-400 border-blue-500/25',
  },
  pendente_assinatura: {
    label: 'Aguard. Assinatura',
    cls: 'bg-amber-500/15 text-amber-400 border-amber-500/25',
  },
  assinado: {
    label: 'Assinado',
    cls: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/25',
  },
  enviado: {
    label: 'Enviado',
    cls: 'bg-purple-500/15 text-purple-400 border-purple-500/25',
  },
  arquivado: {
    label: 'Arquivado',
    cls: 'bg-slate-500/15 text-slate-400 border-slate-500/25',
  },
};

export const docStatusConfig = status =>
  DOC_STATUS_CONFIG[status] || DOC_STATUS_CONFIG.gerado;

// Tipos de documento que usam um único campo livre `conteudo` em vez de
// campos específicos (CID, medicamentos, exames, etc).
export const FREE_CONTENT_TYPES = [
  'relatorio_clinico',
  'declaracao',
  'instrucao_procedimento',
  'contrato',
  'orcamento',
  'questionario',
  'outro',
];

export const blankDocForm = () => ({
  document_type: 'atestado',
  title: '',
  cid: '',
  dias_afastamento: '',
  observacoes: '',
  medicamentos: '',
  posologia: '',
  exames_solicitados: '',
  encaminhado_para: '',
  especialidade: '',
  conteudo_livre: '',
});
