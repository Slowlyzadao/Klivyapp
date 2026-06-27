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

function buildFormData({
  accountId, kind, source, file, files,
  dentistMapping, bankAccountStrategy, bankAccountId, paymentMethodMapping,
  specialtyMapping,
}) {
  const fd = new FormData();
  fd.append('account_id', accountId);
  fd.append('kind', kind);
  if (source) fd.append('source', source);

  if (kind === 'patients' && files) {
    if (files.patients) fd.append('csv_patients', files.patients);
    if (files.patientAnamnesis) fd.append('csv_patient_anamnesis', files.patientAnamnesis);
    if (files.anamnesis) fd.append('csv_anamnesis', files.anamnesis);
  } else if (kind === 'treatment_operations' && files) {
    if (files.operations) fd.append('csv_operations', files.operations);
    // Mapping vai como JSON string — FormData não tem nested params nativos.
    // Backend aceita ambos (raw Hash do Rails ou JSON string).
    if (dentistMapping) fd.append('dentist_mapping', JSON.stringify(dentistMapping));
  } else if (kind === 'financial' && files) {
    if (files.budgets) fd.append('csv_budgets', files.budgets);
    if (files.paymentHeaders) fd.append('csv_payment_headers', files.paymentHeaders);
    if (files.paymentItems) fd.append('csv_payment_items', files.paymentItems);
    if (dentistMapping) fd.append('dentist_mapping', JSON.stringify(dentistMapping));
    if (bankAccountStrategy) fd.append('bank_account_strategy', bankAccountStrategy);
    if (bankAccountId) fd.append('bank_account_id', bankAccountId);
    if (paymentMethodMapping) fd.append('payment_method_mapping', JSON.stringify(paymentMethodMapping));
    if (specialtyMapping) fd.append('specialty_mapping', JSON.stringify(specialtyMapping));
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

// Lista de usuários da conta (com klivy_role.name) pra montar a tela de
// mapeamento "DentistName" → user_id no fluxo de TreatmentOperation.
export function fetchProfessionalUsers(accountId) {
  return jsonRequest(`/super_admin/migrations/professional_users.json?account_id=${accountId}`);
}

// Lista PaymentMethods (kind+name+provider) e BankAccounts ativos da conta —
// usado no F-10 Financeiro pra mapear "kind Clinicorp → PaymentMethod Klivy"
// + escolher conta bancária específica entre várias ativas.
export function fetchFinancialSettings(accountId) {
  return jsonRequest(`/super_admin/migrations/payment_methods.json?account_id=${accountId}`);
}
