<script setup>
/**
 * ExamsTab — Aba "Exames e Imagens" do prontuário do paciente.
 *
 * Orquestrador. Composição:
 *   • useExamMedias — fetch + upload + rename + lock + delete + move
 *   • useExamFolders — CRUD pastas + drag/drop tree + reorder
 *   • useMediaLightbox — abre/fecha lightbox + ESC keyboard
 *   • exams-tab/* (12 sub-componentes)
 *
 * Auto-suficiente: lê patientId da rota e gerencia próprio estado/refresh.
 * Pai (Record.vue) só precisa de `<ExamsTab v-if="activeTab === 'exams'" />`.
 */
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import { useExamMedias } from '@plugins/patients/frontend/features/patient-record/composables/useExamMedias';
import { useExamFolders } from '@plugins/patients/frontend/features/patient-record/composables/useExamFolders';
import { useMediaLightbox } from '@plugins/patients/frontend/features/patient-record/composables/useMediaLightbox';
import { matchesTypeFilter } from '@plugins/patients/frontend/features/patient-record/utils/examClassifiers';
import { ROOT_FOLDER_ID } from '@plugins/patients/frontend/constants/exams';
import ExamsHeader from '@plugins/patients/frontend/features/patient-record/components/exams-tab/ExamsHeader.vue';
import FolderBreadcrumb from '@plugins/patients/frontend/features/patient-record/components/exams-tab/FolderBreadcrumb.vue';
import FolderSidebar from '@plugins/patients/frontend/features/patient-record/components/exams-tab/FolderSidebar.vue';
import MediaTypeFilters from '@plugins/patients/frontend/features/patient-record/components/exams-tab/MediaTypeFilters.vue';
import MediaGrid from '@plugins/patients/frontend/features/patient-record/components/exams-tab/MediaGrid.vue';
import CreateFolderModal from '@plugins/patients/frontend/features/patient-record/components/exams-tab/CreateFolderModal.vue';
import RenameFolderModal from '@plugins/patients/frontend/features/patient-record/components/exams-tab/RenameFolderModal.vue';
import DeleteFolderModal from '@plugins/patients/frontend/features/patient-record/components/exams-tab/DeleteFolderModal.vue';
import LockMediaModal from '@plugins/patients/frontend/features/patient-record/components/exams-tab/LockMediaModal.vue';
import DeleteMediaModal from '@plugins/patients/frontend/features/patient-record/components/exams-tab/DeleteMediaModal.vue';
import MediaLightbox from '@plugins/patients/frontend/features/patient-record/components/exams-tab/MediaLightbox.vue';

const { t } = useI18n();
const route = useRoute();
const patientId = computed(() => route.params.patientId);

// ── Composables ────────────────────────────────────────────
const {
  examMedias,
  isUploading,
  uploadProgress,
  isDeleting,
  fetch: fetchMedias,
  upload,
  move,
  rename: renameMedia,
  toggleLock,
  remove,
} = useExamMedias(patientId);

const {
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
  fetch: fetchFolders,
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
} = useExamFolders(patientId, examMedias);

const {
  lightboxMedia,
  open: openLightbox,
  close: closeLightbox,
  attachKeyboard,
  detachKeyboard,
} = useMediaLightbox();

// ── Local UI state ─────────────────────────────────────────
const activeMediaTypeFilter = ref('all');
const draggedMediaId = ref(null);
const isDraggingOverFolder = ref(null);

// Modais
const showCreateFolderModal = ref(false);

const showRenameFolderModal = ref(false);
const renamingFolder = ref(null);

const showDeleteFolderModal = ref(false);
const folderToDelete = ref(null);
const deleteBlockedMessage = ref('');

const showLockModal = ref(false);
const lockTargetMediaId = ref(null);
const lockActionType = ref('lock');
const isLockSubmitting = ref(false);

const renamingMediaId = ref(null);

const showDeleteMediaModal = ref(false);
const mediaToDelete = ref(null);

// ── Computeds ──────────────────────────────────────────────
const mediasInFolder = computed(() => {
  let list = examMedias.value;
  if (activeFolderId.value !== ROOT_FOLDER_ID) {
    list = list.filter(m => m.folder_id === activeFolderId.value);
  }
  return list.filter(m => matchesTypeFilter(m, activeMediaTypeFilter.value));
});

const countMediasInFolder = folderId =>
  examMedias.value.filter(m => m.folder_id === folderId).length;

const isAnyDragging = computed(
  () => Boolean(draggedMediaId.value || draggedFolderId.value)
);

// ── Handlers: pastas (CRUD) ─────────────────────────────────
const handleCreateFolder = async name => {
  const { ok } = await createFolder(name);
  if (ok) showCreateFolderModal.value = false;
};

const handleStartRenameFolder = folder => {
  renamingFolder.value = folder;
  showRenameFolderModal.value = true;
};

const handleConfirmRenameFolder = async ({ name, color }) => {
  if (!renamingFolder.value) return;
  const { ok } = await renameFolder(renamingFolder.value.id, name, color);
  if (ok) {
    showRenameFolderModal.value = false;
    renamingFolder.value = null;
  }
};

