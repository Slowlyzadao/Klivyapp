<script setup>
import { useI18n } from 'vue-i18n';
import { ROOT_FOLDER_ID } from '@plugins/patients/frontend/constants/exams';

defineProps({
  totalMedias: { type: Number, default: 0 },
  topLevelFolders: { type: Array, default: () => [] },
  activeFolderId: { type: String, default: ROOT_FOLDER_ID },
  expandedFolderIds: { type: Set, default: () => new Set() },
  draggedFolderId: { type: String, default: null },
  dragOverFolderTarget: { type: Object, default: null },
  dragPromoteActive: { type: Boolean, default: false },
  isDraggingOverFolder: { type: String, default: null },
  getSubfolders: { type: Function, required: true },
  getTotalItemCount: { type: Function, required: true },
  countMediasInFolder: { type: Function, required: true },
});

const emit = defineEmits([
  'set-active',
  'click-row',
  'toggle-expand',
  'rename-folder',
  'delete-folder',
  'sidebar-drag-start',
  'sidebar-drag-over',
  'sidebar-drag-leave',
  'sidebar-drag-end',
  'sidebar-drop',
  'media-drag-over',
  'media-drag-leave',
  'media-drop',
  'promote-active',
  'promote-leave',
  'promote-drop',
]);

const { t } = useI18n();
</script>

