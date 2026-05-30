// Acesso ergonômico ao catálogo de variáveis disponíveis pra inserção no
// template. Garante que o catálogo foi carregado e expõe agrupamentos
// úteis pra UI (menu por categoria, busca por label).

import { computed, onMounted } from 'vue';
import { storeToRefs } from 'pinia';
import { useDocumentTemplatesStore } from '../stores/documentTemplates';

export function useVariableCatalog() {
  const store = useDocumentTemplatesStore();
  const { variables, variablesByCategory, variablesLoaded } = storeToRefs(store);

  const ensure = () => store.ensureVariables();

  onMounted(ensure);

  const search = (query) => {
    const q = String(query || '').trim().toLowerCase();
    if (q.length === 0) return variables.value;

    return variables.value.filter(v =>
      v.label.toLowerCase().includes(q) ||
      v.key.toLowerCase().includes(q) ||
      (v.example && v.example.toLowerCase().includes(q))
    );
  };

  return {
    variables,
    variablesByCategory,
    loaded: variablesLoaded,
    ensure,
    search,
    findByKey: (key) => variables.value.find(v => v.key === key),
    categories: computed(() => Object.keys(variablesByCategory.value)),
  };
}
