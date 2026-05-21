/**
 * usePhoneContactSearch — busca debounced em paralelo
 *   • Pacientes existentes (PatientsAPI.get com search) — detecção de duplicatas
 *   • Contatos do chat (Chatwoot ContactAPI.search)
 *
 * Filtra fora o paciente atualmente aberto (excludeId) para não sugerir ele
 * mesmo. Usa Promise.allSettled — uma falha não derruba a outra.
 */

import { ref } from 'vue';
import ContactAPI from 'dashboard/api/contacts';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';

export function usePhoneContactSearch({ excludeId } = {}) {
  const phoneContactResults = ref([]);
  const phonePatientResults = ref([]);
  const phoneContactSearching = ref(false);
  const phoneContactDropdown = ref(false);
  const phoneContactSkipSearch = ref(false);
  let phoneContactTimeout = null;

  const resolveExclude = () =>
    typeof excludeId === 'function'
      ? excludeId()
      : excludeId?.value ?? excludeId;

  const search = rawDigits => {
    if (phoneContactSkipSearch.value) {
      phoneContactSkipSearch.value = false;
      return;
    }
    clearTimeout(phoneContactTimeout);

    if (!rawDigits || rawDigits.length < 3) {
      phoneContactResults.value = [];
      phonePatientResults.value = [];
      phoneContactDropdown.value = false;
      return;
    }

    phoneContactDropdown.value = true;
    phoneContactSearching.value = true;
    phoneContactTimeout = setTimeout(async () => {
      try {
        const [contactResp, patientResp] = await Promise.allSettled([
          ContactAPI.search(rawDigits),
          PatientsAPI.get({ page: 1, perPage: 25, search: rawDigits }),
        ]);
        phoneContactResults.value =
          contactResp.status === 'fulfilled'
            ? contactResp.value.data?.payload || []
            : [];
        const currentId = resolveExclude();
        phonePatientResults.value =
          patientResp.status === 'fulfilled'
            ? (patientResp.value.data?.payload || []).filter(
                p => p.id !== currentId
              )
            : [];
      } finally {
        phoneContactSearching.value = false;
      }
    }, 400);
  };

  const reset = () => {
    phoneContactResults.value = [];
    phonePatientResults.value = [];
    phoneContactDropdown.value = false;
  };

  // Marca skip pra próxima busca — usado quando o caller seleciona um item
  // (não dispara nova busca após gravar o telefone selecionado).
  const skipNext = () => {
    phoneContactSkipSearch.value = true;
  };

  return {
    phoneContactResults,
    phonePatientResults,
    phoneContactSearching,
    phoneContactDropdown,
    search,
    reset,
    skipNext,
  };
}
