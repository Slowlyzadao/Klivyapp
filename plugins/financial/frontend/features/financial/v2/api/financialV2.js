/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

/**
 * Cliente HTTP para o módulo financeiro v2 (canon Financial::*).
 * Inclui Idempotency-Key automático em mutações POST/PUT/PATCH/DELETE.
 *
 * Toda chamada que muda estado gera um UUID v4 e envia em `Idempotency-Key`.
 * O backend responde com `Idempotency-Replayed: true` se houver replay.
 */

const HEADER_IDEMPOTENCY = 'Idempotency-Key';

const uuidv4 = () => {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  // RFC 4122 v4 fallback
  const rnd = (size = 16) =>
    Array.from({ length: size }, () =>
      Math.floor(Math.random() * 256).toString(16).padStart(2, '0'),
    ).join('');
  const r = rnd();
  return `${r.slice(0, 8)}-${r.slice(8, 12)}-4${r.slice(13, 16)}-a${r.slice(17, 20)}-${r.slice(20)}`;
};

const idempotentHeaders = (extra = {}) => ({
  ...extra,
  [HEADER_IDEMPOTENCY]: uuidv4(),
});

/**
 * Detecta o 412 do gate de setup financeiro (ensure_setup_complete! no
 * BaseController). O backend bloqueia QUALQUER escrita v2 com
 * { error: 'financial_setup_required' } enquanto Plano de Contas + Contas
 * Bancárias + Formas de Pagamento não estiverem configurados. Os call-sites
 * usam isto pra orientar o usuário (link pro assistente) em vez de mostrar um
 * erro genérico/silencioso.
 */
export const isFinancialSetupRequired = error =>
  error?.response?.status === 412 &&
  error?.response?.data?.error === 'financial_setup_required';

class FinancialV2Base extends ApiClient {
  constructor(resource) {
    // Prefixo `financial/v2/` evita colisão com rotas v1 antigas (canon §coexistência).
    super(`financial/v2/${resource}`, { accountScoped: true });
  }

  index(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id, params = {}) {
    return axios.get(`${this.url}/${id}`, { params });
  }

  create(data, opts = {}) {
    return axios.post(this.url, data, { headers: idempotentHeaders(opts.headers) });
  }

  update(id, data, opts = {}) {
    return axios.patch(`${this.url}/${id}`, data, { headers: idempotentHeaders(opts.headers) });
  }

  destroy(id, opts = {}) {
    return axios.delete(`${this.url}/${id}`, { headers: idempotentHeaders(opts.headers) });
  }

  postAction(id, action, data = {}, opts = {}) {
    return axios.post(`${this.url}/${id}/${action}`, data, {
      headers: idempotentHeaders(opts.headers),
    });
  }

  patchAction(id, action, data = {}, opts = {}) {
    return axios.patch(`${this.url}/${id}/${action}`, data, {
      headers: idempotentHeaders(opts.headers),
    });
  }
}

class CategoriesV2 extends FinancialV2Base {
  constructor() { super('categories'); }

  // Recria as categorias padrão (canon DRE) que estiverem faltando.
  // Aditivo/idempotente no backend — não apaga nada. Retorna { created, skipped, total }.
  restoreDefaults() {
    return axios.post(`${this.url}/restore_defaults`, {}, { headers: idempotentHeaders() });
  }

  // Define esta categoria de receita como a PADRÃO da conta — passa a receber
  // os lançamentos sem categoria explícita (avulso à vista, plano, mensalidade).
  // Backend limpa a anterior; só UMA receita padrão por conta.
  setDefault(id) {
    return this.postAction(id, 'set_default');
  }
}

class BankAccountsV2 extends FinancialV2Base {
  constructor() { super('bank_accounts'); }
  transfer(id, payload) { return this.postAction(id, 'transfer', payload); }
}

class CommissionRulesV2 extends FinancialV2Base {
  constructor() { super('commission_rules'); }
}

class RecurringExpensesV2 extends FinancialV2Base {
  constructor() { super('recurring_expenses'); }
}

class RevenueGoalsV2 extends FinancialV2Base {
  constructor() { super('revenue_goals'); }
  upsert(payload) {
    return axios.post(`${this.url}/upsert`, payload, { headers: idempotentHeaders() });
  }
}

