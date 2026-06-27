import AiAgentTraining from '@plugins/ai_agent/frontend/api/training';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Estados em que o job ainda está rodando — usados pra controlar o polling
// de status na aba enquanto o pipeline processa.
export const PROCESSING_STATUSES = [
  'pending',
  'extracting',
  'transcribing',
  'extracting_faq',
];

const initialState = () => ({
  records: [],
  // total no servidor (lista pagina de 25 em 25; records guarda só o carregado).
  meta: { totalCount: 0, page: 1 },
  uiFlags: {
    isFetching: false,
    isFetchingMore: false,
    isCreating: false,
    isDeleting: false,
    isPublishing: false,
    isApproving: false,
  },
});

const state = initialState();

const getters = {
  getRecords: $state => $state.records,
  getMeta: $state => $state.meta,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await AiAgentTraining.get(1);
      commit('SET_RECORDS', data.payload);
      commit('SET_META', data.meta);
      return data.payload;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  // "Carregar mais": próxima página, anexada ao que já está na tela.
  fetchMore: async ({ commit, state: $state }) => {
    commit('SET_UI_FLAG', { isFetchingMore: true });
    try {
      const { data } = await AiAgentTraining.get(($state.meta.page || 1) + 1);
      commit('APPEND_RECORDS', data.payload);
      commit('SET_META', data.meta);
      return data.payload;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetchingMore: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await AiAgentTraining.create(payload);
      commit('ADD_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  // Upload em massa robusto (pra centenas/milhares): fila com concorrência
  // LIMITADA (não dispara tudo de uma vez) + RETRY por arquivo (nenhum fica
  // de fora) + progresso. Ao final faz UM fetch (não inflar a lista com N
  // ADD_RECORD). Retorna { done, failed } pra UI reportar/retentar.
  bulkCreate: async ({ dispatch }, { files, onProgress }) => {
    const CONCURRENCY = 3; // gentil com o servidor (3 por vez, não N)
    const MAX_RETRIES = 2;
    const queue = [...files];
    let done = 0;
    const failed = [];
    const report = () =>
      onProgress &&
      onProgress({ done, failed: failed.length, total: files.length });

    const worker = async () => {
      while (queue.length) {
        const file = queue.shift();
        let ok = false;
        for (let attempt = 0; attempt <= MAX_RETRIES && !ok; attempt += 1) {
          try {
            // eslint-disable-next-line no-await-in-loop
            await AiAgentTraining.create({ zipFile: file });
            ok = true;
          } catch (error) {
            // backoff progressivo antes de retentar
            // eslint-disable-next-line no-await-in-loop
            await new Promise(resolve => {
              setTimeout(resolve, 1500 * (attempt + 1));
            });
          }
        }
        if (ok) done += 1;
        else failed.push(file);
        report();
      }
    };

    report();
    await Promise.all(
      Array.from({ length: Math.min(CONCURRENCY, files.length) }, worker)
    );
    await dispatch('fetch');
    return { done, failed };
  },

  // Re-busca 1 registro (polling enquanto o job processa).
  refresh: async ({ commit }, id) => {
    try {
      const response = await AiAgentTraining.show(id);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    }
  },

  delete: async ({ commit }, { id, mode }) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentTraining.delete(id, mode);
      commit('REMOVE_RECORD', id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },

  // Lista todas as FAQs sugeridas pendentes (de todas as conversas) pra revisão.
  fetchPendingFaqs: async () => {
    try {
      const response = await AiAgentTraining.pendingFaqs();
      return response.data.payload;
    } catch (error) {
      return throwErrorMessage(error);
    }
  },

  // Aprova em massa as FAQs selecionadas; re-busca pra refletir published_at.
  approveAll: async ({ commit, dispatch }, { ids }) => {
    commit('SET_UI_FLAG', { isApproving: true });
    try {
      await AiAgentTraining.approveAll(ids);
      await dispatch('fetch');
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isApproving: false });
    }
    return true;
  },

  // Apaga todas as conversas visíveis de uma vez; re-busca pra refletir o estado.
  deleteAll: async ({ commit, dispatch }, { mode }) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentTraining.deleteAll(mode);
      await dispatch('fetch');
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
    return true;
  },

  // Aprova as FAQs mantidas e publica no RAG da Bea.
  publish: async ({ commit }, { id, faqs }) => {
    commit('SET_UI_FLAG', { isPublishing: true });
    try {
      const response = await AiAgentTraining.publish(id, faqs);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isPublishing: false });
    }
  },

  // Define qual participante é a clínica e dispara o processamento.
  selectClinic: async ({ commit }, { id, clinicSenderName }) => {
    try {
      const response = await AiAgentTraining.selectClinic(id, clinicSenderName);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    }
  },

  // Aplica a clínica detectada a todas as conversas em awaiting_clinic de uma
  // vez. Re-busca a lista (vários status mudam pra pending → polling assume).
  selectClinicBulk: async ({ dispatch }, { clinicSenderName }) => {
    try {
      const response = await AiAgentTraining.selectClinicBulk(clinicSenderName);
      await dispatch('fetch');
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    }
  },

  // MT-19 — defesa em profundidade pra account-switch: evita que uploads de
  // uma clínica vazem visualmente pra outra caso a navegação vire SPA.
  reset: ({ commit }) => commit('RESET'),
};

const mutations = {
  SET_UI_FLAG($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
  SET_RECORDS($state, records) {
    $state.records = records;
  },
  SET_META($state, meta) {
    $state.meta = { totalCount: meta.total_count, page: meta.page };
  },
  APPEND_RECORDS($state, records) {
    const seen = new Set($state.records.map(r => r.id));
    $state.records.push(...records.filter(r => !seen.has(r.id)));
  },
  ADD_RECORD($state, record) {
    $state.records.unshift(record);
  },
  REPLACE_RECORD($state, record) {
    const idx = $state.records.findIndex(r => r.id === record.id);
    if (idx !== -1) $state.records.splice(idx, 1, record);
  },
  REMOVE_RECORD($state, id) {
    $state.records = $state.records.filter(r => r.id !== id);
  },
  RESET($state) {
    Object.assign($state, initialState());
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
