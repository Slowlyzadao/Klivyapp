<script setup>
// Tela principal do plugin document_templates. Compõe header (com tabs +
// viewToggle + busca + filtro), sidebar de pastas e coleção de templates
// (grid ou list).
//
// State local:
//   • activeTab — 'owned' | 'klivy'  (Meus / Biblioteca Klivy)
//   • viewMode — 'grid' | 'list'    (visualização da coleção)
//
// Lógica de fetch/mutate vive no store Pinia. Aqui só cola: filtros +
// handlers + abertura de modais/rotas.

import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { storeToRefs } from 'pinia';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useDocumentTemplatesStore } from '../../stores/documentTemplates';

import DocumentsHeader from '../../components/index/DocumentsHeader.vue';
import FolderSidebar from '../../components/index/FolderSidebar.vue';
import TemplateGrid from '../../components/index/TemplateGrid.vue';
import TemplateList from '../../components/index/TemplateList.vue';
import TemplateContextMenu from '../../components/index/TemplateContextMenu.vue';
import NewFolderModal from '../../components/modals/NewFolderModal.vue';
import NewTemplateModal from '../../components/modals/NewTemplateModal.vue';
import ConfirmDialog from '../../components/modals/ConfirmDialog.vue';
import { useConfirm } from '../../composables/useDialogs';

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const currentUser = useMapGetter('getCurrentUser');
const isAdmin = computed(() => currentUser.value?.role === 'administrator');

const store = useDocumentTemplatesStore();
const {
  templates,
  klivyLibrary,
  folders,
  loading,
  selectedFolderId,
} = storeToRefs(store);

// Diálogos do design system (substituem window.confirm).
const { confirmState, confirm, onConfirm, onCancel } = useConfirm();

// ── Estado local ────────────────────────────────────────────────────────
// Abas:
//   owned → só modelos da clínica (exclui Klivy globais)
//   all   → tudo (modelos da clínica + Klivy globais)
//   klivy → só a Biblioteca Klivy (modelos globais read-only)
const activeTab = ref('owned');      // 'owned' | 'all' | 'klivy'
const viewMode = ref('grid');        // 'grid' | 'list'
const search = ref('');
const documentTypeFilter = ref('');
const showNewFolderModal = ref(false);
const showNewTemplateModal = ref(false);
const contextMenu = ref({ template: null, anchor: null });

// ── Listas-base por origem ────────────────────────────────────────────────
// `templates` (store) vem de for_account = modelos da clínica + Klivy globais.
// "Meus modelos" = só os da clínica (is_klivy=false). "Todos" = a lista cheia.
const ownedTemplates = computed(() => templates.value.filter(t => !t.is_klivy));

const isArchived = (t) => t.status === 'archived';

// Seleção 'archived' na sidebar → view de arquivados (separada das pastas).
const isArchivedView = computed(() => selectedFolderId.value === 'archived');

// ── Filtros (busca + tipo + pasta) ──────────────────────────────────────
const applyFilters = (list, { folder = false } = {}) => {
  let filtered = list;
  if (folder && selectedFolderId.value !== null && selectedFolderId.value !== 'archived') {
    filtered = filtered.filter(t => t.folder_id === selectedFolderId.value);
  }
  if (documentTypeFilter.value) {
    filtered = filtered.filter(t => t.document_type === documentTypeFilter.value);
  }
  if (search.value.trim()) {
    const q = search.value.trim().toLowerCase();
    filtered = filtered.filter(t =>
      t.name.toLowerCase().includes(q) ||
      (t.description && t.description.toLowerCase().includes(q))
    );
  }
  return filtered;
};

// Klivy → biblioteca global (nunca arquivada). owned/all → respeita a view:
// arquivados mostra só status=archived (sem filtro de pasta); senão só os
// não-arquivados, filtrados por pasta.
const currentList = computed(() => {
  if (activeTab.value === 'klivy') return applyFilters(klivyLibrary.value);

  const base = activeTab.value === 'all' ? templates.value : ownedTemplates.value;
  if (isArchivedView.value) {
    return applyFilters(base.filter(isArchived));
  }
  return applyFilters(base.filter(t => !isArchived(t)), { folder: true });
});

const currentLoading = computed(() =>
  activeTab.value === 'klivy' ? loading.value.klivy : loading.value.templates,
);

const emptyTitle = computed(() => {
  if (isArchivedView.value) return t('DOCUMENT_TEMPLATES.INDEX.EMPTY_ARCHIVED_TITLE');
  return activeTab.value === 'klivy'
    ? t('DOCUMENT_TEMPLATES.INDEX.EMPTY_KLIVY_TITLE')
    : t('DOCUMENT_TEMPLATES.INDEX.EMPTY_TITLE');
});

