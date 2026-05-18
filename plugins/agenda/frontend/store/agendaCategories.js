import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from 'dashboard/store/mutation-types';
import CategoriesAPI from '@plugins/agenda/frontend/api/agendaCategories';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  allCategories(_state) {
    return _state.records;
  },
  activeCategories(_state) {
    return _state.records.filter(c => c.active !== false);
  },
  getCategoryById: _state => id => {
    return _state.records.find(c => c.id === id);
  },
};

export const actions = {
  fetch: async function fetchCategories({ commit }) {
    commit(types.SET_AGENDA_CATEGORY_UI_FLAG, { isFetching: true });
    try {
      const response = await CategoriesAPI.get();
      commit(types.SET_AGENDA_CATEGORIES, response.data);
    } catch (error) {
      // Ignore silently
    } finally {
      commit(types.SET_AGENDA_CATEGORY_UI_FLAG, { isFetching: false });
    }
  },

  create: async function createCategory({ commit }, categoryData) {
    commit(types.SET_AGENDA_CATEGORY_UI_FLAG, { isCreating: true });
    try {
      const response = await CategoriesAPI.create({
        agenda_category: categoryData,
      });
      commit(types.ADD_AGENDA_CATEGORY, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_CATEGORY_UI_FLAG, { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...updateData }) => {
    commit(types.SET_AGENDA_CATEGORY_UI_FLAG, { isUpdating: true });
    try {
      const response = await CategoriesAPI.update(id, {
        agenda_category: updateData,
      });
      commit(types.EDIT_AGENDA_CATEGORY, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_CATEGORY_UI_FLAG, { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit(types.SET_AGENDA_CATEGORY_UI_FLAG, { isDeleting: true });
    try {
      await CategoriesAPI.delete(id);
      commit(types.DELETE_AGENDA_CATEGORY, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_CATEGORY_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_AGENDA_CATEGORY_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.ADD_AGENDA_CATEGORY]: MutationHelpers.create,
  [types.SET_AGENDA_CATEGORIES]: MutationHelpers.set,
  [types.EDIT_AGENDA_CATEGORY]: MutationHelpers.update,
  [types.DELETE_AGENDA_CATEGORY]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