class GatewaySettingV2 extends ApiClient {
  constructor() { super('financial/v2/gateway_setting', { accountScoped: true }); }
  show() { return axios.get(this.url); }
  update(payload) { return axios.patch(this.url, payload, { headers: idempotentHeaders() }); }
}

class BudgetsV2 extends FinancialV2Base {
  constructor() { super('budgets'); }
  approve(id, payload = {}) { return this.postAction(id, 'approve', payload); }
  cancel(id, payload = {}) { return this.postAction(id, 'cancel', payload); }
  updateInstallments(id, installments) {
    return this.patchAction(id, 'update_installments', { installments });
  }
  // F1 do PaymentPlanWizardV2 — simula efeito financeiro de um installments_plan
  // ANTES da aprovação real. Read-only. Sem Idempotency-Key (simulação não muta).
  simulatePlan(id, installmentsPlan) {
    return axios.post(`${this.url}/${id}/simulate_plan`, {
      installments_plan: installmentsPlan,
    });
  }
}

class InstallmentsV2 extends FinancialV2Base {
  constructor() { super('installments'); }
  pay(id, payload) { return this.postAction(id, 'pay', payload); }
  refund(id, payload) { return this.postAction(id, 'refund', payload); }
  chargeWhatsapp(id) { return this.postAction(id, 'charge_whatsapp', {}); }

