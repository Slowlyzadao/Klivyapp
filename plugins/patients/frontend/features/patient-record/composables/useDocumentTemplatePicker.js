/**
 * useDocumentTemplatePicker — alimenta o seletor "Gerar a partir de um modelo"
 * das abas Documentos (family: 'clinical') e Consentimentos (family: 'consent').
 *
 * Busca os modelos da biblioteca (clínica + Klivy globais), expõe a lista, o
 * estado de loading e um helper `options` já no formato do FormSelect, com uma
 * opção "Nenhum" no topo pra voltar ao preenchimento manual. Best-effort: se a
 * busca falhar (ex.: sem permissão), a lista fica vazia e o seletor some — o
 * fluxo manual continua intacto.
 */

import { ref, computed } from 'vue';
import DocumentTemplatesAPI from '@plugins/patients/frontend/api/patients/documentTemplates';

export function useDocumentTemplatePicker(family) {
  const templates = ref([]);
  const isLoading = ref(false);
  const loaded = ref(false);

  const fetchTemplates = async ({ force = false } = {}) => {
    if (loaded.value && !force) return templates.value;
    isLoading.value = true;
    try {
      const res = await DocumentTemplatesAPI.list({ family });
      const list = res.data?.data || res.data || [];
      // Só modelos ativos entram no seletor — rascunhos podem ter conteúdo
      // incompleto e gerariam um PDF quebrado.
      templates.value = list.filter(tpl => !tpl.status || tpl.status === 'active');
      loaded.value = true;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[DocumentTemplatePicker] Falha ao carregar modelos', error);
      templates.value = [];
    } finally {
      isLoading.value = false;
    }
    return templates.value;
  };

  const findTemplate = id => templates.value.find(tpl => tpl.id === id) || null;

  // Opções do FormSelect. `noneLabel` é o rótulo da opção "voltar ao manual".
  const buildOptions = noneLabel => [
    { value: '', label: noneLabel },
    ...templates.value.map(tpl => ({
      value: tpl.id,
      label: tpl.is_klivy ? `${tpl.name} · Klivy` : tpl.name,
    })),
  ];

  const hasTemplates = computed(() => templates.value.length > 0);

  return {
    templates,
    isLoading,
    loaded,
    hasTemplates,
    fetchTemplates,
    findTemplate,
    buildOptions,
  };
}
