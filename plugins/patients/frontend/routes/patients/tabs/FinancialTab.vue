<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * FinancialTab — Aba "Financeiro do Paciente" do prontuário.
 *
 * Gestão financeira completa: orçamentos, transações (parcelas), recibos,
 * cobrança WhatsApp, comprovantes, estornos, KPIs, impressão de extrato e
 * recibos. Auto-suficiente: lê patientId da rota e faz seu próprio fetch.
 *
 * Recebe `patient` como prop (nome no recibo + extrato).
 * Emite `update-financial-status` (string 'Adimplente' | 'Inadimplente')
 * para que o pai sincronize o badge financeiro mostrado no header.
 *
 * Componente extraído de Record.vue (Fase 5 do refactor).
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import FinancialEstimatesAPI from '@plugins/patients/frontend/api/patients/financialEstimates';
import TransactionsAPI from '@plugins/patients/frontend/api/patients/transactions';
import bankAccountsApi from '@plugins/financial/frontend/features/financial/api/bankAccounts';

const props = defineProps({
  patient: { type: Object, required: true },
});
const emit = defineEmits(['update-financial-status']);

const route = useRoute();

const BRT = 'America/Sao_Paulo';

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return formatDateBR(dateStr) || '—';
};
const formatCurrency = value => {
  if (!value) return 'R$ 0,00';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value);
};

const financialSummary = ref(null);
const transactions = ref([]);
const financialEstimates = ref([]);
const activeFinancialTab = ref('transactions');
const financialFilter = ref('all');
const financialLoading = ref(false);

// Helpers de formatação BRL para inputs
const subtotalRaw = ref('');
const formatCurrencyInput = val => {
  const num = parseFloat(String(val).replace(/\./g, '').replace(',', '.'));
  if (Number.isNaN(num)) return '';
  return num.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};
const parseCurrencyInput = val => {
  const cleaned = String(val).replace(/\./g, '').replace(',', '.');
  const num = parseFloat(cleaned);
  return Number.isNaN(num) ? 0 : num;
};
const onSubtotalInput = e => {
  // Mantém apenas dígitos
  const raw = e.target.value.replace(/\D/g, '');
  const cents = parseInt(raw || '0', 10);
  const num = cents / 100;
  subtotalRaw.value = num.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  e.target.value = subtotalRaw.value;
};

// Modal: Receber Pagamento
const showPayModal = ref(false);
const payModalLoading = ref(false);
const selectedTxId = ref(null);
const bankAccountsForPay = ref([]);
const payForm = ref({
  payment_method: 'pix',
  paid_at: new Date().toISOString().split('T')[0],
  bank_account_id: '',
  notes: '',
});

const loadBankAccountsForPay = async () => {
  try {
    const { data } = await bankAccountsApi.get();
    bankAccountsForPay.value = data.bank_accounts || [];
  } catch {
    bankAccountsForPay.value = [];
  }
};

// Modal: Novo Orçamento
const showEstimateModal = ref(false);
const estimateModalLoading = ref(false);
const estimateForm = ref({
  discount_type: 'fixo',
  discount_value: 0,
  installments_count: 1,
  payment_method: 'pix',
  notes: '',
  valid_until: new Date(Date.now() + 30 * 864e5).toISOString().split('T')[0],
});

const TX_STATUS_CONFIG = {
  pago: {
    label: 'PAGO',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    icon: 'i-lucide-check-circle-2',
  },
  pendente: {
    label: 'EM ABERTO',
    cls: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
    icon: 'i-lucide-calendar',
  },
  vencido: {
    label: 'VENCIDO',
    cls: 'bg-red-500/10 text-red-400 border-red-500/20',
    icon: 'i-lucide-clock-3',
  },
  cancelado: {
    label: 'CANCELADO',
    cls: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
    icon: 'i-lucide-x-circle',
  },
  reembolsado: {
    label: 'ESTORNADO',
    cls: 'bg-purple-500/10 text-purple-400 border-purple-500/20',
    icon: 'i-lucide-rotate-ccw',
  },
};

const ESTIMATE_STATUS_CONFIG = {
  rascunho: {
    label: 'Rascunho',
    cls: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
  },
  enviado: {
    label: 'Enviado',
    cls: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
  },
  aprovado: {
    label: 'Aprovado',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
  },
  cancelado: {
    label: 'Cancelado',
    cls: 'bg-red-500/10 text-red-400 border-red-500/20',
  },
};

const filteredTransactions = computed(() => {
  const list = transactions.value || [];
  const today = new Date().toISOString().split('T')[0];
  switch (financialFilter.value) {
    case 'pendente':
      return list.filter(
        t => t.status === 'pendente' && (!t.due_date || t.due_date >= today)
      );
    case 'pago':
      return list.filter(t => t.status === 'pago');
    case 'vencido':
      return list.filter(
        t =>
          t.status === 'vencido' ||
          (t.status === 'pendente' && t.due_date && t.due_date < today)
      );
    default:
      return list;
  }
});

// Parcelas pendentes para selecionar no modal Receber
const pendingTransactions = computed(() =>
  (transactions.value || []).filter(
    t => t.status === 'pendente' || t.status === 'vencido'
  )
);

const fetchFinancialData = async () => {
  financialLoading.value = true;
  try {
    const [summaryRes, txRes, estimatesRes] = await Promise.all([
      TransactionsAPI.getSummary(route.params.patientId),
      TransactionsAPI.get(route.params.patientId),
      FinancialEstimatesAPI.get(route.params.patientId),
    ]);
    financialSummary.value = summaryRes.data;
    if (summaryRes.data?.overall_status) {
      const s = summaryRes.data.overall_status;
      if (s === 'inadimplente') emit('update-financial-status', 'Inadimplente');
      else emit('update-financial-status', 'Adimplente');
    }
    transactions.value = (
      txRes.data?.transactions ||
      txRes.data?.data ||
      txRes.data ||
      []
    ).map(tx => {
      if (tx.status === 'pendente' && tx.is_overdue) {
        return { ...tx, status: 'vencido' };
      }
      return tx;
    });
    financialEstimates.value =
      estimatesRes.data?.financial_estimates ||
      estimatesRes.data?.data ||
      estimatesRes.data ||
      [];
  } catch {
    useAlert('Erro ao carregar dados financeiros.');
  } finally {
    financialLoading.value = false;
  }
};

const openPayModal = (txId = null) => {
  selectedTxId.value = txId;
  payForm.value = {
    payment_method: 'pix',
    paid_at: new Date().toISOString().split('T')[0],
    bank_account_id:
      bankAccountsForPay.value.length === 1
        ? bankAccountsForPay.value[0].id
        : '',
    notes: '',
  };
  showPayModal.value = true;
};

const confirmPayment = async () => {
  if (!selectedTxId.value) return;
  payModalLoading.value = true;
  try {
    await TransactionsAPI.pay(route.params.patientId, selectedTxId.value, {
      payment_method: payForm.value.payment_method,
      paid_at: payForm.value.paid_at,
      bank_account_id: payForm.value.bank_account_id || null,
    });
    useAlert('Pagamento registrado com sucesso!');
    showPayModal.value = false;
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao registrar pagamento.');
  } finally {
    payModalLoading.value = false;
  }
};

const payTransaction = txId => openPayModal(txId);

const openEstimateModal = () => {
  subtotalRaw.value = '';
  estimateForm.value = {
    discount_type: 'fixo',
    discount_value: 0,
    installments_count: 1,
    payment_method: 'pix',
    notes: '',
    valid_until: new Date(Date.now() + 30 * 864e5).toISOString().split('T')[0],
  };
  showEstimateModal.value = true;
};

