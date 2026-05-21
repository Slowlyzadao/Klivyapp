/**
 * Template HTML do Extrato Financeiro do paciente (impressão via window.print).
 *
 * Fonte única de dados: o array `entries` da timeline v2
 * (`useFinancialTimeline`) — exatamente o mesmo que alimenta o
 * `FinancialTimeline.vue` na aba do paciente. Antes da migração v2 esta
 * função consumia `transactions[]` + `estimates[]` do `useFinancialData`,
 * mas esses arrays passaram a ser refs vazios após a Fase A (2026-05-11);
 * o extrato impresso então passou a exibir "Nenhuma transação" mesmo com
 * lançamentos visíveis no card da timeline. Refatorado em 2026-05-12 pra
 * eliminar essa divergência: tela e impressão lêem da MESMA estrutura.
 */

import { escapeHtml } from '@plugins/beclinic_core/frontend/helpers/htmlHelpers';
import {
  BRT,
  txStatusConfig,
  PAYMENT_METHOD_BADGE_LABELS,
} from '@plugins/patients/frontend/constants/financial';
import { formatCurrency } from './financialFormatters';

const todayBR = () =>
  new Date().toLocaleDateString('pt-BR', { timeZone: BRT });

const dateBR = dateStr => {
  if (!dateStr) return '—';
  // due_date / paid_at vêm como 'YYYY-MM-DD' — fixar 12:00 evita drift de fuso.
  const iso = dateStr.length === 10 ? `${dateStr}T12:00:00` : dateStr;
  return new Date(iso).toLocaleDateString('pt-BR', { timeZone: BRT });
};

// Paleta semântica de status — mesma da timeline (Badge component).
// Hex direto para garantir impressão correta independente de tokens CSS.
const STATUS_PALETTE = {
  pago: { bg: '#d1fae5', fg: '#065f46' },
  vencido: { bg: '#fee2e2', fg: '#991b1b' },
  reembolsado: { bg: '#ede9fe', fg: '#6d28d9' },
  cancelado: { bg: '#f1f5f9', fg: '#64748b' },
  pendente: { bg: '#fef3c7', fg: '#b45309' },
  parcial: { bg: '#dbeafe', fg: '#1e40af' },
  rascunho: { bg: '#f1f5f9', fg: '#64748b' },
  enviado: { bg: '#dbeafe', fg: '#1e40af' },
  aprovado: { bg: '#d1fae5', fg: '#065f46' },
};

// Paleta para o tipo (recurrence_type) — coerente com a timeline.
// `plano_tratamento` veio na Fase A (entries com `origin.kind=treatment_plan`).
const RECURRENCE_PALETTE = {
  avulso: { bg: '#f1f5f9', fg: '#475569', label: 'Avulso' },
  parcelamento: { bg: '#dbeafe', fg: '#1e40af', label: 'Parcelamento' },
  mensalidade: { bg: '#ede9fe', fg: '#6d28d9', label: 'Mensalidade' },
  plano_tratamento: { bg: '#ecfeff', fg: '#0e7490', label: 'Plano de Tratamento' },
};

// Labels textuais (uppercase) por status do entry/installment, alinhados ao
// `TX_STATUS_CONFIG.label`. `parcial`/`rascunho`/`enviado`/`aprovado` ficam
// fora do `txStatusConfig` default em alguns lugares; centraliza aqui pra
// garantir que o badge no PDF nunca caia em label "EM ABERTO" genérico.
const STATUS_LABELS = {
  pago: 'PAGO',
  pendente: 'EM ABERTO',
  vencido: 'VENCIDO',
  cancelado: 'CANCELADO',
  reembolsado: 'ESTORNADO',
  parcial: 'PARCIAL',
  rascunho: 'RASCUNHO',
  enviado: 'ENVIADO',
  aprovado: 'APROVADO',
};

const statusPalette = status =>
  STATUS_PALETTE[status] || { bg: '#f1f5f9', fg: '#334155' };

const statusLabel = status =>
  STATUS_LABELS[status] || txStatusConfig(status).label || '—';

const methodLabel = method =>
  PAYMENT_METHOD_BADGE_LABELS[method] || method || '—';

const renderBadge = (text, palette) =>
  `<span style="padding:2px 8px;border-radius:20px;font-size:10px;font-weight:600;background:${palette.bg};color:${palette.fg};white-space:nowrap">${escapeHtml(
    text
  )}</span>`;

const renderTypeBadge = recurrenceType => {
  if (!recurrenceType) return '—';
  const palette = RECURRENCE_PALETTE[recurrenceType];
  if (!palette) return '—';
  return renderBadge(palette.label, palette);
};

const renderStatusBadge = status =>
  renderBadge(statusLabel(status), statusPalette(status));

// Identificador "humano" do entry, prioriza `display_id` (preservado da
// migração legacy → v2 em metadata.legacy_id) sobre o `id` interno do
// Financial::Budget. Mesma regra do `derive_origin_label` no backend.
const entryRefLabel = entry => {
  const ref = entry.display_id ?? entry.id;
  return ref != null ? `#${ref}` : '—';
};