const handleRequestDeleteFolder = folder => {
  const subIds = getSubfolders(folder.id).map(s => s.id);
  const containedIds = [folder.id, ...subIds];
  const hasLockedMedia = examMedias.value.some(
    m => containedIds.includes(m.folder_id) && m.locked
  );
  deleteBlockedMessage.value = hasLockedMedia
    ? t('PATIENT_EXAMS.MESSAGES.DELETE_FOLDER_BLOCKED')
    : '';
  folderToDelete.value = folder;
  showDeleteFolderModal.value = true;
};

const handleCloseDeleteFolder = () => {
  showDeleteFolderModal.value = false;
  folderToDelete.value = null;
  deleteBlockedMessage.value = '';
};

const handleConfirmDeleteFolder = async () => {
  if (!folderToDelete.value || deleteBlockedMessage.value) {
    handleCloseDeleteFolder();
    return;
  }
  const target = folderToDelete.value;
  handleCloseDeleteFolder();
  const { ok } = await deleteFolder(target.id);
  if (ok) await fetchMedias(); // reflect folder_id zerado pelo backend
};

// ── Handlers: drag/drop de mídia para pasta ────────────────
const onMediaDragStart = (event, mediaId) => {
  draggedMediaId.value = mediaId;
  event.dataTransfer.effectAllowed = 'move';

  const media = examMedias.value.find(m => m.id === mediaId);
  const label = media?.file_name || t('PATIENT_EXAMS.CARD.DEFAULT_NAME');

  const ghost = document.createElement('div');
  ghost.style.cssText = [
    'position:absolute',
    'top:-1000px',
    'left:-1000px',
    'display:inline-flex',
    'align-items:center',
    'gap:8px',
    'padding:8px 14px',
    'background:#1e293b',
    'color:#f1f5f9',
    'border-radius:9999px',
    'font:500 13px system-ui,sans-serif',
    'box-shadow:0 8px 20px rgba(0,0,0,.35)',
    'border:1px solid rgba(59,130,246,.4)',
    'pointer-events:none',
    'white-space:nowrap',
    'max-width:260px',
    'overflow:hidden',
    'text-overflow:ellipsis',
  ].join(';');
  ghost.textContent = `↕  ${label}`;
  document.body.appendChild(ghost);
  event.dataTransfer.setDragImage(ghost, 16, 16);
  requestAnimationFrame(() => {
    if (ghost.parentNode) ghost.parentNode.removeChild(ghost);
  });
};

const onMediaFolderDragOver = (event, folderId) => {
  event.preventDefault();
  event.dataTransfer.dropEffect = 'move';
  isDraggingOverFolder.value = folderId;
};

const onMediaFolderDragLeave = () => {
  isDraggingOverFolder.value = null;
};

const onMediaFolderDrop = async (event, folderId) => {
  event.preventDefault();
  isDraggingOverFolder.value = null;
  const mediaId = draggedMediaId.value;
  draggedMediaId.value = null;
  if (!mediaId) return;
  const targetId = folderId === ROOT_FOLDER_ID ? null : folderId;
  await move(mediaId, targetId);
};

// ── Handlers: lock/unlock ──────────────────────────────────
const openLockModal = (mediaId, action) => {
  lockTargetMediaId.value = mediaId;
  lockActionType.value = action;
  showLockModal.value = true;
};

const closeLockModal = () => {
  if (isLockSubmitting.value) return;
  showLockModal.value = false;
  lockTargetMediaId.value = null;
};

const confirmLockAction = async () => {
  if (!lockTargetMediaId.value) return;
  isLockSubmitting.value = true;
  const desired = lockActionType.value === 'lock';
  const { ok } = await toggleLock(lockTargetMediaId.value, desired);
  isLockSubmitting.value = false;
  if (ok) closeLockModal();
};

// ── Handlers: rename mídia ─────────────────────────────────
const startRenameMedia = media => {
  renamingMediaId.value = media.id;
};

const cancelRenameMedia = () => {
  renamingMediaId.value = null;
};

const confirmRenameMedia = async newName => {
  if (!renamingMediaId.value) return;
  const id = renamingMediaId.value;
  const candidate = String(newName || '').trim();
  if (!candidate) {
    renamingMediaId.value = null;
    return;
  }

  const target = examMedias.value.find(m => m.id === id);
  if (target && target.file_name === candidate) {
    renamingMediaId.value = null;
    return;
  }

  const folderId = target?.folder_id ?? null;
  const hasDuplicate = examMedias.value.some(
    m =>
      m.id !== id &&
      (m.folder_id ?? null) === folderId &&
      String(m.file_name || '').localeCompare(candidate, undefined, {
        sensitivity: 'base',
      }) === 0
  );
  if (hasDuplicate) {
    useNotification.warning(t('PATIENT_EXAMS.MESSAGES.RENAME_DUPLICATE_NAME'));
    return;
  }

  renamingMediaId.value = null;
  await renameMedia(id, candidate);
};

