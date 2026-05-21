/* global axios */

/**
 * Downloads a financial PDF report using axios (sends auth headers automatically),
 * then triggers a browser download via a temporary object URL.
 *
 * @param {string} endpoint  - e.g. 'cash_flow', 'receivables', 'dre'
 * @param {Object} params    - Query parameters to send
 */
export async function downloadFinancialPdf(endpoint, params = {}) {
  const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
  if (!accountId) return;

  // Strip undefined/null values so they don't appear as "undefined" in the URL
  const cleanParams = Object.fromEntries(
    Object.entries(params).filter(
      ([, v]) => v != null && v !== '' && v !== 'undefined'
    )
  );

  try {
    const response = await axios.get(
      `/api/v1/accounts/${accountId}/financial/pdfs/${endpoint}`,
      { params: cleanParams, responseType: 'blob' }
    );

    const blob = new Blob([response.data], { type: 'application/pdf' });
    const url = URL.createObjectURL(blob);

    // Allow the user to preview the PDF in a new tab
    window.open(url, '_blank');

    // Revoke the object URL after a short delay to allow the new tab to load it
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[PDF] Erro ao gerar relatório:', err);
  }
}

// `downloadTransactionReceipt` removido em 2026-05-11 (Fase A da depreciação v1).
// Apontava pra rota v1 (`/patients/:id/transactions/:tx/receipt`) servida pelo
// `Patients::ReceiptPdfGenerator` legacy. PDF generator equivalente em cima de
// `Financial::PaymentReceipt` (v2) ainda não foi implementado — TODO separado.

export default { downloadFinancialPdf };
