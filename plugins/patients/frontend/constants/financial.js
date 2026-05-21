/**
 * Constants do módulo Financeiro do paciente.
 *
 * Extraído de FinancialTab.vue (Roadmap #11). Configurações estáticas
 * centralizadas para reuso entre tab principal, sub-componentes e templates
 * de impressão.
 *
 * Os labels textuais aqui são pt-BR fixo — são valores semânticos
 * usados nos badges de status e dropdowns. Strings de UI ficam em
 * `app/javascript/dashboard/i18n/locale/{lang}/patientFinancial.json`.
 */

// `cls` permanece para compat com componentes que ainda usam classes Tailwind
// inline (PayTransactionModal). Novos componentes devem usar `intent`/`color`
// para o Badge global.
export const TX_STATUS_CONFIG = {
  pago: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.TX.PAID',
    label: 'PAGO',
    intent: 'success',
    cls: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20',
    icon: 'i-lucide-check-circle-2',
  },
  pendente: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.TX.PENDING',
    label: 'EM ABERTO',
    intent: 'warning',
    cls: 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20',
    icon: 'i-lucide-calendar',
  },
  vencido: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.TX.OVERDUE',
    label: 'VENCIDO',
    intent: 'danger',
    cls: 'bg-red-500/10 text-red-600 dark:text-red-400 border-red-500/20',
    icon: 'i-lucide-clock-3',
  },
  cancelado: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.TX.CANCELLED',
    label: 'CANCELADO',
    intent: 'neutral',
    cls: 'bg-slate-500/10 text-slate-600 dark:text-slate-400 border-slate-500/20',
    icon: 'i-lucide-x-circle',
  },
  reembolsado: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.TX.REFUNDED',
    label: 'ESTORNADO',
    color: 'violet',
    cls: 'bg-purple-500/10 text-purple-600 dark:text-purple-400 border-purple-500/20',
    icon: 'i-lucide-rotate-ccw',
  },
  // Baixa parcial: parcela teve pagamento, mas falta saldo. UI mostra
  // saldo restante (riscando o valor original) + label "Parcial" em tom
  // azul (informativo, não alerta — diferente de "vencido" vermelho).
  parcial: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.TX.PARTIAL',
    label: 'PARCIAL',
    intent: 'info',
    cls: 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border-blue-500/20',
    icon: 'i-lucide-pie-chart',
  },
};

// Cor + ícone por método de pagamento — reutilizado em badges, dropdowns
// e botões. `intent` mapeia direto pro Badge global.
// Cor por método de pagamento — usado no Badge da tabela e no PayModal.
// PIX virou `teal` em [1.5.4.6] (era `cyan`, mas o design system não tem
// tokens `--cyan-N` no `:root`, só o Badge tinha hex hardcoded interno).
// Teal é visualmente similar e tem suporte completo (slate/emerald/amber/
// ruby/blue/teal/violet/slate cobrem todos os métodos).
export const PAYMENT_METHOD_VISUAL = {
  // `pix` usa cor brand oficial do Banco Central (rgb(46, 189, 175))
  // adicionada como variant dedicada `pix` no Badge global. Garante visual
  // consistente em qualquer lugar que renderize um Badge de PIX.
  pix: { color: 'pix', icon: 'i-lucide-qr-code' },
  // Aliases v1/v2 — `credito`/`debito` (v2 enum) e `cartao_*` (legado).
  credito: { color: 'violet', icon: 'i-lucide-credit-card' },
  debito: { color: 'blue', icon: 'i-lucide-credit-card' },
  cartao_credito: { color: 'violet', icon: 'i-lucide-credit-card' },
  cartao_debito: { color: 'blue', icon: 'i-lucide-credit-card' },
  dinheiro: { color: 'emerald', icon: 'i-lucide-banknote' },
  boleto: { color: 'amber', icon: 'i-lucide-file-text' },
  transferencia: { color: 'blue', icon: 'i-lucide-arrow-right-left' },
  cheque: { color: 'slate', icon: 'i-lucide-scroll-text' },
  // Pagamento via crédito do paciente (saldo a favor). Visual emerald +
  // ícone carteira pra sinalizar "veio do saldo dele", distinto de Crédito
  // (cartão) que é violet.
  credito_paciente: { color: 'emerald', icon: 'i-lucide-wallet' },
  // Quitação combinada de múltiplas formas de pagamento no mesmo recibo.
  multiplas: { color: 'slate', icon: 'i-lucide-layers' },
  outros: { color: 'slate', icon: 'i-lucide-more-horizontal' },
};