const confirmCreateEstimate = async () => {
  const subtotalValue = parseCurrencyInput(subtotalRaw.value);
  if (!subtotalValue || subtotalValue <= 0) {
    useAlert('Informe um subtotal válido.');
    return;
  }
  estimateModalLoading.value = true;
  try {
    await FinancialEstimatesAPI.create(route.params.patientId, {
      subtotal: subtotalValue,
      discount_type: estimateForm.value.discount_type,
      discount_value:
        parseCurrencyInput(estimateForm.value.discount_value) || 0,
      installments_count:
        parseInt(estimateForm.value.installments_count, 10) || 1,
      payment_method: estimateForm.value.payment_method,
      notes: estimateForm.value.notes,
      valid_until: estimateForm.value.valid_until,
    });
    useAlert('Orçamento criado com sucesso!');
    showEstimateModal.value = false;
    activeFinancialTab.value = 'estimates';
    await fetchFinancialData();
  } catch (e) {
    const msg =
      e.response?.data?.errors?.join(', ') || 'Erro ao criar orçamento.';
    useAlert(msg);
  } finally {
    estimateModalLoading.value = false;
  }
};

const approveEstimate = async estimateId => {
  try {
    await FinancialEstimatesAPI.approve(route.params.patientId, estimateId);
    useAlert('Orçamento aprovado!');
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao aprovar orçamento.');
  }
};

const cancelEstimate = async estimateId => {
  try {
    await FinancialEstimatesAPI.cancel(route.params.patientId, estimateId);
    useAlert('Orçamento cancelado.');
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao cancelar orçamento.');
  }
};

const chargeWhatsapp = async txId => {
  try {
    const res = await TransactionsAPI.chargeWhatsapp(
      route.params.patientId,
      txId
    );
    const msg = res.data?.whatsapp_message || '';
    const phone = res.data?.phone || '';
    if (phone) {
      const url = `https://wa.me/${phone.replace(/\D/g, '')}?text=${encodeURIComponent(msg)}`;
      window.open(url, '_blank');
    } else {
      useAlert('Cobrança preparada — paciente sem telefone cadastrado.');
    }
  } catch {
    useAlert('Erro ao preparar cobrança WhatsApp.');
  }
};

const refundTransaction = async txId => {
  if (!window.confirm('Confirmar estorno desta transação?')) return;
  try {
    await TransactionsAPI.refund(route.params.patientId, txId);
    useAlert('Transação estornada com sucesso!');
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao estornar transação.');
  }
};

// ── Comprovante de Pagamento ────────────────────────────────
const showProofModal = ref(false);
const proofTxId = ref(null);
const proofUploading = ref(false);
const proofTx = computed(() =>
  transactions.value.find(t => t.id === proofTxId.value)
);

const openProofModal = txId => {
  proofTxId.value = txId;
  showProofModal.value = true;
};

const handleProofUpload = async event => {
  const file = event.target.files[0];
  if (!file) return;
  proofUploading.value = true;
  try {
    await TransactionsAPI.uploadProof(
      route.params.patientId,
      proofTxId.value,
      file
    );
    useAlert('Comprovante anexado com sucesso!');
    showProofModal.value = false;
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao anexar comprovante.');
  } finally {
    proofUploading.value = false;
  }
};

const viewProof = async tx => {
  if (tx.payment_proof_url) {
    window.open(tx.payment_proof_url, '_blank');
  }
};

const showPrintModal = ref(false);
const printHtmlContent = ref('');
const printTitle = ref('');

const openPrintPreview = (html, title) => {
  printHtmlContent.value = html;
  printTitle.value = title;
  showPrintModal.value = true;
};