const emptyDescription = computed(() => {
  if (isArchivedView.value) return t('DOCUMENT_TEMPLATES.INDEX.EMPTY_ARCHIVED_DESCRIPTION');
  return activeTab.value === 'klivy'
    ? t('DOCUMENT_TEMPLATES.INDEX.EMPTY_KLIVY_DESCRIPTION')
    : t('DOCUMENT_TEMPLATES.INDEX.EMPTY_DESCRIPTION');
});

// Variant do card: na aba Klivy é sempre 'klivy'; em owned/all, cada card
// decide pelo próprio is_klivy (um Klivy dentro de "Todos" mostra badge Klivy).
const gridVariant = computed(() => (activeTab.value === 'klivy' ? 'klivy' : 'owned'));

// Sidebar de pastas aparece em owned/all (não em klivy).
const showSidebar = computed(() => activeTab.value !== 'klivy');

// ── Counts (excluem arquivados) ─────────────────────────────────────────
const ownedCount = computed(() =>
  ownedTemplates.value.filter(t => !isArchived(t)).length,
);
const allCount = computed(() =>
  templates.value.filter(t => !isArchived(t)).length,
);
const archivedCount = computed(() =>
  ownedTemplates.value.filter(isArchived).length,
);

// ── Navegação / handlers ────────────────────────────────────────────────
const openEditor = (template) => {
  router.push({
    name: 'documents_dashboard_edit',
    params: { accountId: accountId.value, id: template.id },
  });
};

// Click em card → abre o editor. Se for um modelo Klivy (read-only), o
// editor faz clone-on-edit: cria a cópia na clínica só quando o user
// realmente edita. Evita clones acidentais por mera visualização.
const handleOpen = (template) => {
  openEditor(template);
};

const openNewTemplate = () => {
  if (!isAdmin.value) {
    useAlert(t('DOCUMENT_TEMPLATES.ERRORS.ADMIN_ONLY'));
    return;
  }
  showNewTemplateModal.value = true;
};

const openNewFolder = () => {
  if (!isAdmin.value) {
    useAlert(t('DOCUMENT_TEMPLATES.ERRORS.ADMIN_ONLY'));
    return;
  }
  showNewFolderModal.value = true;
};

const handleTemplateMenu = ({ template, anchor }) => {
  contextMenu.value = { template, anchor };
};

const closeContextMenu = () => {
  contextMenu.value = { template: null, anchor: null };
};

// Drag-and-drop: TemplateCard arrastado e solto sobre uma FolderItem.
const handleDropTemplate = async ({ templateId, folderId }) => {
  const template = templates.value.find(t => t.id === templateId);
  if (!template) return;
  if (template.folder_id === folderId) return;

  try {
    await store.updateTemplate(templateId, { folder_id: folderId });
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.MOVED'));
  } catch (e) {
    useAlert(e.response?.data?.errors?.join(', ') || e.message);
  }
};

const handleDuplicate = async template => {
  try {
    const copy = await store.duplicateTemplate(template.id);
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.DUPLICATED', { name: copy.name }));
  } catch (e) {
    useAlert(e.response?.data?.errors?.join(', ') || e.message);
  }
};

const handleArchive = async template => {
  try {
    await store.archiveTemplate(template.id);
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.ARCHIVED', { name: template.name }));
  } catch (e) {
    useAlert(e.response?.data?.errors?.join(', ') || e.message);
  }
};

const handleUnarchive = async template => {
  try {
    await store.unarchiveTemplate(template.id);
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.UNARCHIVED', { name: template.name }));
  } catch (e) {
    useAlert(e.response?.data?.errors?.join(', ') || e.message);
  }
};

const handleDelete = async template => {
  const ok = await confirm({
    title: t('DOCUMENT_TEMPLATES.CONTEXT_MENU.DELETE_TITLE'),
    message: t('DOCUMENT_TEMPLATES.CONTEXT_MENU.CONFIRM_DELETE', { name: template.name }),
    confirmLabel: t('DOCUMENT_TEMPLATES.CONTEXT_MENU.DELETE'),
    cancelLabel: t('DOCUMENT_TEMPLATES.MODAL.CANCEL'),
    variant: 'danger',
  });
  if (!ok) return;

  try {
    await store.deleteTemplate(template.id);
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.DELETED', { name: template.name }));
  } catch (e) {
    // Template já gerou documentos → FK restrict. Sugere arquivar.
    if (e.response?.data?.error === 'has_dependents') {
      useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.DELETE_HAS_DOCUMENTS'));
    } else {
      useAlert(e.response?.data?.errors?.join(', ') || e.response?.data?.error || e.message);
    }
  }
};

