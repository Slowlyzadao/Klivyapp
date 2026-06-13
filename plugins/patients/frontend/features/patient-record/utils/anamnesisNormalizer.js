/**
 * anamnesisNormalizer — shape canônico + normalização do JSON do servidor.
 *
 * Extraído de AnamnesisTab.vue (Roadmap #11). Resolve dois problemas:
 *   1. Anamnese pode chegar incompleta do backend (campos jsonb opcionais)
 *      — o `EMPTY_ANAMNESIS` define o shape default e o merge mantém os
 *      v-models reativos sem `undefined`.
 *   2. `applyAnamnesisState` muta in-place em vez de substituir o ref —
 *      preserva a reatividade dos v-models aninhados (medical_history.x,
 *      relevant_habits.y) após o fetch.
 */

export const EMPTY_ANAMNESIS = () => ({
  id: null,
  specialty: 'Odontologia Geral',
  chief_complaint: '',
  medical_history: {
    hypertension: false,
    diabetes: false,
    bleeding_disorder: false,
    pregnant: false,
    oncology: false,
    hepatitis: false,
    other: '',
    has_recent_surgeries: false,
    has_implants: false,
    has_anesthesia_complications: false,
  },
  allergies: [],
  current_medications: [],
  contraindications: [],
  surgical_history: '',
  family_history: '',
  relevant_habits: {
    smoker: 'Não',
    alcohol: 'Não consome',
    sports: 'Sedentário',
  },
  pregnancy: {},
  additional_notes: '',
  status: 'draft',
});

// JSON round-trip: safe com Vue Proxies (structuredClone falha em Proxies);
// dados da anamnese são 100% JSON-seguros (sem Date/Map/Set).
export const deepCloneAnamnesis = value => JSON.parse(JSON.stringify(value));

export const normalizeAnamnesisFromServer = remote => {
  const base = EMPTY_ANAMNESIS();
  const clone = deepCloneAnamnesis(remote || {});
  return {
    ...base,
    ...clone,
    medical_history: {
      ...base.medical_history,
      ...(clone.medical_history ?? {}),
    },
    relevant_habits: {
      ...base.relevant_habits,
      ...(clone.relevant_habits ?? {}),
    },
    pregnancy: { ...base.pregnancy, ...(clone.pregnancy ?? {}) },
    allergies: Array.isArray(clone.allergies) ? clone.allergies : [],
    current_medications: Array.isArray(clone.current_medications)
      ? clone.current_medications
      : [],
    contraindications: Array.isArray(clone.contraindications)
      ? clone.contraindications
      : [],
  };
};

// Aplica o estado de forma cirúrgica: muta propriedades in-place em vez de
// substituir o Ref inteiro. Preserva a reatividade dos v-models aninhados.
//
// `defaults` é usado APENAS quando `source` é null (anamnese nova) — permite
// pré-preencher campos a partir do perfil da clínica (ex.: specialty default).
export const applyAnamnesisState = (target, source, defaults = {}) => {
  const normalized = source
    ? normalizeAnamnesisFromServer(source)
    : EMPTY_ANAMNESIS();

  if (!source && defaults.specialty) {
    normalized.specialty = defaults.specialty;
  }

  // campos escalares no root
  [
    'id',
    'specialty',
    'chief_complaint',
    'surgical_history',
    'family_history',
    'additional_notes',
    'status',
    'version_number',
    'finalized_at',
    'pdf_url',
    'updated_at',
  ].forEach(key => {
    target[key] = normalized[key] ?? (key === 'id' ? null : '');
  });

  // hashes aninhados — mutar in-place
  Object.keys(target.medical_history).forEach(key => {
    target.medical_history[key] = normalized.medical_history[key] ?? false;
  });
  Object.keys(normalized.medical_history).forEach(key => {
    target.medical_history[key] = normalized.medical_history[key];
  });

  Object.keys(target.relevant_habits).forEach(key => {
    target.relevant_habits[key] =
      normalized.relevant_habits[key] ?? target.relevant_habits[key];
  });

  target.pregnancy = { ...normalized.pregnancy };

  // arrays — substituir referência (Vue reage bem a substituição de array)
  target.allergies = Array.isArray(normalized.allergies)
    ? [...normalized.allergies]
    : [];
  target.current_medications = Array.isArray(normalized.current_medications)
    ? [...normalized.current_medications]
    : [];
  target.contraindications = Array.isArray(normalized.contraindications)
    ? [...normalized.contraindications]
    : [];
};