  // Variante agrupada por paciente. Aceita os mesmos filtros do index
  // mas retorna `[{ patient, summary, installments }]` paginado por paciente.
  // Uso na tela "A Receber" com agrupamento + acordeão.
  byPatient(params = {}) {
    return axios.get(`${this.url}/by_patient`, { params });
  }
  proofUrl(id) { return axios.get(`${this.url}/${id}/proof_url`); }
  uploadProof(id, file) {
    const formData = new FormData();
    formData.append('file', file);
    return axios.post(`${this.url}/${id}/upload_proof`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

class PaymentReceiptsV2 extends FinancialV2Base {
  constructor() { super('payment_receipts'); }
  refund(id, payload = {}) { return this.postAction(id, 'refund', payload); }
}

class ExpensesV2 extends FinancialV2Base {
  constructor() { super('expenses'); }
  pay(id, payload) { return this.postAction(id, 'pay', payload); }
  reverse(id, payload = {}) { return this.postAction(id, 'reverse', payload); }
}

// Lançamentos avulsos no Fluxo de Caixa (canon F-25) + reclassificação em
// massa (F-28). `entries` é a tabela `financial_entries` que registra TODA
// movimentação de caixa — manuais (criadas aqui) + automáticas (geradas por
// ReceivePayment, RefundPayment, CashRegister, ExpensesController).
class EntriesV2 extends FinancialV2Base {
  constructor() { super('entries'); }
  bulkReclassify(payload) {
    return axios.post(`${this.url}/bulk_reclassify`, payload, {
      headers: idempotentHeaders(),
    });
  }
}

class CashRegistersV2 extends FinancialV2Base {
  constructor() { super('cash_registers'); }
  open(payload) {
    return axios.post(`${this.url}/open`, payload, { headers: idempotentHeaders() });
  }
  close(id, payload) { return this.postAction(id, 'close', payload); }
  reopen(id, payload) { return this.postAction(id, 'reopen', payload); }
  withdraw(id, payload) { return this.postAction(id, 'withdraw', payload); }
  supplement(id, payload) { return this.postAction(id, 'supplement', payload); }
}

class PatientCreditsV2 extends FinancialV2Base {
  constructor() { super('patient_credits'); }
}

class AuditLogsV2 extends FinancialV2Base {
  constructor() { super('audit_logs'); }
  exportCsv(params) {
    return axios.get(`${this.url}/export_csv`, { params, responseType: 'blob' });
  }
}

class ReportsV2 extends ApiClient {
  constructor() { super('financial/v2/reports', { accountScoped: true }); }
  dre(params) { return axios.get(`${this.url}/dre`, { params }); }
  dreCategory(categoryId, params) {
    return axios.get(`${this.url}/dre/category/${categoryId}`, { params });
  }
  cashFlow(params) { return axios.get(`${this.url}/cash_flow`, { params }); }
  dashboard(params = {}) { return axios.get(`${this.url}/dashboard`, { params }); }
  // F-29: relatório de comissões agrupado por profissional.
  commissions(params) { return axios.get(`${this.url}/commissions`, { params }); }
  // F-30: relatórios extras.
  expensesByCategory(params) {
    return axios.get(`${this.url}/expenses_by_category`, { params });
  }
  expensesByCategoryDrilldown(categoryId, params) {
    // categoryId pode ser null → "Sem categoria"; envia "null" string.
    const segment = categoryId == null ? 'null' : categoryId;
    return axios.get(`${this.url}/expenses_by_category/category/${segment}`, { params });
  }
  ticketMedio(params) { return axios.get(`${this.url}/ticket_medio`, { params }); }
  convenio(params) { return axios.get(`${this.url}/convenio`, { params }); }
  // F-33: exportação para contador (CSVs por tipo)
  accountantExportPreview(params) {
    return axios.get(`${this.url}/accountant_export/preview`, { params });
  }
  accountantExport(params) {
    return axios.get(`${this.url}/accountant_export`, { params, responseType: 'blob' });
  }

  // Dashboard charts v2 — leem das tabelas Financial::* (alinhado com import
  // F-10). Os 3 primeiros aceitam `from`/`to` pra respeitar o period selector;
  // o aging é sempre snapshot atual (vencido = hoje).
  cashFlowChart(params)         { return axios.get(`${this.url}/cash_flow_chart`, { params }); }
  revenueComposition(params)    { return axios.get(`${this.url}/revenue_composition`, { params }); }
  delinquencyAging(params)      { return axios.get(`${this.url}/delinquency_aging`, { params }); }
  revenueByProfessional(params) { return axios.get(`${this.url}/revenue_by_professional`, { params }); }
  cashFlowProjection(params)    { return axios.get(`${this.url}/cash_flow_projection`, { params }); }
  delinquencyTrend(params)      { return axios.get(`${this.url}/delinquency_trend`, { params }); }

  // KPI sparklines (14 dias por padrão) — endpoint v2 nativo, lê de
  // Financial::Entry agregado por dia. Substituiu o /v1/financial/dashboard/kpis.
  dashboardKpis(params) {
    return axios.get(`${this.url}/kpi_sparklines`, { params });
  }

  // Top procedimentos no período (default mês corrente).
  topProcedures(params) {
    return axios.get(`${this.url}/top_procedures`, { params });
  }

  // Série mensal de receita vs meta (últimos N meses, default 12).
  revenueVsGoal(params) {
    return axios.get(`${this.url}/revenue_vs_goal`, { params });
  }

  // ── Hub Relatórios (5 endpoints novos, 2026-05-23) ──────────────────
  // Cada um delega num service `Financial::Reports::*Report` no backend.
  revenueByProcedure(params) {
    return axios.get(`${this.url}/revenue_by_procedure`, { params });
  }
  revenueByPaymentMethod(params) {
    return axios.get(`${this.url}/revenue_by_payment_method`, { params });
  }
  // Sufixo `Table` evita conflito com `revenueByProfessional` (chart do dashboard).
  revenueByProfessionalTable(params) {
    return axios.get(`${this.url}/revenue_by_professional_table`, { params });
  }
  accountStatement(params) {
    return axios.get(`${this.url}/account_statement`, { params });
  }
  goalsVsActual(params) {
    return axios.get(`${this.url}/goals_vs_actual`, { params });
  }
}

// Ações sobre lançamentos de comissão (read fica em ReportsV2.commissions).
class CommissionEntriesV2 extends ApiClient {
  constructor() {
    super('financial/v2/commission_entries', { accountScoped: true });
  }
  pay(id, payload = {}) {
    return axios.post(`${this.url}/${id}/pay`, payload, {
      headers: idempotentHeaders(),
    });
  }
  bulkPay(entryIds, payload = {}) {
    return axios.post(
      `${this.url}/bulk_pay`,
      { ...payload, entry_ids: entryIds },
      { headers: idempotentHeaders() },
    );
  }
}

// F-33 §parte 2 — workflow LGPD de anonimização de paciente.
class LgpdRequestsV2 extends FinancialV2Base {
  constructor() { super('lgpd_requests'); }
  approve(id, payload = {}) { return this.postAction(id, 'approve', payload); }
  reject(id, payload)       { return this.postAction(id, 'reject',  payload); }
  execute(id)               { return this.postAction(id, 'execute', {}); }
  cancel(id)                { return this.postAction(id, 'cancel',  {}); }
}

// F-32 — listagem + disparo manual de backup + delete.
class BackupsV2 extends ApiClient {
  constructor() { super('financial/v2/backups', { accountScoped: true }); }
  index() { return axios.get(this.url); }
  // Dispara CreateBackup imediatamente (síncrono no backend).
  run() {
    return axios.post(`${this.url}/run`, {}, {
      headers: idempotentHeaders(),
    });
  }
  // Apaga um backup (local + R2). filename precisa bater no pattern
  // klivy-YYYYMMDD-HHMMSS.sql.gz (validado no backend).
  destroyBackup(filename) {
    return axios.post(`${this.url}/destroy`, { filename }, {
      headers: idempotentHeaders(),
    });
  }
}

class SetupV2 extends ApiClient {
  constructor() { super('financial/v2/setup', { accountScoped: true }); }
  show() { return axios.get(this.url); }
  completeStep(step) {
    return axios.post(`${this.url}/complete_step`, { step }, { headers: idempotentHeaders() });
  }
}

// Endpoints "espelho" da aba financeira do paciente — retornam o mesmo shape
// que os endpoints legacy entregavam, mas alimentados pelos modelos v2.
// Permite repluggar a aba sem mudar UX (canon decisão 2026-05-08).
/**
 * ServicePricings — ponte 1-to-1 entre AgendaService (plugin agenda) e
 * Financial::ServicePricing (plugin financial). URL usa agenda_service_id
 * como :id (operador pensa "configurar preço do serviço X" não "pricing #N").
 *
 * Endpoints (Fase 2A):
 *   GET  /financial/v2/service_pricings              → lista AgendaServices + pricing (pode ser null)
 *   GET  /financial/v2/service_pricings/:id          → 1 serviço + pricing
 *   PUT  /financial/v2/service_pricings/:id          → upsert (cria ou atualiza)
 *   DELETE /financial/v2/service_pricings/:id        → inativa pricing (AgendaService permanece)
 */
class ServicePricingsV2 extends ApiClient {
  constructor() { super('financial/v2/service_pricings', { accountScoped: true }); }

  index() { return axios.get(this.url); }
  show(agendaServiceId) { return axios.get(`${this.url}/${agendaServiceId}`); }

  upsert(agendaServiceId, payload) {
    return axios.put(`${this.url}/${agendaServiceId}`, payload, {
      headers: idempotentHeaders(),
    });
  }

  deactivate(agendaServiceId) {
    return axios.delete(`${this.url}/${agendaServiceId}`, {
      headers: idempotentHeaders(),
    });
  }
}

/**
 * PaymentMethods — meios de pagamento da clínica (canon step 3).
 * CRUD básico do "rótulo" do método. Taxas vivem em PaymentMethodFees
 * (sub-rota nested) e são VERSIONADAS — nunca editar, sempre criar nova.
 */
class PaymentMethodsV2 extends FinancialV2Base {
  constructor() { super('payment_methods'); }

  // Rename de provedor — propaga alias em todos os métodos do mesmo
  // (account_id, provider). Body: { provider, provider_alias }.
  renameProvider(payload) {
    return axios.post(`${this.url}/rename_provider`, payload, {
      headers: idempotentHeaders(),
    });
  }

  // Bulk delete por provedor — soft-delete em todos os métodos do grupo
  // (apenas se nenhum tiver lançamentos). Backend retorna 422 se usado.
  destroyProvider(payload) {
    return axios.post(`${this.url}/destroy_provider`, payload, {
      headers: idempotentHeaders(),
    });
  }

  // F1 do PaymentPlanWizardV2 — preview de taxa vigente em (amount × installments × on_date).
  // Read-only. Sem Idempotency-Key. Pode ser chamado N vezes (frontend faz debounce).
  // params: { amount_cents, installments_count?, on_date? }
  simulateFee(id, params = {}) {
    return axios.get(`${this.url}/${id}/simulate_fee`, { params });
  }
}

class PaymentMethodFeesV2 {
  // Nested route /payment_methods/:payment_method_id/fees
  constructor() {
    this.base = paymentMethodId =>
      `/api/v1/accounts/${this.accountIdFromRoute()}/financial/v2/payment_methods/${paymentMethodId}/fees`;
  }

  accountIdFromRoute() {
    const isInsideAccountScopedURLs = window.location.pathname.includes('/app/accounts');
    return isInsideAccountScopedURLs ? window.location.pathname.split('/')[3] : '';
  }

  index(paymentMethodId, params = {}) {
    return axios.get(this.base(paymentMethodId), { params });
  }
  show(paymentMethodId, feeId) {
    return axios.get(`${this.base(paymentMethodId)}/${feeId}`);
  }
  create(paymentMethodId, payload) {
    return axios.post(this.base(paymentMethodId), payload, {
      headers: idempotentHeaders(),
    });
  }
  deactivate(paymentMethodId, feeId, payload = {}) {
    return axios.post(`${this.base(paymentMethodId)}/${feeId}/deactivate`, payload, {
      headers: idempotentHeaders(),
    });
  }
}

/**
 * AgentProfiles — extensão financeira de User (1-to-1).
 * Lista TODOS os Users da conta + profile financeiro (pode ser null).
 *
 * Endpoints (Fase 2A + stats Fase 2B-profissionais):
 *   GET    /financial/v2/agent_profiles?include_stats=true → [{ user, profile, stats? }]
 *   GET    /financial/v2/agent_profiles/:user_id
 *   PUT    /financial/v2/agent_profiles/:user_id  (upsert)
 *   DELETE /financial/v2/agent_profiles/:user_id  (deactivate, User permanece)
 */
class AgentProfilesV2 extends ApiClient {
  constructor() { super('financial/v2/agent_profiles', { accountScoped: true }); }

  index(params = {}) { return axios.get(this.url, { params }); }
  show(userId) { return axios.get(`${this.url}/${userId}`); }

  upsert(userId, payload) {
    return axios.put(`${this.url}/${userId}`, payload, {
      headers: idempotentHeaders(),
    });
  }

  deactivate(userId) {
    return axios.delete(`${this.url}/${userId}`, {
      headers: idempotentHeaders(),
    });
  }
}

class PatientFinancialV2 extends ApiClient {
  constructor() { super('financial/v2/patients', { accountScoped: true }); }

  summary(patientId) {
    return axios.get(`${this.url}/${patientId}/summary`);
  }

  timeline(patientId, params = {}) {
    return axios.get(`${this.url}/${patientId}/timeline`, { params });
  }
}

/**
 * RecurringBillings — mensalidades fixas de paciente (contrato recorrente).
 * Decisão 2026-05-28: separa do "tipo Mensalidade" do modal Novo Lançamento
 * (que era só uma label). Job daily gera Budget+Installment por período.
 *
 * Endpoints adicionais:
 *   POST /financial/v2/recurring_billings/:id/pause  — pausa geração
 *   POST /financial/v2/recurring_billings/:id/resume — retoma geração
 *   POST /financial/v2/recurring_billings/:id/cancel — encerra (preserva histórico)
 */
class RecurringBillingsV2 extends FinancialV2Base {
  constructor() { super('recurring_billings'); }

  pause(id, payload = {}) {
    return axios.post(`${this.url}/${id}/pause`, payload, { headers: idempotentHeaders() });
  }
  resume(id, payload = {}) {
    return axios.post(`${this.url}/${id}/resume`, payload, { headers: idempotentHeaders() });
  }
  cancel(id, payload = {}) {
    return axios.post(`${this.url}/${id}/cancel`, payload, { headers: idempotentHeaders() });
  }
}

export const FinancialV2 = {
  categories: new CategoriesV2(),
  bankAccounts: new BankAccountsV2(),
  commissionRules: new CommissionRulesV2(),
  recurringExpenses: new RecurringExpensesV2(),
  revenueGoals: new RevenueGoalsV2(),
  gatewaySetting: new GatewaySettingV2(),
  budgets: new BudgetsV2(),
  installments: new InstallmentsV2(),
  paymentReceipts: new PaymentReceiptsV2(),
  expenses: new ExpensesV2(),
  cashRegisters: new CashRegistersV2(),
  entries: new EntriesV2(),
  patientCredits: new PatientCreditsV2(),
  auditLogs: new AuditLogsV2(),
  reports: new ReportsV2(),
  commissionEntries: new CommissionEntriesV2(),
  lgpdRequests: new LgpdRequestsV2(),
  backups: new BackupsV2(),
  setup: new SetupV2(),
  patient: new PatientFinancialV2(),
  servicePricings: new ServicePricingsV2(),
  agentProfiles: new AgentProfilesV2(),
  paymentMethods: new PaymentMethodsV2(),
  paymentMethodFees: new PaymentMethodFeesV2(),
  recurringBillings: new RecurringBillingsV2(),
};

export default FinancialV2;