// Para a linha de Transações: contextualiza qual orçamento gerou a parcela.
// Ex.: "Orçamento #38 — Parcela 3/12" ou "Plano de Tratamento #4 — Parcela 1/1".
// Sem o contexto do entry, várias parcelas com mesma descrição ficariam
// indistinguíveis na impressão (regressão visual vs tela).
const installmentDescription = (entry, inst) => {
  const ctx = entry.origin?.label || entry.description || entryRefLabel(entry);
  const part = `Parcela ${inst.number ?? 1}/${inst.total ?? 1}`;
  return `${ctx} — ${part}`;
};

// Conta de parcelas para a coluna "Parcelas" da seção de orçamentos.
// Reusa exatamente o que `InstallmentProgress.vue` exibe na tela ("7/14 pagas").
const installmentsSummary = entry => {
  const total = entry.progress?.total ?? (entry.installments?.length || 0);
  const paid = entry.progress?.paid ?? 0;
  return `${paid}/${total}`;
};

export const buildExtratoHtml = ({
  patient,
  summary,
  entries = [],
  accountName = 'Klivy',
}) => {
  const name = escapeHtml(patient?.name || 'Paciente');
  const headerName = escapeHtml(accountName);
  const today = todayBR();

  // ── Linhas de Transações ──
  // Achata `entries[].installments[]` mantendo a referência ao entry pai
  // pra montar a descrição contextual e o badge de Tipo. Ordena por
  // due_date asc dentro de cada entry (espelha a ordem da timeline:
  // `installments.order(:due_date, :number)` no PatientTimelinesController).
  const txRows = entries
    .flatMap(entry =>
      (entry.installments || []).map(inst => ({ entry, inst }))
    )
    .map(({ entry, inst }) => {
      const sBadge = renderStatusBadge(inst.status);
      return `<tr>
      <td>${dateBR(inst.due_date)}</td>
      <td>${escapeHtml(installmentDescription(entry, inst))}</td>
      <td>${renderTypeBadge(entry.recurrence_type)}</td>
      <td style="text-align:center;font-variant-numeric:tabular-nums">${inst.number ?? 1}/${inst.total ?? 1}</td>
      <td style="font-weight:600;font-variant-numeric:tabular-nums">${formatCurrency(inst.amount)}</td>
      <td>${escapeHtml(methodLabel(inst.payment_method))}</td>
      <td>${sBadge}</td>
    </tr>`;
    })
    .join('');

  // ── Linhas de Orçamentos / Lançamentos ──
  // Uma linha por entry da timeline (Budget agregado). Espelha visualmente
  // o card-pai da timeline: id, data, tipo, total, recebido, em aberto,
  // contagem de parcelas e status agregado.
  const estRows = entries
    .map(entry => {
      const sBadge = renderStatusBadge(entry.status);
      return `<tr>
      <td>${escapeHtml(entryRefLabel(entry))}</td>
      <td>${dateBR(entry.date)}</td>
      <td>${renderTypeBadge(entry.recurrence_type)}</td>
      <td style="font-weight:600;font-variant-numeric:tabular-nums">${formatCurrency(entry.total)}</td>
      <td style="color:#059669;font-variant-numeric:tabular-nums">${formatCurrency(entry.paid)}</td>
      <td style="color:#b45309;font-variant-numeric:tabular-nums">${formatCurrency(entry.open)}</td>
      <td style="font-variant-numeric:tabular-nums">${installmentsSummary(entry)}</td>
      <td>${sBadge}</td>
    </tr>`;
    })
    .join('');

  return `<!DOCTYPE html>
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
    .kpi-hint { font-size: 10px; color: #94a3b8; margin-top: 2px; }
    .kpi-value { font-size: 20px; font-weight: 700; font-variant-numeric: tabular-nums; }
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
      <div class="clinic-name">${headerName}</div>
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
      <div class="kpi-value">${formatCurrency(summary?.total_approved)}</div>
      <div class="kpi-hint">Plano principal</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Pago / Recebido</div>
      <div class="kpi-value green">${formatCurrency(summary?.total_paid)}</div>
      <div class="kpi-hint">Atualizado</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Em Aberto / Devedor</div>
      <div class="kpi-value red">${formatCurrency(summary?.total_open)}</div>
      <div class="kpi-hint">${summary?.total_overdue > 0 ? `Vencido: ${formatCurrency(summary.total_overdue)}` : 'Tudo em dia'}</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Crédito do Paciente</div>
      <div class="kpi-value blue">${formatCurrency(summary?.credit_balance)}</div>
      <div class="kpi-hint">Saldo de estornos</div>
    </div>
  </div>

  <h2>Transações / Extrato</h2>
  <table>
    <thead><tr><th>Vencimento</th><th>Descrição</th><th>Tipo</th><th>Parcela</th><th>Valor</th><th>Método</th><th>Status</th></tr></thead>
    <tbody>${txRows || '<tr><td colspan="7" style="text-align:center;color:#94a3b8;padding:16px">Nenhuma transação</td></tr>'}</tbody>
  </table>

  <h2>Orçamentos e Lançamentos</h2>
  <table>
    <thead><tr><th>#</th><th>Data</th><th>Tipo</th><th>Total</th><th>Recebido</th><th>Em Aberto</th><th>Parcelas</th><th>Status</th></tr></thead>
    <tbody>${estRows || '<tr><td colspan="8" style="text-align:center;color:#94a3b8;padding:16px">Nenhum lançamento</td></tr>'}</tbody>
  </table>

  <div class="footer">${headerName} — Documento gerado automaticamente em ${today}</div>
</body>
</html>`;
};