export const paymentMethodVisual = method =>
  PAYMENT_METHOD_VISUAL[method] || PAYMENT_METHOD_VISUAL.outros;

export const ESTIMATE_STATUS_CONFIG = {
  rascunho: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.ESTIMATE.DRAFT',
    label: 'Rascunho',
    cls: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
  },
  enviado: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.ESTIMATE.SENT',
    label: 'Enviado',
    cls: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
  },
  aprovado: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.ESTIMATE.APPROVED',
    label: 'Aprovado',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
  },
  cancelado: {
    labelKey: 'PATIENT_FINANCIAL.STATUS.ESTIMATE.CANCELLED',
    label: 'Cancelado',
    cls: 'bg-red-500/10 text-red-400 border-red-500/20',
  },
};

export const DISCOUNT_TYPE_OPTIONS = [
  {
    value: 'fixo',
    label: 'Valor Fixo (R$)',
    labelKey: 'PATIENT_FINANCIAL.DISCOUNT.FIXED',
  },
  {
    value: 'percentual',
    label: 'Percentual (%)',
    labelKey: 'PATIENT_FINANCIAL.DISCOUNT.PERCENT',
  },
];

// Opções de método de pagamento alinhadas ao enum v2 `Installment::PAYMENT_METHODS`.
// Valores legados (`cartao_credito`, `cartao_debito`, `outros`) foram removidos
// porque o backend (`Installment`/`Expense`/`PaymentReceipt`) rejeita com
// "Payment method não está incluso na lista". O enum v2 usa `credito`/`debito`
// (sem prefixo "cartao_") e não tem "outros".
export const PAYMENT_METHOD_OPTIONS = [
  { value: 'pix', label: 'PIX' },
  { value: 'dinheiro', label: 'Dinheiro' },
  { value: 'credito', label: 'Cartão de Crédito' },
  { value: 'debito', label: 'Cartão de Débito' },
  { value: 'boleto', label: 'Boleto' },
  { value: 'transferencia', label: 'Transferência' },
  { value: 'cheque', label: 'Cheque' },
];

export const PAYMENT_METHOD_BADGE_LABELS = {
  pix: 'PIX',
  // Aliases v1/v2 — `credito`/`debito` (enum v2) e `cartao_*` (legado).
  credito: 'Crédito',
  debito: 'Débito',
  cartao_credito: 'Crédito',
  cartao_debito: 'Débito',
  dinheiro: 'Dinheiro',
  boleto: 'Boleto',
  transferencia: 'Transf.',
  cheque: 'Cheque',
  // Pagamento via saldo a favor do paciente — distinto do "Crédito" (cartão).
  credito_paciente: 'Crédito do paciente',
  multiplas: 'Múltiplas',
  outros: 'Outros',
};

export const PAY_MODAL_METHOD_BUTTONS = [
  { v: 'pix', l: 'PIX', icon: 'i-lucide-qr-code' },
  { v: 'dinheiro', l: 'Dinheiro', icon: 'i-lucide-banknote' },
  { v: 'cartao_credito', l: 'Crédito', icon: 'i-lucide-credit-card' },
  { v: 'cartao_debito', l: 'Débito', icon: 'i-lucide-credit-card' },
  { v: 'transferencia', l: 'Transf.', icon: 'i-lucide-arrow-right-left' },
  { v: 'boleto', l: 'Boleto', icon: 'i-lucide-file-text' },
];

export const TX_FILTER_OPTIONS = [
  { v: 'all', l: 'Todos' },
  { v: 'pendente', l: 'Pendentes' },
  { v: 'pago', l: 'Pagos' },
  { v: 'vencido', l: 'Vencidos' },
];

export const txStatusConfig = status =>
  TX_STATUS_CONFIG[status] || TX_STATUS_CONFIG.pendente;

export const estimateStatusConfig = status =>
  ESTIMATE_STATUS_CONFIG[status] || ESTIMATE_STATUS_CONFIG.rascunho;

export const BRT = 'America/Sao_Paulo';