const printFinancial = () => {
  const p = props.patient;
  const name = p?.name || 'Paciente';
  const today = new Date().toLocaleDateString('pt-BR', { timeZone: BRT });

  const txRows = (transactions.value || [])
    .map(tx => {
      const s = txStatusConfig(tx.status);
      return `<tr>
      <td>${tx.due_date ? new Date(tx.due_date + 'T12:00:00').toLocaleDateString('pt-BR', { timeZone: BRT }) : '—'}</td>
      <td>${tx.description || '—'}</td>
      <td>${tx.installment_number || 1}/${tx.total_installments || 1}</td>
      <td style="font-weight:600">${formatCurrency(tx.amount)}</td>
      <td>${tx.payment_method || '—'}</td>
      <td><span style="padding:2px 8px;border-radius:20px;font-size:11px;background:${tx.status === 'pago' ? '#d1fae5' : tx.status === 'vencido' ? '#fee2e2' : '#f1f5f9'};color:${tx.status === 'pago' ? '#065f46' : tx.status === 'vencido' ? '#991b1b' : '#334155'}">${s.label}</span></td>
    </tr>`;
    })
    .join('');

  const estRows = (financialEstimates.value || [])
    .map(est => {
      const s = estimateStatusConfig(est.status);
      return `<tr>
      <td>#${est.id}</td>
      <td>${est.created_at ? new Date(est.created_at).toLocaleDateString('pt-BR', { timeZone: BRT }) : '—'}</td>
      <td style="font-weight:600">${formatCurrency(est.subtotal)}</td>
      <td>${est.discount_amount > 0 ? '- ' + formatCurrency(est.discount_amount) : '—'}</td>
      <td style="font-weight:600;color:#059669">${formatCurrency(est.total)}</td>
      <td>${est.installments_count}x de ${formatCurrency(est.installment_value)}</td>
      <td><span style="padding:2px 8px;border-radius:20px;font-size:11px;background:${est.status === 'aprovado' ? '#d1fae5' : est.status === 'cancelado' ? '#fee2e2' : '#f1f5f9'};color:${est.status === 'aprovado' ? '#065f46' : est.status === 'cancelado' ? '#991b1b' : '#334155'}">${s.label}</span></td>
    </tr>`;
    })
    .join('');

  const html = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Extrato Financeiro — ${name}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 13px; color: #1e293b; background: #fff; padding: 32px; }
    .header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #0f172a; padding-bottom: 16px; margin-bottom: 24px; }
    .clinic-name { font-size: 20px; font-weight: 700; color: #0f172a; }
    .clinic-sub { font-size: 12px; color: #64748b; margin-top: 2px; }
    .patient-name { font-size: 18px; font-weight: 600; text-align: right; }
    .patient-meta { font-size: 12px; color: #64748b; text-align: right; }
    .kpis { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }
    .kpi { border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 16px; }
    .kpi-label { font-size: 10px; text-transform: uppercase; letter-spacing: .05em; color: #94a3b8; margin-bottom: 4px; }
    .kpi-value { font-size: 20px; font-weight: 700; }
    .kpi-value.red { color: #dc2626; }
    .kpi-value.green { color: #16a34a; }
    .kpi-value.blue { color: #2563eb; }
    h2 { font-size: 14px; font-weight: 600; color: #0f172a; margin: 20px 0 8px; text-transform: uppercase; letter-spacing: .05em; }
    table { width: 100%; border-collapse: collapse; font-size: 12px; }
    th { background: #f8fafc; text-align: left; padding: 8px 10px; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: .04em; color: #64748b; border-bottom: 1px solid #e2e8f0; }
    td { padding: 8px 10px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
    tr:last-child td { border-bottom: none; }
    .footer { margin-top: 32px; border-top: 1px solid #e2e8f0; padding-top: 12px; font-size: 11px; color: #94a3b8; text-align: center; }
    @media print { body { padding: 16px; } }
  </style>
</head>
<body>
  <div class="header">
    <div>
      <div class="clinic-name">BeClinic</div>
      <div class="clinic-sub">Extrato Financeiro do Paciente</div>
    </div>
    <div>
      <div class="patient-name">${name}</div>
      <div class="patient-meta">Emitido em ${today}</div>
    </div>
  </div>

  <div class="kpis">
    <div class="kpi">
      <div class="kpi-label">Total Aprovado</div>
      <div class="kpi-value">${formatCurrency(financialSummary.value?.total_approved)}</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Pago / Recebido</div>
      <div class="kpi-value green">${formatCurrency(financialSummary.value?.total_paid)}</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Aberto / Devedor</div>
      <div class="kpi-value red">${formatCurrency(financialSummary.value?.total_open)}</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Crédito Disponível</div>
      <div class="kpi-value blue">${formatCurrency(financialSummary.value?.credit_balance)}</div>
    </div>
  </div>

  <h2>Transações / Extrato</h2>
  <table>
    <thead><tr><th>Vencimento</th><th>Descrição</th><th>Parcela</th><th>Valor</th><th>Método</th><th>Status</th></tr></thead>
    <tbody>${txRows || '<tr><td colspan="6" style="text-align:center;color:#94a3b8;padding:16px">Nenhuma transação</td></tr>'}</tbody>
  </table>

  <h2>Orçamentos e Planos</h2>
  <table>
    <thead><tr><th>#</th><th>Data</th><th>Subtotal</th><th>Desconto</th><th>Total</th><th>Parcelas</th><th>Status</th></tr></thead>
    <tbody>${estRows || '<tr><td colspan="7" style="text-align:center;color:#94a3b8;padding:16px">Nenhum orçamento</td></tr>'}</tbody>
  </table>

  <div class="footer">BeClinic — Documento gerado automaticamente em ${today}</div>
</body>
</html>`;

  openPrintPreview(html, 'Extrato Financeiro');
};

const printReceipt = tx => {
  const p = props.patient;
  const name = p?.name || 'Paciente';
  const paidAt = tx.paid_at
    ? new Date(tx.paid_at + 'T12:00:00').toLocaleDateString('pt-BR', {
        timeZone: BRT,
      })
    : new Date().toLocaleDateString('pt-BR', { timeZone: BRT });
  const methodLabel =
    {
      pix: 'PIX',
      cartao_credito: 'Cartão de Crédito',
      cartao_debito: 'Cartão de Débito',
      dinheiro: 'Dinheiro',
      boleto: 'Boleto',
      transferencia: 'Transferência Bancária',
      outros: 'Outros',
    }[tx.payment_method] ||
    tx.payment_method ||
    '—';
  const receiptNum = String(tx.id).padStart(6, '0');
  const today = new Date().toLocaleDateString('pt-BR', { timeZone: BRT });

  const html = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Recibo #${receiptNum} — ${name}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Helvetica Neue', Arial, sans-serif; color: #1e293b; background: #fff; }
    .page { max-width: 600px; margin: 0 auto; padding: 48px 40px; }
    .top-bar { background: #0f172a; color: #fff; padding: 20px 40px; display: flex; justify-content: space-between; align-items: center; }
    .clinic-name { font-size: 20px; font-weight: 800; letter-spacing: -0.5px; }
    .receipt-tag { font-size: 11px; background: #f59e0b; color: #1e293b; font-weight: 700; padding: 3px 10px; border-radius: 999px; letter-spacing: .05em; }
    .receipt-id { font-size: 11px; color: #94a3b8; margin-top: 4px; }
    .hero { text-align: center; padding: 36px 0 28px; border-bottom: 1px solid #e2e8f0; }
    .amount { font-size: 48px; font-weight: 800; color: #059669; letter-spacing: -1px; }
    .amount-label { font-size: 12px; color: #94a3b8; margin-bottom: 8px; text-transform: uppercase; letter-spacing: .08em; }
    .status-badge { display: inline-block; margin-top: 12px; background: #d1fae5; color: #065f46; font-weight: 700; font-size: 12px; padding: 4px 16px; border-radius: 999px; }
    .details { padding: 28px 0; border-bottom: 1px solid #e2e8f0; }
    .row { display: flex; justify-content: space-between; padding: 8px 0; font-size: 14px; }
    .row .label { color: #64748b; }
    .row .value { font-weight: 600; text-align: right; max-width: 55%; }
    .patient-section { padding: 24px 0 8px; }
    .patient-label { font-size: 11px; text-transform: uppercase; letter-spacing: .08em; color: #94a3b8; margin-bottom: 6px; }
    .patient-name { font-size: 18px; font-weight: 700; color: #0f172a; }
    .footer { margin-top: 40px; text-align: center; font-size: 11px; color: #c0cad8; }
    .divider { border: none; border-top: 1px dashed #e2e8f0; margin: 0; }
    @media print { @page { margin: 0; } body { margin: 0; } .page { padding: 32px; max-width: 100%; } .top-bar { -webkit-print-color-adjust: exact; print-color-adjust: exact; } .amount { -webkit-print-color-adjust: exact; print-color-adjust: exact; } .status-badge { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
  </style>
</head>
<body>
  <div class="top-bar">
    <div>
      <div class="clinic-name">BeClinic</div>
      <div class="receipt-id">Recibo N.º ${receiptNum}</div>
    </div>
    <span class="receipt-tag">RECIBO</span>
  </div>

  <div class="page">
    <div class="hero">
      <div class="amount-label">Valor Pago</div>
      <div class="amount">${formatCurrency(tx.amount)}</div>
      <span class="status-badge">✓ PAGAMENTO CONFIRMADO</span>
    </div>

    <div class="patient-section">
      <div class="patient-label">Paciente</div>
      <div class="patient-name">${name}</div>
    </div>

    <div class="details">
      <div class="row"><span class="label">Descrição</span><span class="value">${tx.description || 'Pagamento'}</span></div>
      <div class="row"><span class="label">Parcela</span><span class="value">${tx.installment_number || 1} de ${tx.total_installments || 1}</span></div>
      <div class="row"><span class="label">Método de Pagamento</span><span class="value">${methodLabel}</span></div>
      <div class="row"><span class="label">Data do Pagamento</span><span class="value">${paidAt}</span></div>
      <div class="row"><span class="label">Data de Emissão</span><span class="value">${today}</span></div>
    </div>

    <div class="footer">
      <p>Este documento é um comprovante de pagamento emitido pela BeClinic.</p>
      <p style="margin-top:4px">Recibo N.º ${receiptNum} — Gerado automaticamente em ${today}</p>
    </div>
  </div>
  </div>
</body>
</html>`;

  openPrintPreview(html, `Recibo #${receiptNum}`);
};

const txStatusConfig = status =>
  TX_STATUS_CONFIG[status] || TX_STATUS_CONFIG.pendente;
const estimateStatusConfig = status =>
  ESTIMATE_STATUS_CONFIG[status] || ESTIMATE_STATUS_CONFIG.rascunho;

onMounted(() => { fetchFinancialData(); loadBankAccountsForPay(); });
</script>

<template>
  <div class="tab-pane fade-in">


            <!-- Header -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Financeiro do Paciente
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Orçamentos, cobranças, parcelas e pagamentos vinculados ao
                  tratamento.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <button
                  v-can="['financial', 'create_estimate']"
                  class="geral-header-btn"
                  @click="openEstimateModal()"
                >
                  <i class="i-lucide-file-plus w-4 h-4" /> Novo Orçamento
                </button>
                <button
                  v-can="['financial', 'create_transaction']"
                  class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2"
                  @click="openPayModal(null)"
                >
                  <i class="i-lucide-receipt w-4 h-4" /> Receber Pagamento
                </button>
              </div>
            </div>

            <!-- KPIs financeiros -->
            <div class="fin-kpi-grid mb-5">
              <div class="fin-kpi-card">
                <div class="fin-kpi-icon">
                  <i class="i-lucide-trending-up w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Total Aprovado</p>
                <p class="fin-kpi-value">
                  {{ formatCurrency(financialSummary?.total_approved) }}
                </p>
                <p class="fin-kpi-hint">Plano principal</p>
              </div>
              <div class="fin-kpi-card fin-kpi-card--green">
                <div class="fin-kpi-icon fin-kpi-icon--green">
                  <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Pago / Recebido</p>
                <p class="fin-kpi-value">
                  {{ formatCurrency(financialSummary?.total_paid) }}
                </p>
                <p class="fin-kpi-hint">Atualizado</p>
              </div>
              <div class="fin-kpi-card fin-kpi-card--amber">
                <div class="fin-kpi-icon fin-kpi-icon--amber">
                  <i class="i-lucide-calendar-clock w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Em Aberto</p>
                <p class="fin-kpi-value">
                  {{ formatCurrency(financialSummary?.total_open) }}
                </p>
                <p class="fin-kpi-hint">
                  {{
                    financialSummary?.next_due_date
                      ? 'Próx: ' + formatDate(financialSummary.next_due_date)
                      : 'Sem pendências'
                  }}
                </p>
              </div>
              <div class="fin-kpi-card fin-kpi-card--red">
                <div class="fin-kpi-icon fin-kpi-icon--red">
                  <i class="i-lucide-alert-circle w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Devedor (Vencido)</p>
                <p
                  class="fin-kpi-value"
                  :class="{
                    'fin-kpi-value--danger':
                      financialSummary?.total_overdue > 0,
                  }"
                >
                  {{ formatCurrency(financialSummary?.total_overdue) }}
                </p>
                <p class="fin-kpi-hint">
                  {{
                    financialSummary?.total_overdue > 0
                      ? 'Exige atenção'
                      : 'Tudo em dia'
                  }}
                </p>
              </div>
              <div class="fin-kpi-card fin-kpi-card--blue">
                <div class="fin-kpi-icon fin-kpi-icon--blue">
                  <i class="i-lucide-wallet w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Crédito</p>
                <p class="fin-kpi-value">
                  {{ formatCurrency(financialSummary?.credit_balance) }}
                </p>
                <p class="fin-kpi-hint">Saldo de estornos</p>
              </div>
            </div>

            <!-- Tabs internas + filtros -->
            <div class="fin-tabs-bar mb-4">
              <div class="fin-tabs-list">
                <button
                  class="fin-tab"
                  :class="
                    activeFinancialTab === 'transactions'
                      ? 'fin-tab--active'
                      : ''
                  "
                  @click="activeFinancialTab = 'transactions'"
                >
                  <i class="i-lucide-list w-3.5 h-3.5" /> Transações
                </button>
                <button
                  class="fin-tab"
                  :class="
                    activeFinancialTab === 'estimates' ? 'fin-tab--active' : ''
                  "
                  @click="activeFinancialTab = 'estimates'"
                >
                  <i class="i-lucide-file-text w-3.5 h-3.5" /> Orçamentos
                  <span
                    v-if="financialEstimates.length"
                    class="fin-tab-badge"
                    >{{ financialEstimates.length }}</span
                  >
                </button>
                <button
                  class="fin-tab"
                  :class="
                    activeFinancialTab === 'receipts' ? 'fin-tab--active' : ''
                  "
                  @click="activeFinancialTab = 'receipts'"
                >
                  <i class="i-lucide-receipt w-3.5 h-3.5" /> Recibos
                </button>
              </div>
              <div class="flex items-center gap-2">
                <div
                  v-if="activeFinancialTab === 'transactions'"
                  class="fin-filter-group"
                >
                  <button
                    v-for="f in [
                      { v: 'all', l: 'Todos' },
                      { v: 'pendente', l: 'Pendentes' },
                      { v: 'pago', l: 'Pagos' },
                      { v: 'vencido', l: 'Vencidos' },
                    ]"
                    :key="f.v"
                    class="fin-filter-btn"
                    :class="
                      financialFilter === f.v ? 'fin-filter-btn--active' : ''
                    "
                    @click="financialFilter = f.v"
                  >
                    {{ f.l }}
                  </button>
                </div>
                <button
                  class="fin-icon-btn"
                  title="Imprimir Extrato"
                  @click="printFinancial()"
                >
                  <i class="i-lucide-printer w-4 h-4" />
                </button>
              </div>
            </div>

            <!-- ABA TRANSAÇÕES -->
            <div v-if="activeFinancialTab === 'transactions'">
              <div
                v-if="financialLoading"
                class="flex items-center justify-center py-16"
              >
                <div
                  class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
                />
              </div>
              <div v-else class="reg-section">
                <div class="proc-table-wrap">
                  <table class="proc-table fin-tx-table">
                    <thead>
                      <tr class="proc-table-head">
                        <th>Vencimento</th>
                        <th>Descrição</th>
                        <th class="fin-tx-col-parcela">Parcela</th>
                        <th class="fin-tx-col-valor">Valor (R$)</th>
                        <th class="fin-tx-col-metodo">Método</th>
                        <th class="fin-tx-col-status">Status</th>
                        <th class="fin-tx-col-acoes">Ações</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-if="filteredTransactions.length === 0">
                        <td colspan="7" class="proc-table-cell">
                          <div class="proc-empty-state">
                            <div class="proc-empty-icon">
                              <i class="i-lucide-receipt-text w-5 h-5" />
                            </div>
                            <p class="proc-empty-text">
                              Nenhuma transação encontrada.
                            </p>
                          </div>
                        </td>
                      </tr>
                      <tr
                        v-for="tx in filteredTransactions"
                        :key="tx.id"
                        class="proc-table-row"
                      >
                        <td class="proc-table-cell">
                          <span
                            class="fin-tx-date"
                            :class="{
                              'fin-tx-date--overdue': tx.status === 'vencido',
                              'fin-tx-date--paid': tx.status === 'pago',
                            }"
                          >
                            {{ tx.due_date ? formatDate(tx.due_date) : '—' }}
                          </span>
                        </td>
                        <td class="proc-table-cell">
                          <p class="proc-cell-primary truncate max-w-[200px]">
                            {{ tx.description || 'Procedimento/Plano' }}
                          </p>
                          <p v-if="tx.paid_at" class="fin-tx-paid-at">
                            Pago em {{ formatDate(tx.paid_at) }}
                          </p>
                        </td>
                        <td
                          class="proc-table-cell fin-tx-col-parcela proc-cell-secondary"
                        >
                          {{ tx.installment_number || '1' }} /
                          {{ tx.total_installments || '1' }}
                        </td>
                        <td
                          class="proc-table-cell fin-tx-col-valor fin-tx-amount"
                          :class="
                            tx.transaction_type === 'despesa'
                              ? 'fin-tx-amount--expense'
                              : 'fin-tx-amount--income'
                          "
                        >
                          {{ formatCurrency(tx.amount) }}
                        </td>
                        <td class="proc-table-cell fin-tx-col-metodo">
                          <span
                            v-if="tx.payment_method"
                            class="fin-method-badge"
                          >
                            {{
                              {
                                pix: 'PIX',
                                cartao_credito: 'Crédito',
                                cartao_debito: 'Débito',
                                dinheiro: 'Dinheiro',
                                boleto: 'Boleto',
                                transferencia: 'Transf.',
                                outros: 'Outros',
                              }[tx.payment_method] || tx.payment_method
                            }}
                          </span>
                          <span v-else class="proc-cell-secondary">—</span>
                        </td>
                        <td class="proc-table-cell fin-tx-col-status">
                          <span
                            class="docs-status-badge"
                            :class="txStatusConfig(tx.status).cls"
                          >
                            <i
                              :class="txStatusConfig(tx.status).icon"
                              class="w-3 h-3 mr-1"
                            />
                            {{ txStatusConfig(tx.status).label }}
                          </span>
                        </td>
                        <td class="proc-table-cell text-right">
                          <div class="fin-tx-actions">
                            <template v-if="!tx.is_manual">
                              <button
                                v-if="
                                  tx.status === 'pendente' ||
                                  tx.status === 'vencido'
                                "
                                v-can="['financial', 'create_transaction']"
                                class="fin-action-btn fin-action-btn--green"
                                @click="openPayModal(tx.id)"
                              >
                                <i class="i-lucide-check w-3 h-3" /> Receber
                              </button>
                              <button
                                v-if="
                                  tx.status === 'pendente' ||
                                  tx.status === 'vencido'
                                "
                                class="fin-icon-btn"
                                title="Cobrar via WhatsApp"
                                @click="chargeWhatsapp(tx.id)"
                              >
                                <i class="i-lucide-message-circle w-4 h-4" />
                              </button>
                              <button
                                v-if="
                                  tx.status === 'pago' && tx.payment_proof_url
                                "
                                class="fin-icon-btn"
                                title="Ver comprovante"
                                @click="viewProof(tx)"
                              >
                                <i class="i-ph-file-text w-4 h-4" />
                              </button>
                              <button
                                v-if="
                                  tx.status === 'pago' && !tx.payment_proof_url
                                "
                                class="fin-icon-btn"
                                title="Anexar comprovante"
                                @click="openProofModal(tx.id)"
                              >
                                <i class="i-ph-upload-simple w-4 h-4" />
                              </button>
                              <button
                                v-if="tx.status === 'pago'"
                                v-can="['financial', 'delete_transaction']"
                                class="fin-icon-btn"
                                title="Estornar transação"
                                @click="refundTransaction(tx.id)"
                              >
                                <i class="i-lucide-undo w-4 h-4" />
                              </button>
                            </template>
                            <template v-else>
                              <span
                                class="inline-flex items-center gap-1 px-2 py-0.5 bg-blue-50 text-blue-600 text-[10px] font-bold uppercase tracking-wide rounded"
                              >
                                <i class="i-lucide-zap w-3 h-3" /> Manual
                              </span>
                            </template>
                          </div>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <!-- ABA ORÇAMENTOS -->
            <div v-else-if="activeFinancialTab === 'estimates'">
              <div
                v-if="financialLoading"
                class="flex items-center justify-center py-16"
              >
                <div
                  class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
                />
              </div>
              <div v-else class="flex flex-col gap-4">
                <div v-if="financialEstimates.length === 0" class="reg-section">
                  <div class="proc-empty-state">
                    <div class="proc-empty-icon">
                      <i class="i-lucide-file-text w-5 h-5" />
                    </div>
                    <p class="proc-empty-text">Nenhum orçamento encontrado.</p>
                    <p class="proc-empty-hint">
                      Clique em "Novo Orçamento" para criar.
                    </p>
                  </div>
                </div>
                <div
                  v-for="est in financialEstimates"
                  :key="est.id"
                  class="fin-estimate-card"
                >
                  <div class="fin-estimate-body">
                    <div class="fin-estimate-meta">
                      <span
                        class="docs-status-badge"
                        :class="estimateStatusConfig(est.status).cls"
                      >
                        {{ estimateStatusConfig(est.status).label }}
                      </span>
                      <span class="fin-estimate-id"
                        >Orçamento #{{ est.id }}</span
                      >
                      <span v-if="est.treatment_plan_id" class="fin-plan-badge">
                        <i class="i-lucide-link w-3 h-3" /> Plano de Tratamento
                      </span>
                    </div>

                    <div class="fin-estimate-values">
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Subtotal</p>
                        <p class="fin-estimate-value-amount">
                          {{ formatCurrency(est.subtotal) }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Desconto</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--red"
                        >
                          - {{ formatCurrency(est.discount_amount) }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Total</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--green fin-estimate-value-amount--lg"
                        >
                          {{ formatCurrency(est.total) }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Parcelas</p>
                        <p class="fin-estimate-value-amount">
                          {{ est.installments_count }}x de
                          {{ formatCurrency(est.installment_value) }}
                        </p>
                      </div>
                    </div>

                    <div class="fin-estimate-summary">
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Pago</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--green"
                        >
                          {{
                            formatCurrency(est.financial_summary?.total_paid)
                          }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Pendente</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--amber"
                        >
                          {{
                            formatCurrency(est.financial_summary?.total_pending)
                          }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Vencido</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--red"
                        >
                          {{
                            formatCurrency(est.financial_summary?.total_overdue)
                          }}
                        </p>
                      </div>
                    </div>

                    <div v-if="est.notes" class="fin-estimate-notes">
                      {{ est.notes }}
                    </div>
                  </div>

                  <div class="fin-estimate-actions">
                    <div class="fin-estimate-dates">
                      <p>Criado em {{ formatDate(est.created_at) }}</p>
                      <p v-if="est.valid_until" class="fin-estimate-valid">
                        Válido até {{ formatDate(est.valid_until) }}
                      </p>
                    </div>
                    <div class="flex gap-2">
                      <button
                        v-if="
                          est.status === 'rascunho' || est.status === 'enviado'
                        "
                        v-can="['financial', 'approve_estimate']"
                        class="fin-action-btn fin-action-btn--green"
                        @click="approveEstimate(est.id)"
                      >
                        <i class="i-lucide-check-circle w-3.5 h-3.5" /> Aprovar
                      </button>
                      <button
                        v-if="
                          est.status !== 'cancelado' &&
                          est.status !== 'aprovado'
                        "
                        v-can="['financial', 'edit_estimate']"
                        class="fin-action-btn fin-action-btn--danger"
                        @click="cancelEstimate(est.id)"
                      >
                        <i class="i-lucide-x-circle w-3.5 h-3.5" /> Cancelar
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- ABA RECIBOS -->
            <div v-else-if="activeFinancialTab === 'receipts'">
              <div class="reg-section">
                <div class="proc-table-wrap">
                  <table class="proc-table">
                    <thead>
                      <tr class="proc-table-head">
                        <th>Data Pagamento</th>
                        <th>Descrição</th>
                        <th>Valor (R$)</th>
                        <th>Método</th>
                        <th class="text-right">Recibo</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-if="
                          transactions.filter(t => t.status === 'pago')
                            .length === 0
                        "
                      >
                        <td colspan="5" class="proc-table-cell">
                          <div class="proc-empty-state">
                            <div class="proc-empty-icon">
                              <i class="i-lucide-file-check w-5 h-5" />
                            </div>
                            <p class="proc-empty-text">
                              Nenhum pagamento confirmado ainda.
                            </p>
                          </div>
                        </td>
                      </tr>
                      <tr
                        v-for="tx in transactions.filter(
                          t => t.status === 'pago'
                        )"
                        :key="'r-' + tx.id"
                        class="proc-table-row fin-tx-row--paid"
                      >
                        <td
                          class="proc-table-cell proc-cell-secondary font-mono"
                        >
                          {{
                            tx.paid_at
                              ? formatDate(tx.paid_at)
                              : formatDate(tx.updated_at)
                          }}
                        </td>
                        <td class="proc-table-cell proc-cell-primary">
                          {{ tx.description || 'Pagamento' }}
                        </td>
                        <td
                          class="proc-table-cell fin-tx-amount fin-tx-amount--income"
                        >
                          {{ formatCurrency(tx.amount) }}
                        </td>
                        <td class="proc-table-cell">
                          <span class="fin-method-badge">
                            {{
                              {
                                pix: 'PIX',
                                cartao_credito: 'Crédito',
                                cartao_debito: 'Débito',
                                dinheiro: 'Dinheiro',
                                boleto: 'Boleto',
                                transferencia: 'Transf.',
                                outros: 'Outros',
                              }[tx.payment_method] || '—'
                            }}
                          </span>
                        </td>
                        <td class="proc-table-cell text-right">
                          <button
                            class="fin-action-btn fin-action-btn--green"
                            @click="printReceipt(tx)"
                          >
                            <i class="i-lucide-receipt w-3.5 h-3.5" /> Recibo
                          </button>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <!-- MODAL: Preview de Impressão -->
            <div
              v-if="showPrintModal"
              class="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm"
              @click.self="showPrintModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-xl shadow-2xl w-full max-w-4xl h-[90vh] flex flex-col overflow-hidden relative"
              >
                <div
                  class="flex items-center justify-between px-4 py-3 border-b border-slate-700/50 flex-shrink-0"
                >
                  <h3
                    class="text-base font-semibold text-slate-100 flex items-center gap-2"
                  >
                    <i class="i-lucide-printer text-sky-400" /> {{ printTitle }}
                  </h3>
                  <div class="flex items-center gap-3">
                    <button
                      class="h-8 px-3 rounded-lg bg-white text-slate-900 font-semibold text-xs hover:bg-slate-100 flex items-center gap-2 transition-colors"
                      @click="$refs.previewIframe.contentWindow.print()"
                    >
                      <i class="i-lucide-printer" /> Imprimir / PDF
                    </button>
                    <button
                      class="p-1 rounded-lg hover:bg-slate-800 text-slate-400 transition-colors"
                      @click="showPrintModal = false"
                    >
                      <i class="i-lucide-x" />
                    </button>
                  </div>
                </div>
                <div class="flex-1 bg-slate-800 overflow-hidden relative">
                  <iframe
                    ref="previewIframe"
                    :srcdoc="printHtmlContent"
                    class="w-full h-full border-none bg-white block absolute inset-0"
                    title="Visualização de Impressão"
                  />
                </div>
              </div>
            </div>

            <!-- MODAL: Anexar Comprovante -->
            <div
              v-if="showProofModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
              @click.self="showProofModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
              >
                <div
                  class="flex items-center justify-between p-6 border-b border-slate-700/50"
                >
                  <div>
                    <h3
                      class="text-lg font-semibold text-slate-100 flex items-center gap-2"
                    >
                      <i class="i-lucide-paperclip text-sky-400" /> Anexar
                      Comprovante
                    </h3>
                    <p class="text-xs text-slate-400 mt-0.5">
                      Anexe o comprovante de pagamento (PIX, boleto, etc.)
                    </p>
                  </div>
                  <button
                    class="p-2 rounded-lg hover:bg-slate-800 text-slate-400"
                    @click="showProofModal = false"
                  >
                    <i class="i-lucide-x" />
                  </button>
                </div>
                <div class="p-6 space-y-4">
                  <div
                    v-if="proofTx"
                    class="bg-slate-800 rounded-xl p-4 space-y-1"
                  >
                    <p class="text-xs text-slate-400">Transação</p>
                    <p class="text-sm font-semibold text-slate-200">
                      {{ proofTx.description || 'Pagamento' }}
                    </p>
                    <p class="text-lg font-bold text-emerald-400">
                      {{ formatCurrency(proofTx.amount) }}
                    </p>
                  </div>
                  <label class="block">
                    <span class="text-sm text-slate-300 mb-2 block"
                      >Arquivo (imagem ou PDF)</span
                    >
                    <div
                      class="border-2 border-dashed border-slate-600 hover:border-sky-500 rounded-xl p-8 text-center cursor-pointer transition-colors relative"
                    >
                      <i
                        class="i-lucide-upload-cloud text-3xl text-slate-500 block mb-2"
                      />
                      <p class="text-sm text-slate-400">
                        Clique para selecionar ou arraste o arquivo
                      </p>
                      <p class="text-xs text-slate-600 mt-1">
                        PNG, JPG, PDF — máx. 10MB
                      </p>
                      <input
                        type="file"
                        accept="image/*,application/pdf"
                        class="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
                        :disabled="proofUploading"
                        @change="handleProofUpload"
                      />
                    </div>
                  </label>
                  <div
                    v-if="proofUploading"
                    class="flex items-center gap-2 text-sky-400 text-sm"
                  >
                    <i class="i-lucide-loader-2 animate-spin" /> Enviando
                    comprovante...
                  </div>
                </div>
              </div>
            </div>

            <!-- MODAL: Receber Pagamento -->

            <div
              v-if="showPayModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
              @click.self="showPayModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
              >
                <div
                  class="flex items-center justify-between p-6 border-b border-slate-700/50"
                >
                  <div>
                    <h3
                      class="text-lg font-semibold text-slate-100 flex items-center gap-2"
                    >
                      <i class="i-lucide-receipt text-emerald-400" /> Registrar
                      Pagamento
                    </h3>
                    <p class="text-xs text-slate-400 mt-0.5">
                      Confirme o método e data do pagamento
                    </p>
                  </div>
                  <button
                    class="text-slate-400 hover:text-slate-100"
                    @click="showPayModal = false"
                  >
                    <i class="i-lucide-x text-xl" />
                  </button>
                </div>
                <div class="p-6 space-y-4">
                  <!-- Seletor de parcela (quando aberto pelo botão do header) -->
                  <div v-if="selectedTxId === null">
                    <label class="block text-sm font-medium text-slate-300 mb-2"
                      >Selecionar Parcela *</label
                    >
                    <div
                      v-if="pendingTransactions.length === 0"
                      class="bg-slate-800/50 border border-slate-700 rounded-xl p-4 text-center text-slate-500 text-sm"
                    >
                      <i
                        class="i-lucide-check-circle-2 text-2xl mb-1 block text-emerald-400"
                      />
                      Nenhuma parcela pendente. Todas as parcelas estão pagas!
                    </div>
                    <div v-else class="space-y-2 max-h-48 overflow-y-auto">
                      <button
                        v-for="pt in pendingTransactions"
                        :key="pt.id"
                        class="w-full flex items-center justify-between p-3 rounded-xl border text-left transition-all"
                        :class="
                          selectedTxId === pt.id
                            ? 'bg-emerald-500/15 border-emerald-500/50'
                            : 'bg-slate-800/50 border-slate-700 hover:border-slate-600'
                        "
                        @click="selectedTxId = pt.id"
                      >
                        <div>
                          <p
                            class="text-sm font-medium text-slate-200 truncate max-w-[200px]"
                          >
                            {{ pt.description || 'Parcela' }}
                          </p>
                          <p class="text-xs text-slate-500 mt-0.5">
                            Venc:
                            {{ pt.due_date ? formatDate(pt.due_date) : '—' }} ·
                            Parcela {{ pt.installment_number }}/{{
                              pt.total_installments
                            }}
                          </p>
                        </div>
                        <div class="text-right shrink-0 ml-4">
                          <p class="font-mono font-semibold text-emerald-400">
                            {{ formatCurrency(pt.amount) }}
                          </p>
                          <span
                            class="text-[10px] font-medium px-1.5 py-0.5 rounded-full border"
                            :class="txStatusConfig(pt.status).cls"
                          >
                            {{ txStatusConfig(pt.status).label }}
                          </span>
                        </div>
                      </button>
                    </div>
                  </div>
                  <!-- Info da parcela já selecionada -->
                  <div
                    v-else
                    class="bg-emerald-500/10 border border-emerald-500/20 rounded-xl p-3 flex items-center justify-between"
                  >
                    <div>
                      <p class="text-xs text-emerald-400 font-medium">
                        Parcela selecionada
                      </p>
                      <p class="text-sm text-slate-200 mt-0.5">
                        {{
                          transactions.find(t => t.id === selectedTxId)
                            ?.description || 'Parcela'
                        }}
                      </p>
                    </div>
                    <button
                      class="text-slate-400 hover:text-red-400 text-xs"
                      @click="selectedTxId = null"
                    >
                      Trocar
                    </button>
                  </div>

                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Método de Pagamento *</label
                    >
                    <div class="grid grid-cols-3 gap-2">
                      <button
                        v-for="m in [
                          { v: 'pix', l: 'PIX', icon: 'i-lucide-qr-code' },
                          {
                            v: 'dinheiro',
                            l: 'Dinheiro',
                            icon: 'i-lucide-banknote',
                          },
                          {
                            v: 'cartao_credito',
                            l: 'Crédito',
                            icon: 'i-lucide-credit-card',
                          },
                          {
                            v: 'cartao_debito',
                            l: 'Débito',
                            icon: 'i-lucide-credit-card',
                          },
                          {
                            v: 'transferencia',
                            l: 'Transf.',
                            icon: 'i-lucide-arrow-right-left',
                          },
                          {
                            v: 'boleto',
                            l: 'Boleto',
                            icon: 'i-lucide-file-text',
                          },
                        ]"
                        :key="m.v"
                        class="flex flex-col items-center gap-1 p-2.5 rounded-xl border text-xs font-medium transition-all"
                        :class="
                          payForm.payment_method === m.v
                            ? 'bg-emerald-500/15 border-emerald-500/50 text-emerald-400'
                            : 'bg-slate-800/50 border-slate-700 text-slate-400 hover:border-slate-600 hover:text-slate-200'
                        "
                        @click="payForm.payment_method = m.v"
                      >
                        <i :class="m.icon" />
                        {{ m.l }}
                      </button>
                    </div>
                  </div>
                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Data do Pagamento</label
                    >
                    <input
                      v-model="payForm.paid_at"
                      type="date"
                      class="form-input w-full"
                    />
                  </div>
                  <!-- Conta de Destino -->
                  <div v-if="bankAccountsForPay.length">
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Conta de Destino</label>
                    <select
                      v-model="payForm.bank_account_id"
                      class="form-input w-full"
                    >
                      <option value="">— Selecionar conta —</option>
                      <option
                        v-for="ba in bankAccountsForPay"
                        :key="ba.id"
                        :value="ba.id"
                      >
                        {{ ba.bank_code ? `${ba.bank_code} · ` : ''
                        }}{{ ba.name
                        }}{{ ba.bank_name ? ` (${ba.bank_name})` : '' }}
                      </option>
                    </select>
                  </div>
                </div>
                <div
                  class="p-6 border-t border-slate-700/50 flex justify-end gap-3"
                >
                  <button class="btn-secondary" @click="showPayModal = false">
                    Cancelar
                  </button>
                  <button
                    class="btn-primary bg-emerald-600 hover:bg-emerald-500 text-white flex items-center gap-2 disabled:opacity-50"
                    :disabled="payModalLoading || !selectedTxId"
                    @click="confirmPayment()"
                  >
                    <i
                      v-if="payModalLoading"
                      class="i-lucide-loader-2 animate-spin"
                    />
                    <i v-else class="i-lucide-check" />
                    Confirmar Pagamento
                  </button>
                </div>
              </div>
            </div>

            <!-- MODAL: Novo Orçamento -->
            <div
              v-if="showEstimateModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
              @click.self="showEstimateModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-lg"
              >
                <div
                  class="flex items-center justify-between p-6 border-b border-slate-700/50"
                >
                  <div>
                    <h3
                      class="text-lg font-semibold text-slate-100 flex items-center gap-2"
                    >
                      <i class="i-lucide-file-plus text-blue-400" /> Novo
                      Orçamento
                    </h3>
                    <p class="text-xs text-slate-400 mt-0.5">
                      Crie um orçamento avulso para este paciente
                    </p>
                  </div>
                  <button
                    class="text-slate-400 hover:text-slate-100"
                    @click="showEstimateModal = false"
                  >
                    <i class="i-lucide-x text-xl" />
                  </button>
                </div>
                <div class="p-6 space-y-4">
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Subtotal (R$) *</label
                      >
                      <div class="relative">
                        <span
                          class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 text-sm font-medium z-10 pointer-events-none"
                          >R$</span
                        >
                        <input
                          :value="subtotalRaw"
                          type="text"
                          inputmode="numeric"
                          placeholder="0,00"
                          style="padding-left: 2.25rem !important"
                          class="form-input w-full font-mono"
                          @input="onSubtotalInput"
                        />
                      </div>
                    </div>
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Parcelas</label
                      >
                      <input
                        v-model="estimateForm.installments_count"
                        type="number"
                        min="1"
                        max="60"
                        class="form-input w-full"
                      />
                    </div>
                  </div>
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Tipo de Desconto</label
                      >
                      <select
                        v-model="estimateForm.discount_type"
                        class="form-input w-full"
                      >
                        <option value="fixo">Valor Fixo (R$)</option>
                        <option value="percentual">Percentual (%)</option>
                      </select>
                    </div>
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Valor Desconto</label
                      >
                      <input
                        v-model="estimateForm.discount_value"
                        type="number"
                        step="0.01"
                        min="0"
                        class="form-input w-full"
                      />
                    </div>
                  </div>
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Método Padrão</label
                      >
                      <select
                        v-model="estimateForm.payment_method"
                        class="form-input w-full"
                      >
                        <option value="pix">PIX</option>
                        <option value="cartao_credito">
                          Cartão de Crédito
                        </option>
                        <option value="cartao_debito">Cartão de Débito</option>
                        <option value="dinheiro">Dinheiro</option>
                        <option value="boleto">Boleto</option>
                        <option value="transferencia">Transferência</option>
                        <option value="outros">Outros</option>
                      </select>
                    </div>
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >1º Vencimento</label
                      >
                      <input
                        v-model="estimateForm.valid_until"
                        type="date"
                        class="form-input w-full"
                      />
                    </div>
                  </div>
                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Observações</label
                    >
                    <textarea
                      v-model="estimateForm.notes"
                      rows="2"
                      placeholder="Observações sobre o orçamento..."
                      class="form-input w-full resize-none"
                    />
                  </div>
                  <!-- Preview do total -->
                  <div
                    v-if="subtotalRaw"
                    class="bg-slate-800/50 border border-slate-700/50 rounded-xl p-3 flex items-center justify-between"
                  >
                    <div class="text-xs text-slate-400">
                      <span
                        >Subtotal:
                        <strong class="text-slate-200"
                          >R$ {{ subtotalRaw }}</strong
                        ></span
                      >
                      <span
                        v-if="estimateForm.discount_value > 0"
                        class="ml-3 text-red-400"
                      >
                        - Desconto:
                        {{
                          estimateForm.discount_type === 'percentual'
                            ? estimateForm.discount_value + '%'
                            : 'R$ ' + estimateForm.discount_value
                        }}
                      </span>
                    </div>
                    <div class="text-right">
                      <p class="text-xs text-slate-400">
                        {{ estimateForm.installments_count }}x de
                      </p>
                      <p class="text-sm font-bold text-emerald-400 font-mono">
                        {{
                          formatCurrency(
                            parseCurrencyInput(subtotalRaw) /
                              (parseInt(estimateForm.installments_count) || 1)
                          )
                        }}
                      </p>
                    </div>
                  </div>
                </div>
                <div
                  class="p-6 border-t border-slate-700/50 flex justify-end gap-3"
                >
                  <button
                    class="btn-secondary"
                    @click="showEstimateModal = false"
                  >
                    Cancelar
                  </button>
                  <button
                    class="btn-primary bg-blue-600 hover:bg-blue-500 text-white flex items-center gap-2 disabled:opacity-50"
                    :disabled="estimateModalLoading || !subtotalRaw"
                    @click="confirmCreateEstimate()"
                  >
                    <i
                      v-if="estimateModalLoading"
                      class="i-lucide-loader-2 animate-spin"
                    />
                    <i v-else class="i-lucide-file-check" />
                    Criar Orçamento
                  </button>
                </div>
              </div>
            </div>
  </div>
</template>

<style scoped>
/* ═══════════════════════════════════════════
   FINANCEIRO — estilos exclusivos
═══════════════════════════════════════════ */

/* KPI grid — 5 colunas iguais */
.fin-kpi-grid {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 12px;
}

/* KPI card base */
.fin-kpi-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 16px 18px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
}

/* Variantes de cor do card */
.fin-kpi-card--green {
  border-color: rgba(34, 197, 94, 0.2);
  background: rgba(34, 197, 94, 0.04);
}
.fin-kpi-card--amber {
  border-color: rgba(251, 191, 36, 0.2);
  background: rgba(251, 191, 36, 0.04);
}
.fin-kpi-card--red {
  border-color: rgba(239, 68, 68, 0.2);
  background: rgba(239, 68, 68, 0.04);
}
.fin-kpi-card--blue {
  border-color: rgba(59, 130, 246, 0.2);
  background: rgba(59, 130, 246, 0.04);
}

/* KPI ícone */
.fin-kpi-icon {
  width: 28px;
  height: 28px;
  border-radius: 7px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  background: rgba(255, 255, 255, 0.05);
  color: #475569;
  margin-bottom: 4px;
}
.fin-kpi-icon--green {
  background: rgba(34, 197, 94, 0.12);
  color: #4ade80;
}
.fin-kpi-icon--amber {
  background: rgba(251, 191, 36, 0.12);
  color: #fbbf24;
}
.fin-kpi-icon--red {
  background: rgba(239, 68, 68, 0.12);
  color: #f87171;
}
.fin-kpi-icon--blue {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}

.fin-kpi-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #475569;
  margin: 0;
}

.fin-kpi-value {
  font-size: 18px;
  font-weight: 700;
  color: #e2e8f0;
  margin: 2px 0 0;
  line-height: 1.1;
  font-variant-numeric: tabular-nums;
}

.fin-kpi-hint {
  font-size: 10px;
  color: #334155;
  margin: 0;
}

.fin-kpi-value--danger {
  color: #f87171;
}

/* ── Tabs internas ──
   O indicador ativo é uma linha reta (sem border-radius no elemento).
   O próprio <button> não tem border-radius para garantir que o underline
   apareça como linha plana de ponta a ponta. */
.fin-tabs-bar {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  margin-bottom: 16px;
}
.fin-tabs-list {
  display: flex;
  gap: 0;
}

.fin-tab {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 9px 16px;
  font-size: 13px;
  font-weight: 500;
  color: #64748b;
  background: transparent;
  border: none;
  border-radius: 0; /* sem arredondamento — underline é linha reta */
  border-bottom: 2px solid transparent;
  cursor: pointer;
  transition:
    color 0.15s,
    border-color 0.15s;
  white-space: nowrap;
  margin-bottom: -1px;
}
.fin-tab:hover {
  color: #94a3b8;
}
.fin-tab--active {
  color: #60a5fa;
  border-bottom-color: #3b82f6;
}

.fin-tab-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  border-radius: 99px;
  background: rgba(255, 255, 255, 0.07);
  color: #64748b;
  font-size: 10px;
  font-weight: 600;
}

/* ── Filtros ──
   Margem inferior para o grupo não tocar a borda divisória */
.fin-filter-group {
  display: flex;
  align-items: center;
  gap: 2px;
  background: rgba(0, 0, 0, 0.2);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 8px;
  padding: 3px;
  margin-bottom: 8px; /* afasta da linha divisória abaixo */
}
.fin-filter-btn {
  padding: 4px 10px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 500;
  color: #64748b;
  background: transparent;
  border: none;
  cursor: pointer;
  transition:
    background 0.13s,
    color 0.13s;
  white-space: nowrap;
}
.fin-filter-btn:hover {
  color: #94a3b8;
}
.fin-filter-btn--active {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}

/* Ícone-botão */
.fin-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  border: none;
  background: transparent;
  color: #475569;
  cursor: pointer;
  transition:
    background 0.14s,
    color 0.14s;
  margin-bottom: 8px; /* alinha com o filtro */
}
.fin-icon-btn:hover {
  background: rgba(255, 255, 255, 0.05);
  color: #94a3b8;
}

/* ── Tabela de transações ──
   Zebra striping: linha par (lighter), linha ímpar (base).
   Alinhamento vertical central em todas as células.
   proc-table-row já adiciona hover; aqui adicionamos nth-child striping. */
.fin-tx-table tbody tr:nth-child(odd) {
  background: rgba(255, 255, 255, 0);
}
.fin-tx-table tbody tr:nth-child(even) {
  background: rgba(255, 255, 255, 0.025);
}

/* Cells — vertical center */
.fin-tx-table td,
.fin-tx-table th {
  vertical-align: middle;
  padding: 12px 14px;
}

/* Alinhamento: colunas numéricas centradas, texto à esquerda */
.fin-tx-table th {
  text-align: left;
}
.fin-tx-table td {
  text-align: left;
}
.fin-tx-col-parcela,
.fin-tx-col-valor,
.fin-tx-col-metodo,
.fin-tx-col-status {
  text-align: center;
}
.fin-tx-col-acoes {
  text-align: right;
}

/* Data de vencimento */
.fin-tx-date {
  font-size: 12px;
  font-family: ui-monospace, monospace;
  color: #64748b;
}
.fin-tx-date--overdue {
  color: #f87171;
  font-weight: 600;
}
.fin-tx-date--paid {
  color: #334155;
  text-decoration: line-through;
}

.fin-tx-paid-at {
  font-size: 11px;
  color: #334155;
  margin-top: 2px;
}

/* Valor */
.fin-tx-amount {
  font-family: ui-monospace, monospace;
  font-weight: 600;
  font-size: 13px;
  color: #e2e8f0;
}
.fin-tx-amount--income {
  color: #e2e8f0;
}
.fin-tx-amount--expense {
  color: #f87171;
}

/* Badge método */
.fin-method-badge {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 11px;
  font-weight: 500;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  color: #64748b;
  white-space: nowrap;
}

/* Ações */
.fin-tx-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
}

/* Botão de ação */
.fin-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 5px 10px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: rgba(255, 255, 255, 0.04);
  color: #64748b;
  transition:
    background 0.13s,
    color 0.13s,
    border-color 0.13s;
  white-space: nowrap;
}
.fin-action-btn:hover {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}
.fin-action-btn--danger:hover {
  background: rgba(239, 68, 68, 0.08);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.15);
}

/* ── Cards de orçamento ── */
.fin-estimate-card {
  display: flex;
  gap: 20px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
  padding: 20px;
  transition: background 0.15s;
}
.fin-estimate-card:hover {
  background: rgba(255, 255, 255, 0.04);
}

.fin-estimate-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.fin-estimate-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.fin-estimate-id {
  font-size: 11px;
  color: #334155;
}

.fin-plan-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: #60a5fa;
  background: rgba(59, 130, 246, 0.08);
  border: 1px solid rgba(59, 130, 246, 0.15);
  border-radius: 99px;
  padding: 2px 8px;
}

.fin-estimate-values {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 14px;
}
.fin-estimate-summary {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 14px;
  padding-top: 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}
.fin-estimate-value-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.fin-estimate-value-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #334155;
  margin: 0;
}

.fin-estimate-value-amount {
  font-size: 13px;
  font-weight: 600;
  color: #94a3b8;
  margin: 0;
  font-variant-numeric: tabular-nums;
}
.fin-estimate-value-amount--highlight {
  color: #e2e8f0;
  font-size: 15px;
}
.fin-estimate-value-amount--danger {
  color: #f87171;
}

.fin-estimate-notes {
  font-size: 12px;
  color: #475569;
  background: rgba(0, 0, 0, 0.15);
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 8px;
  padding: 8px 12px;
}

.fin-estimate-actions {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: space-between;
  gap: 12px;
  flex-shrink: 0;
  min-width: 130px;
}
.fin-estimate-dates {
  text-align: right;
  font-size: 11px;
  color: #334155;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.fin-estimate-valid {
  color: #475569;
}


</style>