<template>
  <div class="exams-sidebar">
    <!-- Raiz -->
    <button
      class="exams-sidebar-item"
      :class="
        activeFolderId === ROOT_FOLDER_ID
          ? 'exams-sidebar-item--active'
          : 'exams-sidebar-item--idle'
      "
      :style="
        isDraggingOverFolder === ROOT_FOLDER_ID
          ? 'background: rgba(96,165,250,0.18); border-color: rgba(96,165,250,0.5); transform: scale(1.03); box-shadow: 0 0 16px rgba(96,165,250,0.25);'
          : ''
      "
      @click="emit('set-active', ROOT_FOLDER_ID)"
      @dragover.prevent="emit('media-drag-over', $event, ROOT_FOLDER_ID)"
      @dragleave="emit('media-drag-leave')"
      @drop="emit('media-drop', $event, ROOT_FOLDER_ID)"
    >
      <i class="i-lucide-hard-drive text-base shrink-0" />
      <span class="truncate">{{ t('PATIENT_EXAMS.SIDEBAR.ALL_FILES') }}</span>
      <span class="ml-auto text-[10px] opacity-60">{{ totalMedias }}</span>
    </button>

    <div class="exams-sidebar-section-label">
      <span>{{ t('PATIENT_EXAMS.SIDEBAR.FOLDERS_SECTION') }}</span>
    </div>

    <!-- Pastas top-level -->
    <template v-for="folder in topLevelFolders" :key="folder.id">
      <!-- Indicador ANTES -->
      <div
        v-if="
          dragOverFolderTarget?.id === folder.id &&
          dragOverFolderTarget?.position === 'before'
        "
        class="relative my-0.5"
        style="height: 10px"
      >
        <div
          class="absolute left-2 right-0 top-1/2 -translate-y-1/2 h-px bg-blue-400"
          style="box-shadow: 0 0 4px rgba(96, 165, 250, 0.8)"
        />
        <div
          class="absolute left-2 top-1/2 -translate-y-1/2 w-2.5 h-2.5 rounded-full border-2 border-blue-400"
          style="background: #0f172a"
        />
      </div>

      <!-- Row -->
      <div class="group relative">
        <div
          class="flex items-center gap-1.5 rounded-xl border transition-all cursor-grab active:cursor-grabbing"
          :class="[
            activeFolderId === folder.id
              ? 'bg-opacity-20 border-opacity-40'
              : 'bg-transparent border-transparent',
            draggedFolderId === folder.id ? 'opacity-30' : '',
          ]"
          :style="[
            dragOverFolderTarget?.id === folder.id &&
            dragOverFolderTarget?.position === 'inside'
              ? `color: ${folder.color || '#60a5fa'}; background: ${folder.color || '#60a5fa'}22; border-color: ${folder.color || '#60a5fa'}88; box-shadow: 0 0 18px ${folder.color || '#60a5fa'}44;`
              : activeFolderId === folder.id
                ? `color: ${folder.color || '#60a5fa'}; background: ${folder.color || '#60a5fa'}1a; border-color: ${folder.color || '#60a5fa'}44;`
                : `color: ${folder.color || '#94a3b8'};`,
          ]"
          draggable="true"
          @dragstart="emit('sidebar-drag-start', $event, folder)"
          @dragend="emit('sidebar-drag-end')"
          @dragover="emit('sidebar-drag-over', $event, folder)"
          @dragleave="emit('sidebar-drag-leave')"
          @drop="emit('sidebar-drop', $event, folder)"
        >
          <button
            class="flex items-center gap-1.5 px-3 py-2 flex-1 min-w-0 text-sm font-medium text-left"
            @click="emit('click-row', folder)"
            @dragover.prevent="emit('media-drag-over', $event, folder.id)"
            @dragleave="emit('media-drag-leave')"
            @drop="emit('media-drop', $event, folder.id)"
          >
            <i
              class="text-base shrink-0"
              :class="
                expandedFolderIds.has(folder.id) &&
                getSubfolders(folder.id).length > 0
                  ? 'i-lucide-folder-open'
                  : 'i-lucide-folder'
              "
            />
            <span class="truncate flex-1">{{ folder.name }}</span>
            <span class="text-[10px] opacity-50 shrink-0">
              {{ getTotalItemCount(folder.id) }}
            </span>
          </button>

          <button
            v-if="getSubfolders(folder.id).length > 0"
            class="p-1.5 shrink-0 opacity-60 hover:opacity-100 transition-all"
            :class="expandedFolderIds.has(folder.id) ? 'rotate-90' : ''"
            style="transition: transform 0.2s ease"
            @click.stop="emit('toggle-expand', folder.id)"
          >
            <i class="i-lucide-chevron-right text-xs" />
          </button>
        </div>

        <!-- Ações pasta (hover) -->
        <div
          class="absolute right-8 top-1/2 -translate-y-1/2 hidden group-hover:flex items-center gap-0.5 bg-slate-800/90 rounded-lg px-1 py-0.5 z-10"
        >
          <button
            class="p-1 text-slate-400 hover:text-blue-400 rounded transition-colors"
            :title="t('PATIENT_EXAMS.SIDEBAR.RENAME_TITLE')"
            @click.stop="emit('rename-folder', folder)"
          >
            <i class="i-lucide-pencil text-xs" />
          </button>
          <button
            class="p-1 text-slate-400 hover:text-red-400 rounded transition-colors"
            :title="t('PATIENT_EXAMS.SIDEBAR.DELETE_TITLE')"
            @click.stop="emit('delete-folder', folder)"
          >
            <i class="i-lucide-trash-2 text-xs" />
          </button>
        </div>
      </div>

      <!-- Indicador DEPOIS -->
      <div
        v-if="
          dragOverFolderTarget?.id === folder.id &&
          dragOverFolderTarget?.position === 'after'
        "
        class="relative my-0.5"
        style="height: 10px"
      >
        <div
          class="absolute left-2 right-0 top-1/2 -translate-y-1/2 h-px bg-blue-400"
          style="box-shadow: 0 0 4px rgba(96, 165, 250, 0.8)"
        />
        <div
          class="absolute left-2 top-1/2 -translate-y-1/2 w-2.5 h-2.5 rounded-full border-2 border-blue-400"
          style="background: #0f172a"
        />
      </div>

      <!-- Subpastas -->
      <template v-if="expandedFolderIds.has(folder.id)">
        <div
          v-for="sub in getSubfolders(folder.id)"
          :key="sub.id"
          class="group relative ml-5"
        >
          <div
            v-if="
              dragOverFolderTarget?.id === sub.id &&
              dragOverFolderTarget?.position === 'before'
            "
            class="relative my-0.5"
            style="height: 8px"
          >
            <div
              class="absolute left-0 right-0 top-1/2 -translate-y-1/2 h-px bg-blue-400"
              style="box-shadow: 0 0 3px rgba(96, 165, 250, 0.7)"
            />
            <div
              class="absolute left-0 top-1/2 -translate-y-1/2 w-2 h-2 rounded-full border-2 border-blue-400"
              style="background: #0f172a"
            />
          </div>

          <div
            class="flex items-center gap-1.5 rounded-xl border transition-all cursor-grab active:cursor-grabbing"
            :class="[
              activeFolderId === sub.id
                ? 'bg-opacity-20 border-opacity-40'
                : 'bg-transparent border-transparent',
              draggedFolderId === sub.id ? 'opacity-30' : '',
            ]"
            :style="[
              dragOverFolderTarget?.id === sub.id &&
              dragOverFolderTarget?.position === 'inside'
                ? `color: ${sub.color || '#60a5fa'}; background: ${sub.color || '#60a5fa'}22; border-color: ${sub.color || '#60a5fa'}88; box-shadow: 0 0 14px ${sub.color || '#60a5fa'}44;`
                : activeFolderId === sub.id
                  ? `color: ${sub.color || '#60a5fa'}; background: ${sub.color || '#60a5fa'}1a; border-color: ${sub.color || '#60a5fa'}44;`
                  : `color: ${sub.color || '#94a3b8'};`,
            ]"
            draggable="true"
            @dragstart="emit('sidebar-drag-start', $event, sub)"
            @dragend="emit('sidebar-drag-end')"
            @dragover="emit('sidebar-drag-over', $event, sub)"
            @dragleave="emit('sidebar-drag-leave')"
            @drop="emit('sidebar-drop', $event, sub)"
          >
            <button
              class="flex items-center gap-1.5 py-2 pr-3 flex-1 min-w-0 text-sm font-medium text-left"
              @click="emit('click-row', sub)"
              @dragover.prevent="emit('media-drag-over', $event, sub.id)"
              @dragleave="emit('media-drag-leave')"
              @drop="emit('media-drop', $event, sub.id)"
            >
              <i class="i-lucide-folder text-sm shrink-0" />
              <span class="truncate flex-1">{{ sub.name }}</span>
              <span class="text-[10px] opacity-50 shrink-0 pr-1">
                {{ countMediasInFolder(sub.id) }}
              </span>
            </button>
          </div>

          <div
            class="absolute right-1 top-1/2 -translate-y-1/2 hidden group-hover:flex items-center gap-0.5 bg-slate-800/90 rounded-lg px-1 py-0.5 z-10"
          >
            <button
              class="p-1 text-slate-400 hover:text-blue-400 rounded transition-colors"
              :title="t('PATIENT_EXAMS.SIDEBAR.RENAME_SUBFOLDER_TITLE')"
              @click.stop="emit('rename-folder', sub)"
            >
              <i class="i-lucide-pencil text-xs" />
            </button>
            <button
              class="p-1 text-slate-400 hover:text-red-400 rounded transition-colors"
              :title="t('PATIENT_EXAMS.SIDEBAR.DELETE_SUBFOLDER_TITLE')"
              @click.stop="emit('delete-folder', sub)"
            >
              <i class="i-lucide-trash-2 text-xs" />
            </button>
          </div>

          <div
            v-if="
              dragOverFolderTarget?.id === sub.id &&
              dragOverFolderTarget?.position === 'after'
            "
            class="relative my-0.5"
            style="height: 8px"
          >
            <div
              class="absolute left-0 right-0 top-1/2 -translate-y-1/2 h-px bg-blue-400"
              style="box-shadow: 0 0 3px rgba(96, 165, 250, 0.7)"
            />
            <div
              class="absolute left-0 top-1/2 -translate-y-1/2 w-2 h-2 rounded-full border-2 border-blue-400"
              style="background: #0f172a"
            />
          </div>
        </div>
      </template>
    </template>

    <div v-if="topLevelFolders.length === 0" class="px-3 py-2">
      <p class="text-xs text-slate-600 italic">
        {{ t('PATIENT_EXAMS.SIDEBAR.EMPTY') }}
      </p>
    </div>

    <!-- Promote to root -->
    <div
      v-if="draggedFolderId"
      class="mt-2 mx-1 rounded-xl border-2 border-dashed transition-all flex items-center justify-center gap-1.5 py-2 text-xs font-medium"
      :class="
        dragPromoteActive
          ? 'border-emerald-400/70 text-emerald-400 bg-emerald-400/10'
          : 'border-slate-600/50 text-slate-500'
      "
      @dragover.prevent="emit('promote-active')"
      @dragleave="emit('promote-leave')"
      @drop.prevent="emit('promote-drop')"
    >
      <i class="i-lucide-arrow-up-to-line text-sm" />
      {{ t('PATIENT_EXAMS.SIDEBAR.PROMOTE_TO_ROOT') }}
    </div>
  </div>
</template>
