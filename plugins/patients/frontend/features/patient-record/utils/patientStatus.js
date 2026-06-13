export const PATIENT_STATUS_LABELS = {
  novo: 'Novo',
  ativo: 'Ativo',
  inativo: 'Inativo',
  faltoso: 'Faltoso',
  alta: 'Alta',
  arquivado: 'Arquivado',
};

const PATIENT_STATUS_COLORS = {
  novo: '#2563eb',
  ativo: '#10b981',
  inativo: '#64748b',
  faltoso: '#f59e0b',
  alta: '#7c3aed',
  arquivado: '#475569',
};

export const PATIENT_STATUS_OPTIONS = Object.entries(PATIENT_STATUS_LABELS).map(
  ([value, label]) => ({ value, label, color: PATIENT_STATUS_COLORS[value] })
);
