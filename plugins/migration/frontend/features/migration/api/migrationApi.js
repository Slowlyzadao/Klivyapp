// Lightweight fetch wrapper for the SuperAdmin Migration endpoints.
// Uses the same-origin Devise super_admin session — no Authorization header.

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content || '';
}

async function jsonRequest(url, options = {}) {
  const res = await fetch(url, {
    credentials: 'same-origin',
    headers: {
      Accept: 'application/json',
      'X-CSRF-Token': csrfToken(),
      ...(options.headers || {}),
    },
    ...options,
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) {
    const err = new Error(data?.error || `HTTP ${res.status}`);
    err.status = res.status;
    err.payload = data;
    throw err;
  }
  return data;
}

export function fetchIndex() {
  return jsonRequest('/super_admin/migrations.json');
}

export function fetchRun(id) {
  return jsonRequest(`/super_admin/migrations/${id}.json`);
}

function buildFormData({ accountId, kind, source, file, files }) {
  const fd = new FormData();
  fd.append('account_id', accountId);
  fd.append('kind', kind);
  if (source) fd.append('source', source);

  if (kind === 'patients' && files) {
    if (files.patients) fd.append('csv_patients', files.patients);
    if (files.patientAnamnesis) fd.append('csv_patient_anamnesis', files.patientAnamnesis);
    if (files.anamnesis) fd.append('csv_anamnesis', files.anamnesis);
  } else if (file) {
    fd.append('csv', file);
  }
  return fd;
}

// kind=patients: aceita até 3 arquivos (Patient + PatientAnamnesis + Anamnesis).
// outros kinds: arquivo único via campo `csv`.
export function uploadCsv(payload) {
  return jsonRequest('/super_admin/migrations', { method: 'POST', body: buildFormData(payload) });
}

// Read-only preview — runs same parse/match logic as upload, but returns a
// summary (would_create / would_update / would_skip) and a sample of rows
// without touching the database.
export function previewCsv(payload) {
  return jsonRequest('/super_admin/migrations/preview', { method: 'POST', body: buildFormData(payload) });
}
