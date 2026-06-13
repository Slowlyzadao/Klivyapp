import { ref, computed } from 'vue';
import AnamnesisAPI from '@plugins/patients/frontend/api/patients/anamnesis';

/**
 * usePatientClinicalGuards — verifica se um procedimento/produto colide com
 * alergias, contraindicações ou medicações registradas na anamnese ativa.
 *
 * Roadmap #16: trava clínica (não bloqueia, exige override). Hoje a proteção
 * é puramente frontend; backend audit do override fica como follow-up.
 *
 * Uso:
 *   const { ensureLoaded, checkProcedureForConflicts } = usePatientClinicalGuards(patientId);
 *   await ensureLoaded();
 *   const conflicts = checkProcedureForConflicts({
 *     procedureName: 'Aplicação de Toxina + Lidocaína',
 *     productName: 'Lidocaína 2%',
 *   });
 *   // conflicts: [{ kind, term, severity, source, label }]
 */
export function usePatientClinicalGuards(patientId) {
  const currentAnamnesis = ref(null);
  const isLoaded = ref(false);
  const isLoading = ref(false);

  // Normaliza string para matching: lowercase + remove acentos + colapsa espaços.
  // Crítico para PT-BR ("Lidocaína" === "lidocaina").
  const normalize = str => {
    if (!str) return '';
    return String(str)
      .toLowerCase()
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
  };

  // Extrai a "palavra-chave" comparável de um item de anamnese.
  // Aceita string pura OU objeto { name, substance, ... } — o controller
  // permite ambos e a UI já manda objetos com `.name`.
  const extractTerm = item => {
    if (!item) return '';
    if (typeof item === 'string') return item;
    return item.name || item.substance || '';
  };

  const ensureLoaded = async () => {
    if (isLoaded.value || !patientId) return;
    isLoading.value = true;
    try {
      const response = await AnamnesisAPI.get(patientId);
      const list = response.data?.payload || response.data || [];
      currentAnamnesis.value = list[0] || null;
      isLoaded.value = true;
    } catch (error) {
      // Falha ao carregar anamnese não deve bloquear procedimento — só
      // remove a proteção. Logamos para investigação.
      // eslint-disable-next-line no-console
      console.error('[ClinicalGuards] Falha ao carregar anamnese', error);
      currentAnamnesis.value = null;
      isLoaded.value = true;
    } finally {
      isLoading.value = false;
    }
  };

  const hasAnamnesis = computed(() => !!currentAnamnesis.value?.id);

  /**
   * Retorna lista de conflitos clínicos detectados ao cruzar inputs (nome
   * de procedimento e produto) com alergias/contraindicações/medicações.
   *
   * Estratégia de match: contains literal após normalização. Não tenta
   * inferir sinônimos (ex: "Latex" não casa com "luva esterilizada").
   * Falsos positivos baixos > falsos negativos altos para dados clínicos.
   */
  const checkProcedureForConflicts = ({ procedureName = '', productName = '' } = {}) => {
    if (!hasAnamnesis.value) return [];

    const haystack = [normalize(procedureName), normalize(productName)]
      .filter(Boolean)
      .join(' || ');
    if (!haystack) return [];

    const conflicts = [];
    const a = currentAnamnesis.value;

    (a.allergies || []).forEach(item => {
      const term = extractTerm(item);
      if (!term) return;
      const needle = normalize(term);
      if (needle && haystack.includes(needle)) {
        conflicts.push({
          kind: 'allergy',
          term,
          severity: (typeof item === 'object' && item?.severity) || 'unknown',
          source: 'allergies',
          label: `Alergia a ${term}`,
          details: typeof item === 'object' ? item.reaction || item.description : null,
        });
      }
    });

    (a.contraindications || []).forEach(item => {
      const term = extractTerm(item);
      if (!term) return;
      const needle = normalize(term);
      if (needle && haystack.includes(needle)) {
        conflicts.push({
          kind: 'contraindication',
          term,
          severity: 'high',
          source: 'contraindications',
          label: `Contraindicação: ${term}`,
          details: typeof item === 'object' ? item.description || item.details : null,
        });
      }
    });

    (a.current_medications || []).forEach(item => {
      const term = extractTerm(item);
      if (!term) return;
      const needle = normalize(term);
      // Medicações com flag `interaction_risk` ou `alert` recebem prioridade.
      const flagged =
        typeof item === 'object' && (item.interaction_risk || item.alert);
      if (needle && haystack.includes(needle) && flagged) {
        conflicts.push({
          kind: 'medication',
          term,
          severity: 'medium',
          source: 'current_medications',
          label: `Medicação em uso: ${term}`,
          details: typeof item === 'object' ? item.dosage || item.frequency : null,
        });
      }
    });

    return conflicts;
  };

  return {
    currentAnamnesis,
    isLoaded,
    isLoading,
    hasAnamnesis,
    ensureLoaded,
    checkProcedureForConflicts,
  };
}
