/**
 * Template HTML da Ficha Clínica do paciente (impressão via PrintPreviewModal).
 *
 * Mesmo padrão usado no Extrato Financeiro (`financialPrintTemplates.js`):
 * gera string HTML auto-contida, renderizada num <iframe srcdoc> para isolar
 * a impressão do app inteiro (sidebar/header do Chatwoot não vazam).
 */

import { escapeHtml } from '@plugins/beclinic_core/frontend/helpers/htmlHelpers';

const BRT = 'America/Sao_Paulo';

const todayBR = () =>
  new Date().toLocaleDateString('pt-BR', { timeZone: BRT });

const dateBR = iso => {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('pt-BR', { timeZone: BRT });
};

const STATUS_LABEL = {
  signed: 'Assinada',
  draft: 'Rascunho',
  erratum: 'Errata',
};

const STATUS_STYLE = {
  signed: { bg: '#dbeafe', fg: '#1d4ed8' },
  draft: { bg: '#fef3c7', fg: '#b45309' },
  erratum: { bg: '#fee2e2', fg: '#b91c1c' },
};

const fieldRow = (label, value) => {
  if (value === null || value === undefined || value === '') return '';
  return `<dt>${escapeHtml(label)}</dt><dd>${escapeHtml(String(value))}</dd>`;
};

export const buildClinicalRecordHtml = ({
  patient,
  sessions = [],
  accountName = 'Klivy',
}) => {
  const name = escapeHtml(patient?.name || 'Paciente');
  const headerName = escapeHtml(accountName);
  const today = todayBR();

  const sortedSessions = [...sessions].sort(
    (a, b) => new Date(b.performed_at) - new Date(a.performed_at)
  );

  const sessionBlocks = sortedSessions
    .map(s => {
      const isErratum = !!s.erratum_at;
      const statusKey = isErratum
        ? 'erratum'
        : s.status === 'signed'
          ? 'signed'
          : 'draft';
      const { bg, fg } = STATUS_STYLE[statusKey];

      const fields = [
        fieldRow('Queixa do dia', s.complaint_of_day),
        fieldRow('Avaliação', s.assessment),
        fieldRow('Intercorrências', s.complications),
        fieldRow('Resultado imediato', s.result_observed),
        fieldRow('Próxima consulta', s.next_consultation_details),
        fieldRow('Observação', s.observation),
        s.return_in_days
          ? fieldRow('Retorno', `em ${s.return_in_days} dias`)
          : '',
      ].join('');

      const erratum =
        isErratum && s.erratum_reason
          ? `<div class="erratum"><strong>Errata:</strong> ${escapeHtml(s.erratum_reason)}</div>`
          : '';

      return `<article class="session">
        <header>
          <div class="session-meta">
            <span class="session-date">${dateBR(s.performed_at)}</span>
            <span class="session-professional">${escapeHtml(s.professional_name || '—')}</span>
          </div>
          <span class="status" style="background:${bg};color:${fg}">${escapeHtml(STATUS_LABEL[statusKey])}</span>
        </header>
        <h3 class="procedure">${escapeHtml(s.procedure_name || '—')}</h3>
        ${fields ? `<dl class="fields">${fields}</dl>` : '<p class="empty">Sem campos clínicos preenchidos.</p>'}
        ${erratum}
      </article>`;
    })
    .join('');

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Ficha Clínica — ${name}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 13px; color: #1e293b; background: #fff; padding: 32px; }
    .header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #0f172a; padding-bottom: 16px; margin-bottom: 24px; }
    .clinic-name { font-size: 20px; font-weight: 700; color: #0f172a; }
    .clinic-sub { font-size: 12px; color: #64748b; margin-top: 2px; }
    .patient-name { font-size: 18px; font-weight: 600; text-align: right; }
    .patient-meta { font-size: 12px; color: #64748b; text-align: right; }
    h2.section { font-size: 14px; font-weight: 600; color: #0f172a; margin: 0 0 12px; text-transform: uppercase; letter-spacing: .05em; }
    .session { border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px 16px; margin-bottom: 12px; break-inside: avoid; page-break-inside: avoid; }
    .session header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
    .session-meta { display: flex; gap: 12px; align-items: center; }
    .session-date { font-size: 12px; color: #64748b; font-weight: 600; }
    .session-professional { font-size: 12px; color: #475569; }
    .status { padding: 2px 10px; border-radius: 99px; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; }
    .procedure { font-size: 15px; font-weight: 600; color: #0f172a; margin: 4px 0 10px; }
    dl.fields { display: grid; grid-template-columns: 160px 1fr; gap: 4px 12px; font-size: 12px; }
    dl.fields dt { color: #64748b; font-weight: 600; }
    dl.fields dd { color: #1e293b; white-space: pre-wrap; }
    .empty { font-size: 12px; color: #94a3b8; font-style: italic; }
    .erratum { margin-top: 10px; padding: 8px 10px; background: #fee2e2; color: #991b1b; border-left: 3px solid #b91c1c; border-radius: 4px; font-size: 12px; }
    .empty-state { text-align: center; padding: 48px 16px; color: #94a3b8; font-style: italic; }
    .footer { margin-top: 32px; border-top: 1px solid #e2e8f0; padding-top: 12px; font-size: 11px; color: #94a3b8; text-align: center; }
    @media print { body { padding: 16px; } }
  </style>
</head>
<body>
  <div class="header">
    <div>
      <div class="clinic-name">${headerName}</div>
      <div class="clinic-sub">Ficha Clínica do Paciente</div>
    </div>
    <div>
      <div class="patient-name">${name}</div>
      <div class="patient-meta">Emitido em ${today}</div>
    </div>
  </div>

  <h2 class="section">Histórico Clínico (${sortedSessions.length})</h2>
  ${sessionBlocks || '<div class="empty-state">Nenhum atendimento registrado.</div>'}

  <div class="footer">${headerName} — Documento gerado em ${today}</div>
</body>
</html>`;
};
