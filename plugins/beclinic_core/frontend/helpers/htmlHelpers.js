// HTML helpers for BeClinic plugins.
// Use sparingly — Vue's template binding already escapes by default. These
// helpers are for the rare cases where we hand-build HTML strings (e.g.
// print-preview iframes, srcdoc generation) and must defend against XSS from
// patient-controlled fields like names, descriptions, etc.

// Escape the 5 HTML special characters (&, <, >, ", ').
// Returns '' for null/undefined.
export const escapeHtml = value => {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
};
