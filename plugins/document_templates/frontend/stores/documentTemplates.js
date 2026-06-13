// Store Pinia do plugin document_templates.
//
// Mantém em memória:
//   - templates da clínica (lista),
//   - templates Klivy globais (biblioteca),
//   - pastas,
//   - catálogo de variáveis (cacheado após primeiro fetch).
//
// As actions são async/await e propagam erros pro chamador — o componente
// decide se mostra toast, modal ou inline. Loading flags individuais por
// área (templates, folders, klivy) pra UI poder skeletons independentes.

import { defineStore } from 'pinia';
import { documentTemplatesApi }         from '../api/documentTemplates';
import { documentTemplateFoldersApi }   from '../api/documentTemplateFolders';
import { documentTemplateVariablesApi } from '../api/documentTemplateVariables';

export const useDocumentTemplatesStore = defineStore('documentTemplates', {
  state: () => ({
    templates: [],
    klivyLibrary: [],
    folders: [],
    variables: [],
    variablesLoaded: false,
    loading: {
      templates: false,
      folders: false,
      klivy: false,
      variables: false,
    },
    error: null,
    selectedFolderId: null,
    selectedDocumentType: null,
  }),

  getters: {
    templatesByFolder: (s) => (folderId) =>
      s.templates.filter(t => t.folder_id === folderId),

    templatesByType: (s) => (type) =>
      s.templates.filter(t => t.document_type === type),

    rootFolders: (s) => s.folders.filter(f => !f.parent_id),

    variablesByCategory: (s) => {
      const grouped = {};
      s.variables.forEach(v => {
        grouped[v.category] ??= [];
        grouped[v.category].push(v);
      });
      return grouped;
    },

    findTemplate: (s) => (id) => s.templates.find(t => t.id === Number(id)),
  },

  actions: {
    // ── Templates ─────────────────────────────────────────────────────────
    async fetchTemplates(params = {}) {
      this.loading.templates = true;
      this.error = null;
      try {
        const { data } = await documentTemplatesApi.list(params);
        this.templates = data.data;
      } catch (e) {
        this.error = e.message;
        throw e;
      } finally {
        this.loading.templates = false;
      }
    },

    async fetchKlivyLibrary(params = {}) {
      this.loading.klivy = true;
      try {
        const { data } = await documentTemplatesApi.klivyLibrary(params);
        this.klivyLibrary = data.data;
      } finally {
        this.loading.klivy = false;
      }
    },

    async fetchTemplate(id) {
      const { data } = await documentTemplatesApi.show(id);
      return data.data;
    },

    // Mapa { chave: valor } das variáveis resolvidas pra um paciente real —
    // alimenta o preview ao vivo do editor. professionalId opcional (resolve
    // professional.* pro profissional escolhido; default = usuário logado).
    async fetchPreviewValues(patientId, professionalId) {
      const { data } = await documentTemplatesApi.previewValues(patientId, professionalId);
      return data.data;
    },

    async createTemplate(payload) {
      const { data } = await documentTemplatesApi.create(payload);
      this.templates = [data.data, ...this.templates];
      return data.data;
    },

    async updateTemplate(id, payload) {
      const { data } = await documentTemplatesApi.update(id, payload);
      const idx = this.templates.findIndex(t => t.id === id);
      if (idx >= 0) this.templates.splice(idx, 1, data.data);
      return data.data;
    },

    // "Excluir" = hard delete. Remove da lista no sucesso. Se o backend
    // retornar 422 (has_dependents), o axios lança e o chamador trata
    // mostrando a mensagem amigável — a lista NÃO é alterada.
    async deleteTemplate(id) {
      await documentTemplatesApi.destroy(id);
      this.templates = this.templates.filter(t => t.id !== id);
    },

    async duplicateTemplate(id) {
      const { data } = await documentTemplatesApi.duplicate(id);
      this.templates = [data.data, ...this.templates];
      return data.data;
    },

    async cloneKlivyTemplate(id, { folderId } = {}) {
      const { data } = await documentTemplatesApi.cloneToAccount(id, { folderId });
      this.templates = [data.data, ...this.templates];
      return data.data;
    },

    async archiveTemplate(id) {
      const { data } = await documentTemplatesApi.archive(id);
      const idx = this.templates.findIndex(t => t.id === id);
      if (idx >= 0) this.templates.splice(idx, 1, data.data);
      return data.data;
    },

    async unarchiveTemplate(id) {
      const { data } = await documentTemplatesApi.unarchive(id);
      const idx = this.templates.findIndex(t => t.id === id);
      if (idx >= 0) this.templates.splice(idx, 1, data.data);
      return data.data;
    },

    // ── Folders ───────────────────────────────────────────────────────────
    async fetchFolders() {
      this.loading.folders = true;
      try {
        const { data } = await documentTemplateFoldersApi.list();
        this.folders = data.data;
      } finally {
        this.loading.folders = false;
      }
    },

    async createFolder(payload) {
      const { data } = await documentTemplateFoldersApi.create(payload);
      this.folders = [...this.folders, data.data];
      return data.data;
    },

    async updateFolder(id, payload) {
      const { data } = await documentTemplateFoldersApi.update(id, payload);
      const idx = this.folders.findIndex(f => f.id === id);
      if (idx >= 0) this.folders.splice(idx, 1, data.data);
      return data.data;
    },

    async deleteFolder(id) {
      await documentTemplateFoldersApi.destroy(id);
      this.folders = this.folders.filter(f => f.id !== id);
    },

    // ── Variáveis (catálogo cacheado em memória) ──────────────────────────
    async ensureVariables() {
      if (this.variablesLoaded) return this.variables;

      this.loading.variables = true;
      try {
        const { data } = await documentTemplateVariablesApi.fetch();
        this.variables = data.data;
        this.variablesLoaded = true;
      } finally {
        this.loading.variables = false;
      }
      return this.variables;
    },

    // ── Filtros locais ────────────────────────────────────────────────────
    selectFolder(folderId) {
      this.selectedFolderId = folderId;
    },

    selectDocumentType(type) {
      this.selectedDocumentType = type;
    },
  },
});
