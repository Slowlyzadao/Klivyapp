/**
 * useExportCsv — Composable de exportação CSV profissional
 *
 * Gera arquivos CSV com BOM UTF-8 (compatível com Excel/Google Sheets),
 * formatação monetária BR e estrutura adequada para relatórios contábeis.
 */

const BOM = '\uFEFF'; // UTF-8 BOM para compatibilidade com Excel/Sheets

function fmtBrl(val) {
  const n = parseFloat(val) || 0;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(n);
}

function fmtDate(d) {
  if (!d) return '—';
  const [y, m, day] = d.split('-');
  return `${day}/${m}/${y}`;
}

function fmtPct(val, total) {
  if (!total || total === 0) return '—';
  return `${((Math.abs(val) / Math.abs(total)) * 100).toFixed(1)}%`;
}

function escapeCell(val) {
  const str = String(val ?? '');
  // Cells containing commas, quotes or newlines must be quoted
  if (str.includes('"') || str.includes(',') || str.includes('\n')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function buildCsv(rows) {
  return BOM + rows.map(row => row.map(escapeCell).join(',')).join('\r\n');
}

function downloadCsv(content, filename) {
  const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.style.display = 'none';
  document.body.appendChild(a);
  a.click();
  setTimeout(() => {
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, 1000);
}

function todayLabel() {
  return new Date().toISOString().slice(0, 10);
}

// ── Exporters ──────────────────────────────────────────────────────────────────

/**
 * Fluxo de Caixa
 * @param {Array}  daily   - Array de { date, label, entradas, saidas, saldo }
 * @param {Object} totals  - { entradas, saidas, saldo }
 * @param {Array}  dateRange
 */
function exportCashFlowCsv(daily, totals, dateRange) {
  const period =
    dateRange && dateRange[0]
      ? `${fmtDate(dateRange[0])} a ${fmtDate(dateRange[1] || dateRange[0])}`
      : 'Mês atual';

  const rows = [
    ['RELATÓRIO FINANCEIRO — FLUXO DE CAIXA'],
    [`Período: ${period}`],
    [`Gerado em: ${fmtDate(todayLabel())}`],
    [],
    ['KPIs DO PERÍODO'],
    ['Total de Entradas', fmtBrl(totals?.entradas ?? 0)],
    ['Total de Saídas', fmtBrl(totals?.saidas ?? 0)],
    ['Saldo Líquido', fmtBrl(totals?.saldo ?? 0)],
    [
      'Margem Operacional',
      totals?.entradas
        ? `${(((totals.entradas - totals.saidas) / totals.entradas) * 100).toFixed(1)}%`
        : '—',
    ],
    [],
    ['DETALHAMENTO DIÁRIO'],
    [
      'Data',
      'Entradas (R$)',
      'Saídas (R$)',
      'Saldo do Dia (R$)',
      '% Entradas s/ Total',
      '% Saídas s/ Total',
    ],
  ];

  const totalEntradas = totals?.entradas || 1;
  const totalSaidas = totals?.saidas || 1;

  daily.forEach(d => {
    rows.push([
      d.label || fmtDate(d.date),
      fmtBrl(d.entradas),
      fmtBrl(d.saidas),
      fmtBrl(d.saldo),
      fmtPct(d.entradas, totalEntradas),
      fmtPct(d.saidas, totalSaidas),
    ]);
  });

  rows.push([]);
  rows.push([
    'TOTAL',
    fmtBrl(totals?.entradas ?? 0),
    fmtBrl(totals?.saidas ?? 0),
    fmtBrl(totals?.saldo ?? 0),
  ]);

  downloadCsv(buildCsv(rows), `fluxo-de-caixa_${todayLabel()}.csv`);
}

/**
 * A Receber
 * @param {Array}  transactions - lista de transações
 * @param {Object} meta         - { total_to_receive, total_received, total_overdue, total_count }
 * @param {Array}  dateRange
 */
function exportReceivablesCsv(transactions, meta, dateRange) {
  const period =
    dateRange && dateRange[0]
      ? `${fmtDate(dateRange[0])} a ${fmtDate(dateRange[1] || dateRange[0])}`
      : 'Período selecionado';

  const statusLabel = s => {
    if (s === 'received' || s === 'recebido') return 'Recebido';
    return 'Pendente';
  };

  const paymentLabel = {
    pix: 'PIX',
    dinheiro: 'Dinheiro',
    cartao_credito: 'Cartão de Crédito',
    cartao_debito: 'Cartão de Débito',
    transferencia: 'Transferência',
    boleto: 'Boleto',
    cheque: 'Cheque',
  };

  const rows = [
    ['RELATÓRIO FINANCEIRO — CONTAS A RECEBER'],
    [`Período: ${period}`],
    [`Gerado em: ${fmtDate(todayLabel())}`],
    [],
    ['KPIs'],
    ['Total a Receber (Pendente)', fmtBrl(meta?.total_to_receive ?? 0)],
    ['Total Recebido (Período)', fmtBrl(meta?.total_received ?? 0)],
    ['Total em Atraso', fmtBrl(meta?.total_overdue ?? 0)],
    ['Número de Transações', String(meta?.total_count ?? 0)],
    [
      'Taxa de Recebimento',
      meta?.total_received && meta?.total_amount
        ? `${((meta.total_received / meta.total_amount) * 100).toFixed(1)}%`
        : '—',
    ],
    [],
    ['LANÇAMENTOS DETALHADOS'],
    [
      '#',
      'Paciente',
      'Descrição',
      'Valor (R$)',
      'Vencimento',
      'Recebido em',
      'Forma de Pagamento',
      'Status',
    ],
  ];

  transactions.forEach((tx, i) => {
    rows.push([
      String(i + 1),
      tx.patient_name || 'Sem paciente vinculado',
      tx.description || '—',
      fmtBrl(tx.amount),
      fmtDate(tx.due_date),
      fmtDate(tx.received_at),
      paymentLabel[tx.payment_method] || tx.payment_method || '—',
      statusLabel(tx.status),
    ]);
  });

  rows.push([]);
  rows.push([
    'TOTAL LISTADO',
    '',
    '',
    fmtBrl(transactions.reduce((s, t) => s + parseFloat(t.amount || 0), 0)),
  ]);

  downloadCsv(buildCsv(rows), `a-receber_${todayLabel()}.csv`);
}

/**
 * A Pagar
 * @param {Array}  transactions
 * @param {Object} meta         - { total_amount, total_recurring, total_upcoming, count_upcoming, total_count }
 * @param {Array}  dateRange
 */
function exportPayablesCsv(transactions, meta, dateRange) {
  const period =
    dateRange && dateRange[0]
      ? `${fmtDate(dateRange[0])} a ${fmtDate(dateRange[1] || dateRange[0])}`
      : 'Período selecionado';

  const statusLabel = s => {
    if (s === 'paid' || s === 'pago') return 'Pago';
    return 'Pendente';
  };

  const rows = [
    ['RELATÓRIO FINANCEIRO — CONTAS A PAGAR'],
    [`Período: ${period}`],
    [`Gerado em: ${fmtDate(todayLabel())}`],
    [],
    ['KPIs'],
    ['Total a Pagar', fmtBrl(meta?.total_amount ?? 0)],
    ['Total Recorrente', fmtBrl(meta?.total_recurring ?? 0)],
    ['Próximos a Vencer (3 dias)', fmtBrl(meta?.total_upcoming ?? 0)],
    ['Qtd. Próximos a Vencer', String(meta?.count_upcoming ?? 0)],
    ['Total de Transações', String(meta?.total_count ?? 0)],
    [],
    ['LANÇAMENTOS DETALHADOS'],
    [
      '#',
      'Descrição',
      'Categoria',
      'Valor (R$)',
      'Vencimento',
      'Pago em',
      'Categoria',
      'Recorrente',
      'Status',
    ],
  ];

  transactions.forEach((tx, i) => {
    rows.push([
      String(i + 1),
      tx.description || '—',
      tx.category_name || '—',
      fmtBrl(tx.amount),
      fmtDate(tx.due_date),
      fmtDate(tx.paid_at),
      tx.category_name || '—',
      tx.is_recurring ? 'Sim' : 'Não',
      statusLabel(tx.status),
    ]);
  });

  rows.push([]);
  rows.push([
    'TOTAL LISTADO',
    '',
    '',
    fmtBrl(transactions.reduce((s, t) => s + parseFloat(t.amount || 0), 0)),
  ]);

  downloadCsv(buildCsv(rows), `a-pagar_${todayLabel()}.csv`);
}

/**
 * DRE — Demonstração do Resultado do Exercício
 * @param {Array}  dreRows   - linhas já computadas (inclui children)
 * @param {Object} dreData   - objeto raw da API (period, prior_period, current, prior)
 * @param {string} periodLabel
 * @param {string} priorLabel
 */
function exportDreCsv(dreRows, dreData, periodLabel, priorLabel) {
  const rows = [
    ['DEMONSTRAÇÃO DO RESULTADO DO EXERCÍCIO (DRE)'],
    [`Período Atual: ${periodLabel}`],
    [`Período Anterior: ${priorLabel}`],
    [`Gerado em: ${fmtDate(todayLabel())}`],
    [],
    ['INDICADORES PRINCIPAIS'],
  ];

  const cur = dreData?.current ?? {};

  rows.push(['Receita Bruta', fmtBrl(cur.receita_bruta ?? 0)]);
  rows.push(['Receita Líquida', fmtBrl(cur.receita_liq ?? 0)]);
  rows.push(['Margem Bruta', fmtBrl(cur.margem_bruta ?? 0)]);
  rows.push(['EBITDA', fmtBrl(cur.ebitda ?? 0)]);
  rows.push(['Lucro Líquido', fmtBrl(cur.lucro_liq ?? 0)]);

  if (cur.receita_bruta) {
    rows.push([
      'Margem Líquida',
      `${((cur.lucro_liq / cur.receita_bruta) * 100).toFixed(1)}%`,
    ]);
    rows.push([
      'Margem EBITDA',
      `${((cur.ebitda / cur.receita_bruta) * 100).toFixed(1)}%`,
    ]);
  }

  rows.push([]);
  rows.push(['DETALHAMENTO COMPLETO']);
  rows.push([
    'Descrição',
    'Subcategoria',
    'Período Atual (R$)',
    'Período Anterior (R$)',
    'Variação %',
    'Tipo',
  ]);

  dreRows.forEach(row => {
    const varPct =
      row.priorVal && row.priorVal !== 0
        ? `${(((row.currentVal - row.priorVal) / Math.abs(row.priorVal)) * 100).toFixed(1)}%`
        : '—';

    rows.push([
      row.label,
      '',
      fmtBrl(Math.abs(row.currentVal)),
      fmtBrl(Math.abs(row.priorVal)),
      varPct,
      row.isResult ? 'Resultado' : 'Seção',
    ]);

    (row.children || []).forEach(child => {
      const childVar =
        child.priorVal && child.priorVal !== 0
          ? `${(((child.currentVal - child.priorVal) / Math.abs(child.priorVal)) * 100).toFixed(1)}%`
          : '—';
      rows.push([
        '',
        child.label,
        fmtBrl(Math.abs(child.currentVal)),
        fmtBrl(Math.abs(child.priorVal)),
        childVar,
        'Categoria',
      ]);
    });
  });

  downloadCsv(buildCsv(rows), `dre_${todayLabel()}.csv`);
}

/**
 * Relatórios (aba ativa passada como parâmetro)
 * @param {string} tab       - 'commissions' | 'expenses' | 'insurance' | 'ticket'
 * @param {Object} reportData - dados da aba
 * @param {Object} params     - filtros aplicados
 */
function exportReportsCsv(tab, reportData, params) {
  let rows = [];
  let filename = `relatorio_${tab}_${todayLabel()}.csv`;

  if (tab === 'commissions') {
    const data = reportData || {};
    rows = [
      ['RELATÓRIO DE COMISSÕES POR PROFISSIONAL'],
      [`Profissional: ${data.professional_name || '—'}`],
      [`Período: ${params?.period || '—'}`],
      [`Gerado em: ${fmtDate(todayLabel())}`],
      [],
      ['RESUMO'],
      ['Total de Transações', String(data.transaction_count ?? 0)],
      ['Total de Comissão', fmtBrl(data.total_commission ?? 0)],
      [],
      ['DETALHAMENTO DE TRANSAÇÕES'],
      [
        '#',
        'Descrição',
        'Categoria',
        'Data Recebimento',
        'Valor Original (R$)',
        'Comissão (R$)',
        'Tipo de Regra',
      ],
    ];

    (data.transactions || []).forEach((tx, i) => {
      rows.push([
        String(i + 1),
        tx.description || '—',
        tx.category_name || '—',
        fmtDate(tx.received_at),
        fmtBrl(tx.original_amount ?? tx.amount),
        fmtBrl(tx.commission_amount),
        tx.rule_type || '—',
      ]);
    });

    rows.push([]);
    rows.push([
      'TOTAL DE COMISSÃO',
      '',
      '',
      '',
      '',
      fmtBrl(data.total_commission ?? 0),
    ]);
    filename = `comissoes_${todayLabel()}.csv`;
  } else if (tab === 'expenses') {
    const items = reportData || [];
    const total = items.reduce((s, r) => s + parseFloat(r.amount || 0), 0);

    rows = [
      ['RELATÓRIO DE DESPESAS POR CATEGORIA'],
      [`Gerado em: ${fmtDate(todayLabel())}`],
      [],
      ['KPIs'],
      ['Total de Despesas', fmtBrl(total)],
      ['Número de Categorias', String(items.length)],
      [],
      ['DETALHAMENTO POR CATEGORIA'],
      ['#', 'Categoria', 'Tipo de Custo', 'Total (R$)', '% do Total'],
    ];

    items.forEach((r, i) => {
      rows.push([
        String(i + 1),
        r.category_name || 'Sem categoria',
        r.cost_type || '—',
        fmtBrl(r.amount),
        fmtPct(r.amount, total),
      ]);
    });

    rows.push([]);
    rows.push(['TOTAL', '', '', fmtBrl(total), '100%']);
    filename = `despesas-por-categoria_${todayLabel()}.csv`;
  } else if (tab === 'insurance') {
    const items = reportData || [];
    const total = items.reduce((s, r) => s + parseFloat(r.amount || 0), 0);

    rows = [
      ['RELATÓRIO DE FATURAMENTO POR CONVÊNIO / ORIGEM'],
      [`Gerado em: ${fmtDate(todayLabel())}`],
      [],
      ['KPIs'],
      ['Faturamento Total', fmtBrl(total)],
      ['Número de Origens', String(items.length)],
      [],
      ['RANKING POR CONVÊNIO'],
      [
        'Posição',
        'Convênio / Origem',
        'Nº Transações',
        'Faturamento (R$)',
        '% do Total',
      ],
    ];

    items.forEach((r, i) => {
      rows.push([
        String(i + 1),
        r.label || '—',
        String(r.count ?? 0),
        fmtBrl(r.amount),
        fmtPct(r.amount, total),
      ]);
    });

    rows.push([]);
    rows.push(['TOTAL', '', '', fmtBrl(total), '100%']);
    filename = `faturamento-por-convenio_${todayLabel()}.csv`;
  } else if (tab === 'ticket') {
    const items = reportData?.items || [];

    rows = [
      ['RELATÓRIO DE TICKET MÉDIO'],
      [
        `Agrupamento: ${params?.groupBy === 'month' ? 'Por Mês' : 'Por Profissional'}`,
      ],
      [`Gerado em: ${fmtDate(todayLabel())}`],
      [],
      ['KPIs'],
      ['Ticket Médio Geral', fmtBrl(reportData?.overall?.avg_ticket ?? 0)],
      ['Total de Transações', String(reportData?.overall?.count ?? 0)],
      ['Faturamento Total', fmtBrl(reportData?.overall?.total ?? 0)],
      [],
      ['DETALHAMENTO'],
      [
        '#',
        'Agrupamento',
        'Nº Transações',
        'Ticket Médio (R$)',
        'Faturamento Total (R$)',
      ],
    ];

    items.forEach((r, i) => {
      rows.push([
        String(i + 1),
        r.label || '—',
        String(r.count ?? 0),
        fmtBrl(r.avg_ticket),
        fmtBrl(r.total),
      ]);
    });

    filename = `ticket-medio_${todayLabel()}.csv`;
  }

  if (rows.length > 0) {
    downloadCsv(buildCsv(rows), filename);
  }
}

export function useExportCsv() {
  return {
    exportCashFlowCsv,
    exportReceivablesCsv,
    exportPayablesCsv,
    exportDreCsv,
    exportReportsCsv,
  };
}

export default useExportCsv;
