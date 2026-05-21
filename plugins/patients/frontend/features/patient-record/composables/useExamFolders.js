/**
 * useExamFolders — gestão completa das pastas de exames.
 *
 * Extraído de ExamsTab.vue (Roadmap #11/#12). Concentra:
 *   • Fetch + estado (`examFolders`, `expandedFolderIds`, `activeFolderId`)
 *   • CRUD (`createFolder`, `renameFolder`, `deleteFolder`)
 *   • Drag/drop tree na sidebar (reorder + nest + promote to root)
 *   • Computeds (`topLevelFolders`, `getSubfolders`, `getFolderPath`,
 *     `getTotalItemCount`)
 *
 * Nota: `examMediasRef` é um Ref (ou função) para a lista de mídias —
 * usado em `getTotalItemCount` e no gate de exclusão. As mutações em mídias
 * (move/lock) ficam em `useExamMedias`; aqui só a estrutura de pastas.
 */

import { ref, computed } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import ExamFoldersAPI from '@plugins/patients/frontend/api/patients/examFolders';
import {
  ROOT_FOLDER_ID,
  DEFAULT_FOLDER_COLOR,
} from '@plugins/patients/frontend/constants/exams';

export function useExamFolders(patientIdRef, examMediasRef) {
  const { t } = useI18n();

  const examFolders = ref([]);
  const activeFolderId = ref(ROOT_FOLDER_ID);
  const expandedFolderIds = ref(new Set());
  const isCreatingFolder = ref(false);

  // Drag & drop state da sidebar.
  const draggedFolderId = ref(null);
  const dragOverFolderTarget = ref(null); // { id, position: 'before'|'after'|'inside' }
  const dragPromoteActive = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const resolveMedias = () => {
    if (typeof examMediasRef === 'function') return examMediasRef();
    return examMediasRef?.value ?? examMediasRef ?? [];
  };

  // ── Computeds / queries ───────────────────────────────────────
  const topLevelFolders = computed(() =>
    examFolders.value
      .filter(f => !f.parent_id)
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
  );

  const getSubfolders = parentId =>
    examFolders.value
      .filter(f => f.parent_id === parentId)
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));

  const getFolderPath = folderId => {
    if (folderId === ROOT_FOLDER_ID) return [];
    const path = [];
    let current = examFolders.value.find(f => f.id === folderId);
    while (current) {
      path.unshift(current);
      current = current.parent_id
        ? examFolders.value.find(f => f.id === current.parent_id)
        : null;
    }
    return path;
  };

  const getTotalItemCount = folderId => {
    const subs = getSubfolders(folderId);
    const medias = resolveMedias();
    const directFiles = medias.filter(
      m => (m.folder_id || ROOT_FOLDER_ID) === folderId
    ).length;
    return (
      subs.length +
      directFiles +
      subs.reduce(
        (sum, sub) =>
          sum + medias.filter(m => (m.folder_id || ROOT_FOLDER_ID) === sub.id).length,
        0
      )
    );
  };

  const isAncestorOf = (potentialAncestorId, folderId) => {
    let current = examFolders.value.find(f => f.id === folderId);
    while (current?.parent_id) {
      if (current.parent_id === potentialAncestorId) return true;
      current = examFolders.value.find(f => f.id === current.parent_id);
    }
    return false;
  };

  // ── Fetch ─────────────────────────────────────────────────────
  const fetch = async () => {
    const id = resolveId();
    if (!id) return;
    try {
      const { data } = await ExamFoldersAPI.getAll(id);
      examFolders.value = data?.data || [];
    } catch (error) {
      examFolders.value = [];
      // eslint-disable-next-line no-console
      console.error('[Exams] Falha ao carregar pastas', error);
      useNotification.error(t('PATIENT_EXAMS.MESSAGES.LOAD_FOLDERS_ERROR'));
    }
  };

  // ── Reorder helpers ──────────────────────────────────────────
  const renumberSiblings = parentId => {
    const siblings = examFolders.value
      .filter(f => (f.parent_id ?? null) === (parentId ?? null))
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
    const items = [];
    siblings.forEach((f, idx) => {
      if (f.position !== idx) {
        f.position = idx;
        items.push({ id: f.id, parent_id: parentId ?? null, position: idx });
      }
    });
    return items;
  };

  const persistReorder = async items => {
    if (!items.length) return;
    try {
      await ExamFoldersAPI.reorder(resolveId(), items);
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Exams] Falha ao reordenar pastas', error);
      useNotification.error(t('PATIENT_EXAMS.MESSAGES.REORDER_REVERTED'));
      await fetch();
    }
  };

  // ── UI: expand/collapse + active folder ───────────────────────
  const toggleFolderExpand = folderId => {
    const next = new Set(expandedFolderIds.value);
    if (next.has(folderId)) next.delete(folderId);
    else next.add(folderId);
    expandedFolderIds.value = next;
  };

  const clickFolderRow = folder => {
    activeFolderId.value = folder.id;
    if (getSubfolders(folder.id).length > 0) toggleFolderExpand(folder.id);
  };

  // ── CRUD ──────────────────────────────────────────────────────
  const createFolder = async name => {
    const trimmed = String(name || '').trim();
    if (!trimmed || isCreatingFolder.value) return { ok: false };
    isCreatingFolder.value = true;
    const maxPos = topLevelFolders.value.reduce(
      (m, f) => Math.max(m, f.position ?? 0),
      -1
    );
    try {
      const { data } = await ExamFoldersAPI.create(resolveId(), {
        name: trimmed,
        color: DEFAULT_FOLDER_COLOR,
        parent_id: null,
        position: maxPos + 1,
      });
      examFolders.value.push(data);
      return { ok: true };
    } catch (error) {
      const errs = error?.response?.data?.errors;
      useNotification.error(
        Array.isArray(errs)
          ? errs.join('. ')
          : t('PATIENT_EXAMS.MESSAGES.CREATE_FOLDER_ERROR')
      );
      return { ok: false };
    } finally {
      isCreatingFolder.value = false;
    }
  };

  const renameFolder = async (folderId, newName, newColor) => {
    const name = String(newName || '').trim();
    if (!name) return { ok: false };
    const folder = examFolders.value.find(f => f.id === folderId);
    if (!folder) return { ok: false };
    const previousName = folder.name;
    const previousColor = folder.color;
    folder.name = name;
    folder.color = newColor;
    try {
      await ExamFoldersAPI.update(resolveId(), folder.id, {
        name,
        color: newColor,
      });
      return { ok: true };
    } catch (error) {
      folder.name = previousName;
      folder.color = previousColor;
      const errs = error?.response?.data?.errors;
      useNotification.error(
        Array.isArray(errs)
          ? errs.join('. ')
          : t('PATIENT_EXAMS.MESSAGES.RENAME_FOLDER_ERROR')
      );
      return { ok: false };
    }
  };

  const deleteFolder = async folderId => {
    const target = examFolders.value.find(f => f.id === folderId);
    if (!target) return { ok: false };
    try {
      await ExamFoldersAPI.delete(resolveId(), target.id);
      const subIds = getSubfolders(target.id).map(s => s.id);
      const removedIds = new Set([target.id, ...subIds]);
      examFolders.value = examFolders.value.filter(f => !removedIds.has(f.id));
      if (removedIds.has(activeFolderId.value)) {
        activeFolderId.value = ROOT_FOLDER_ID;
      }
      return { ok: true, removedIds };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Exams] Falha ao excluir pasta', error);
      useNotification.error(t('PATIENT_EXAMS.MESSAGES.DELETE_FOLDER_ERROR'));
      return { ok: false };
    }
  };

  // ── Drag & drop sidebar ───────────────────────────────────────
  const onSidebarDragStart = (event, folder) => {
    draggedFolderId.value = folder.id;
    event.dataTransfer.effectAllowed = 'move';
  };

  const onSidebarDragOver = (event, folder) => {
    event.preventDefault();
    event.stopPropagation();
    if (!draggedFolderId.value || draggedFolderId.value === folder.id) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const y = event.clientY - rect.top;
    const pct = y / rect.height;
    let position;
    if (pct < 0.28) position = 'before';
    else if (pct > 0.72) position = 'after';
    else position = 'inside';
    dragOverFolderTarget.value = { id: folder.id, position };
  };

  const onSidebarDragLeave = () => {
    dragOverFolderTarget.value = null;
  };

  const onSidebarDragEnd = () => {
    draggedFolderId.value = null;
    dragOverFolderTarget.value = null;
  };

  const onSidebarDrop = async (event, targetFolder) => {
    event.preventDefault();
    event.stopPropagation();
    if (!draggedFolderId.value || draggedFolderId.value === targetFolder.id) {
      onSidebarDragEnd();
      return;
    }
    const dragged = examFolders.value.find(f => f.id === draggedFolderId.value);
    if (!dragged) return;

    const pos = dragOverFolderTarget.value?.position;
    const oldParent = dragged.parent_id ?? null;
    let items = [];

    if (pos === 'inside') {
      if (targetFolder.parent_id) {
        useNotification.warning(t('PATIENT_EXAMS.MESSAGES.FOLDER_NESTING_LIMIT'));
        onSidebarDragEnd();
        return;
      }
      if (isAncestorOf(draggedFolderId.value, targetFolder.id)) {
        useNotification.warning(t('PATIENT_EXAMS.MESSAGES.FOLDER_CIRCULAR'));
        onSidebarDragEnd();
        return;
      }
      dragged.parent_id = targetFolder.id;
      const newSiblings = examFolders.value.filter(
        f => f.parent_id === targetFolder.id && f.id !== dragged.id
      );
      dragged.position = newSiblings.length;
      const next = new Set(expandedFolderIds.value);
      next.add(targetFolder.id);
      expandedFolderIds.value = next;
      useNotification.info(
        t('PATIENT_EXAMS.MESSAGES.FOLDER_MOVED_INTO', {
          name: dragged.name,
          target: targetFolder.name,
        })
      );
      items = [
        { id: dragged.id, parent_id: targetFolder.id, position: dragged.position },
        ...renumberSiblings(oldParent),
      ];
    } else {
      const targetParent = targetFolder.parent_id ?? null;
      dragged.parent_id = targetParent;
      const siblings = examFolders.value
        .filter(f => (f.parent_id ?? null) === targetParent)
        .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
      const withoutDragged = siblings.filter(f => f.id !== dragged.id);
      const targetIdx = withoutDragged.findIndex(f => f.id === targetFolder.id);
      const insertAt = pos === 'before' ? targetIdx : targetIdx + 1;
      withoutDragged.splice(insertAt, 0, dragged);
      withoutDragged.forEach((f, i) => {
        f.position = i;
      });
      items = withoutDragged.map(f => ({
        id: f.id,
        parent_id: targetParent,
        position: f.position,
      }));
      if (oldParent !== targetParent) items.push(...renumberSiblings(oldParent));
    }

    onSidebarDragEnd();
    await persistReorder(items);
  };

  const promoteToRoot = async () => {
    if (!draggedFolderId.value) return;
    const folder = examFolders.value.find(f => f.id === draggedFolderId.value);
    if (!folder) return;

    const oldParent = folder.parent_id ?? null;
    folder.parent_id = null;
    const maxPos = topLevelFolders.value
      .filter(f => f.id !== folder.id)
      .reduce((m, f) => Math.max(m, f.position ?? 0), -1);
    folder.position = maxPos + 1;

    const items = [
      { id: folder.id, parent_id: null, position: folder.position },
      ...renumberSiblings(oldParent),
    ];

    onSidebarDragEnd();
    await persistReorder(items);
  };

  return {
    examFolders,
    activeFolderId,
    expandedFolderIds,
    isCreatingFolder,
    draggedFolderId,
    dragOverFolderTarget,
    dragPromoteActive,
    topLevelFolders,
    getSubfolders,
    getFolderPath,
    getTotalItemCount,
    fetch,
    toggleFolderExpand,
    clickFolderRow,
    createFolder,
    renameFolder,
    deleteFolder,
    onSidebarDragStart,
    onSidebarDragOver,
    onSidebarDragLeave,
    onSidebarDragEnd,
    onSidebarDrop,
    promoteToRoot,
  };
}