const handleCreatedTemplate = (created) => {
  showNewTemplateModal.value = false;
  openEditor(created);
};

const handleCreatedFolder = () => {
  showNewFolderModal.value = false;
};

// Excluir pasta. Backend usa restrict_with_error: se a pasta tem modelos
// dentro, a deleção falha — avisamos o user pra mover/arquivar antes.
const handleDeleteFolder = async (folder) => {
  const hasTemplates = templates.value.some(
    t => t.folder_id === folder.id && !isArchived(t),
  );
  if (hasTemplates) {
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.FOLDER_NOT_EMPTY', { name: folder.name }));
    return;
  }
  const ok = await confirm({
    title: t('DOCUMENT_TEMPLATES.SIDEBAR.DELETE_FOLDER'),
    message: t('DOCUMENT_TEMPLATES.MESSAGES.FOLDER_DELETE_CONFIRM', { name: folder.name }),
    confirmLabel: t('DOCUMENT_TEMPLATES.SIDEBAR.DELETE_FOLDER'),
    cancelLabel: t('DOCUMENT_TEMPLATES.MODAL.CANCEL'),
    variant: 'danger',
  });
  if (!ok) return;

  try {
    if (selectedFolderId.value === folder.id) store.selectFolder(null);
    await store.deleteFolder(folder.id);
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.FOLDER_DELETED', { name: folder.name }));
  } catch (e) {
    useAlert(e.response?.data?.error || e.response?.data?.errors?.join(', ') || e.message);
  }
};

// ── Boot ────────────────────────────────────────────────────────────────
onMounted(async () => {
  await Promise.all([
    // include_archived: traz active + draft + archived num fetch só; o
    // client separa por view (Arquivados) e por status nos counts.
    store.fetchTemplates({ includeArchived: 'true' }),
    store.fetchFolders(),
    store.fetchKlivyLibrary(),
  ]);
});
</script>

<template>
  <div class="documents-index">
    <DocumentsHeader
      v-model:search="search"
      v-model:document-type-filter="documentTypeFilter"
      v-model:active-tab="activeTab"
      v-model:view-mode="viewMode"
      :owned-count="ownedCount"
      :all-count="allCount"
      :klivy-count="klivyLibrary.length"
      :show-new-button="isAdmin"
      @click-new="openNewTemplate"
    />

    <div class="documents-index__body">
      <FolderSidebar
        v-if="showSidebar"
        :folders="folders"
        :templates="ownedTemplates"
        :selected-folder-id="selectedFolderId"
        :archived-count="archivedCount"
        @select="store.selectFolder"
        @click-new-folder="openNewFolder"
        @drop-template="handleDropTemplate"
        @delete-folder="handleDeleteFolder"
      />

      <main class="documents-index__main">
        <TemplateGrid
          v-if="viewMode === 'grid'"
          :templates="currentList"
          :loading="currentLoading"
          :variant="gridVariant"
          :empty-title="emptyTitle"
          :empty-description="emptyDescription"
          @open="handleOpen"
          @menu="handleTemplateMenu"
        />
        <TemplateList
          v-else
          :templates="currentList"
          :loading="currentLoading"
          :variant="gridVariant"
          :empty-title="emptyTitle"
          :empty-description="emptyDescription"
          @open="handleOpen"
          @menu="handleTemplateMenu"
        />
      </main>
    </div>

    <NewFolderModal
      v-if="showNewFolderModal"
      @close="showNewFolderModal = false"
      @created="handleCreatedFolder"
    />

    <NewTemplateModal
      v-if="showNewTemplateModal"
      :folders="folders"
      @close="showNewTemplateModal = false"
      @created="handleCreatedTemplate"
    />

    <ConfirmDialog
      v-bind="confirmState"
      @confirm="onConfirm"
      @cancel="onCancel"
    />

    <TemplateContextMenu
      v-if="contextMenu.template"
      :template="contextMenu.template"
      :anchor="contextMenu.anchor"
      @close="closeContextMenu"
      @duplicate="handleDuplicate"
      @archive="handleArchive"
      @unarchive="handleUnarchive"
      @delete="handleDelete"
    />
  </div>
</template>

<!--
  Tokens M3 Klivy carregados GLOBALMENTE (não-scoped) pra estarem
  disponíveis em modais/popovers teleportados pra body. Sem isso, o
  Vue scoped transformaria :root em :root[data-v-xxx] e quebraria.
-->
<style lang="scss">
@use '../../styles/klivy-tokens';
</style>

<style lang="scss" scoped>
@use '../../styles/index/index';
</style>