// ── Handlers: delete mídia ─────────────────────────────────
const requestDeleteMedia = media => {
  if (media.locked) {
    useNotification.warning(t('PATIENT_EXAMS.MESSAGES.DELETE_LOCKED_BLOCKED'));
    return;
  }
  mediaToDelete.value = media;
  showDeleteMediaModal.value = true;
};

const confirmDeleteMedia = async () => {
  if (!mediaToDelete.value) return;
  const target = mediaToDelete.value;
  const { ok } = await remove(target.id);
  if (ok) {
    showDeleteMediaModal.value = false;
    mediaToDelete.value = null;
  }
};

// ── Lifecycle ──────────────────────────────────────────────
onMounted(() => {
  fetchMedias();
  fetchFolders();
  attachKeyboard();
});

onUnmounted(() => {
  detachKeyboard();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <ExamsHeader
      :is-uploading="isUploading"
      :upload-progress="uploadProgress"
      @create-folder="showCreateFolderModal = true"
      @file-selected="upload"
    />

    <div v-if="isUploading" class="exams-upload-progress mb-4">
      <div
        class="exams-upload-progress-bar"
        :style="{ width: `${uploadProgress}%` }"
      />
      <span class="exams-upload-progress-label">
        {{
          t('PATIENT_EXAMS.HEADER.UPLOAD_PROGRESS_LABEL', {
            progress: uploadProgress,
          })
        }}
      </span>
    </div>

    <FolderBreadcrumb
      :path="getFolderPath(activeFolderId)"
      :active-folder-id="activeFolderId"
      :file-count="mediasInFolder.length"
      :is-dragging="isAnyDragging"
      @select="activeFolderId = $event"
    />

    <div class="flex gap-5 items-start">
      <FolderSidebar
        :total-medias="examMedias.length"
        :top-level-folders="topLevelFolders"
        :active-folder-id="activeFolderId"
        :expanded-folder-ids="expandedFolderIds"
        :dragged-folder-id="draggedFolderId"
        :drag-over-folder-target="dragOverFolderTarget"
        :drag-promote-active="dragPromoteActive"
        :is-dragging-over-folder="isDraggingOverFolder"
        :get-subfolders="getSubfolders"
        :get-total-item-count="getTotalItemCount"
        :count-medias-in-folder="countMediasInFolder"
        @set-active="activeFolderId = $event"
        @click-row="clickFolderRow"
        @toggle-expand="toggleFolderExpand"
        @rename-folder="handleStartRenameFolder"
        @delete-folder="handleRequestDeleteFolder"
        @sidebar-drag-start="onSidebarDragStart"
        @sidebar-drag-over="onSidebarDragOver"
        @sidebar-drag-leave="onSidebarDragLeave"
        @sidebar-drag-end="onSidebarDragEnd"
        @sidebar-drop="onSidebarDrop"
        @media-drag-over="onMediaFolderDragOver"
        @media-drag-leave="onMediaFolderDragLeave"
        @media-drop="onMediaFolderDrop"
        @promote-active="dragPromoteActive = true"
        @promote-leave="dragPromoteActive = false"
        @promote-drop="
          promoteToRoot();
          dragPromoteActive = false;
        "
      />

      <div class="flex-1 min-w-0 flex flex-col gap-4">
        <MediaTypeFilters
          :active="activeMediaTypeFilter"
          @update:active="activeMediaTypeFilter = $event"
        />
        <MediaGrid
          :medias="mediasInFolder"
          :dragged-media-id="draggedMediaId"
          :renaming-media-id="renamingMediaId"
          @media-drag-start="onMediaDragStart"
          @media-drag-end="draggedMediaId = null"
          @open-lightbox="openLightbox"
          @start-rename="startRenameMedia"
          @confirm-rename="confirmRenameMedia"
          @cancel-rename="cancelRenameMedia"
          @lock="openLockModal($event, 'lock')"
          @unlock="openLockModal($event, 'unlock')"
          @delete="requestDeleteMedia"
        />
      </div>
    </div>

    <CreateFolderModal
      :open="showCreateFolderModal"
      :loading="isCreatingFolder"
      @close="showCreateFolderModal = false"
      @confirm="handleCreateFolder"
    />

    <RenameFolderModal
      :open="showRenameFolderModal"
      :folder="renamingFolder"
      @close="
        showRenameFolderModal = false;
        renamingFolder = null;
      "
      @confirm="handleConfirmRenameFolder"
    />

    <DeleteFolderModal
      :open="showDeleteFolderModal"
      :folder="folderToDelete"
      :blocked-message="deleteBlockedMessage"
      @close="handleCloseDeleteFolder"
      @confirm="handleConfirmDeleteFolder"
    />

    <LockMediaModal
      :open="showLockModal"
      :action="lockActionType"
      :loading="isLockSubmitting"
      @close="closeLockModal"
      @confirm="confirmLockAction"
    />

    <DeleteMediaModal
      :open="showDeleteMediaModal"
      :media="mediaToDelete"
      :loading="isDeleting"
      @close="
        showDeleteMediaModal = false;
        mediaToDelete = null;
      "
      @confirm="confirmDeleteMedia"
    />
  </div>

  <MediaLightbox :media="lightboxMedia" @close="closeLightbox" />
</template>
