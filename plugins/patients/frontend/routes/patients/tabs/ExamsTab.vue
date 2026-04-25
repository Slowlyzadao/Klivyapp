<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">Exames e Imagens</h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Galeria clínica, exames laboratoriais e radiografias com suporte a PDF
          e imagens.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <input
          ref="mediaFileInput"
          type="file"
          class="hidden"
          accept="image/*,application/pdf"
          @change="onMediaFileSelected"
        />
        <button
          class="btn-secondary flex items-center gap-2"
          @click="showCreateFolderModal = true"
        >
          <i class="i-lucide-folder-plus w-4 h-4" /> Nova Pasta
        </button>
        <button
          class="btn-primary flex items-center gap-2"
          :disabled="isUploadingMedia"
          @click="triggerMediaUpload"
        >
          <i class="i-lucide-upload-cloud w-4 h-4" />
          {{ isUploadingMedia ? 'Enviando...' : 'Fazer Upload' }}
        </button>
      </div>
    </div>

    <!-- Breadcrumb -->
    <div class="exams-breadcrumb">
      <span class="text-slate-500">Exames</span>
      <template v-for="part in getFolderPath(activeFolderId)" :key="part.id">
        <i class="i-lucide-chevron-right exams-breadcrumb-sep" />
        <button
          class="exams-breadcrumb-link"
          :style="{ color: part.color || '#94a3b8' }"
          @click="activeFolderId = part.id"
        >
          {{ part.name }}
        </button>
      </template>
      <template v-if="activeFolderId === 'root'">
        <i class="i-lucide-chevron-right exams-breadcrumb-sep" />
        <span class="text-slate-300 font-medium">Todos os arquivos</span>
      </template>
      <span class="exams-breadcrumb-count"
        >({{ mediasInFolder.length }} arquivo(s))</span
      >
      <span v-if="draggedMediaId || draggedFolderId" class="exams-drag-hint">
        <i class="i-lucide-arrow-left" /> Arraste para uma pasta ao lado
      </span>
    </div>

    <!-- Layout principal: sidebar de pastas + conteúdo -->
    <div class="flex gap-5 items-start">
      <!-- Sidebar de Pastas -->
      <div class="exams-sidebar">
        <!-- Raiz -->
        <button
          class="exams-sidebar-item"
          :class="
            activeFolderId === 'root'
              ? 'exams-sidebar-item--active'
              : 'exams-sidebar-item--idle'
          "
          :style="
            isDraggingOverFolder === 'root'
              ? 'background: rgba(96,165,250,0.18); border-color: rgba(96,165,250,0.5); transform: scale(1.03); box-shadow: 0 0 16px rgba(96,165,250,0.25);'
              : ''
          "
          @click="activeFolderId = 'root'"
          @dragover.prevent="onFolderDragOver($event, 'root')"
          @dragleave="onFolderDragLeave"
          @drop="onFolderDrop($event, 'root')"
        >
          <i class="i-lucide-hard-drive text-base shrink-0" />
          <span class="truncate">Todos os arquivos</span>
          <span class="ml-auto text-[10px] opacity-60">{{
            examMedias.length
          }}</span>
        </button>

        <div class="exams-sidebar-section-label">
          <span>Pastas</span>
        </div>

        <!-- Pastas top-level (drag para reordenar/aninhar) -->
        <template v-for="folder in topLevelFolders" :key="folder.id">
          <!-- Indicador ANTES (estilo Shopify) -->
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

          <!-- Row da pasta -->
          <div class="group relative">
            <!-- Row da pasta (cursor-grab, sem handle visível) -->
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
              @dragstart="onFolderSidebarDragStart($event, folder)"
              @dragend="
                draggedFolderId = null;
                dragOverFolderTarget = null;
              "
              @dragover="onFolderSidebarDragOver($event, folder)"
              @dragleave="onFolderSidebarDragLeave"
              @drop="onFolderSidebarDrop($event, folder)"
            >
              <button
                class="flex items-center gap-1.5 px-3 py-2 flex-1 min-w-0 text-sm font-medium text-left"
                @click="clickFolderRow(folder)"
                @dragover.prevent="onFolderDragOver($event, folder.id)"
                @dragleave="onFolderDragLeave"
                @drop="onFolderDrop($event, folder.id)"
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
                <span class="text-[10px] opacity-50 shrink-0">{{
                  getTotalItemCount(folder.id)
                }}</span>
              </button>

              <!-- Chevron (expand/collapse se tem subpastas) -->
              <button
                v-if="getSubfolders(folder.id).length > 0"
                class="p-1.5 shrink-0 opacity-60 hover:opacity-100 transition-all"
                :class="expandedFolderIds.has(folder.id) ? 'rotate-90' : ''"
                style="transition: transform 0.2s ease"
                @click.stop="toggleFolderExpand(folder.id)"
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
                title="Renomear pasta"
                @click.stop="startRenameFolder(folder)"
              >
                <i class="i-lucide-pencil text-xs" />
              </button>
              <button
                class="p-1 text-slate-400 hover:text-red-400 rounded transition-colors"
                title="Excluir pasta"
                @click.stop="requestDeleteFolder(folder)"
              >
                <i class="i-lucide-trash-2 text-xs" />
              </button>
            </div>
          </div>

          <!-- Indicador DEPOIS (estilo Shopify) -->
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

          <!-- Subpastas (expandidas) -->
          <template v-if="expandedFolderIds.has(folder.id)">
            <div
              v-for="sub in getSubfolders(folder.id)"
              :key="sub.id"
              class="group relative ml-5"
            >
              <!-- Indicador ANTES sub (estilo Shopify) -->
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
                @dragstart="onFolderSidebarDragStart($event, sub)"
                @dragend="
                  draggedFolderId = null;
                  dragOverFolderTarget = null;
                "
                @dragover="onFolderSidebarDragOver($event, sub)"
                @dragleave="onFolderSidebarDragLeave"
                @drop="onFolderSidebarDrop($event, sub)"
              >
                <button
                  class="flex items-center gap-1.5 py-2 pr-3 flex-1 min-w-0 text-sm font-medium text-left"
                  @click="clickFolderRow(sub)"
                  @dragover.prevent="onFolderDragOver($event, sub.id)"
                  @dragleave="onFolderDragLeave"
                  @drop="onFolderDrop($event, sub.id)"
                >
                  <i class="i-lucide-folder text-sm shrink-0" />
                  <span class="truncate flex-1">{{ sub.name }}</span>
                  <span class="text-[10px] opacity-50 shrink-0 pr-1">
                    {{ examMedias.filter(m => m.folder_id === sub.id).length }}
                  </span>
                </button>
              </div>

              <!-- Ações subpasta (hover) -->
              <div
                class="absolute right-1 top-1/2 -translate-y-1/2 hidden group-hover:flex items-center gap-0.5 bg-slate-800/90 rounded-lg px-1 py-0.5 z-10"
              >
                <button
                  class="p-1 text-slate-400 hover:text-blue-400 rounded transition-colors"
                  title="Renomear"
                  @click.stop="startRenameFolder(sub)"
                >
                  <i class="i-lucide-pencil text-xs" />
                </button>
                <button
                  class="p-1 text-slate-400 hover:text-red-400 rounded transition-colors"
                  title="Excluir"
                  @click.stop="requestDeleteFolder(sub)"
                >
                  <i class="i-lucide-trash-2 text-xs" />
                </button>
              </div>

              <!-- Indicador DEPOIS sub (estilo Shopify) -->
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

        <!-- Empty state pastas -->
        <div v-if="topLevelFolders.length === 0" class="px-3 py-2">
          <p class="text-xs text-slate-600 italic">Nenhuma pasta criada</p>
        </div>

        <!-- Zona de promoção para raiz (aparece ao arrastar uma pasta) -->
        <div
          v-if="draggedFolderId"
          class="mt-2 mx-1 rounded-xl border-2 border-dashed transition-all flex items-center justify-center gap-1.5 py-2 text-xs font-medium"
          :class="
            dragPromoteActive
              ? 'border-emerald-400/70 text-emerald-400 bg-emerald-400/10'
              : 'border-slate-600/50 text-slate-500'
          "
          @dragover.prevent="dragPromoteActive = true"
          @dragleave="dragPromoteActive = false"
          @drop.prevent="
            promoteFolderToRoot();
            dragPromoteActive = false;
          "
        >
          <i class="i-lucide-arrow-up-to-line text-sm" />
          Mover para raiz
        </div>
      </div>

      <!-- Área de conteúdo -->
      <div class="flex-1 min-w-0 flex flex-col gap-4">
        <!-- Barra de filtros por tipo -->
        <div class="exams-filters">
          <button
            class="exams-filter-btn"
            :class="
              activeMediaTypeFilter === 'all'
                ? 'exams-filter-btn--on'
                : 'exams-filter-btn--off'
            "
            @click="activeMediaTypeFilter = 'all'"
          >
            Todos
          </button>
          <button
            class="exams-filter-btn"
            :class="
              activeMediaTypeFilter === 'image'
                ? 'exams-filter-btn--on'
                : 'exams-filter-btn--off'
            "
            @click="activeMediaTypeFilter = 'image'"
          >
            <i class="i-lucide-image w-3.5 h-3.5" /> Imagens
          </button>
          <button
            class="exams-filter-btn"
            :class="
              activeMediaTypeFilter === 'video'
                ? 'exams-filter-btn--on'
                : 'exams-filter-btn--off'
            "
            @click="activeMediaTypeFilter = 'video'"
          >
            <i class="i-lucide-video w-3.5 h-3.5" /> Vídeos
          </button>
          <button
            class="exams-filter-btn"
            :class="
              activeMediaTypeFilter === 'pdf'
                ? 'exams-filter-btn--on'
                : 'exams-filter-btn--off'
            "
            @click="activeMediaTypeFilter = 'pdf'"
          >
            <i class="i-lucide-file-text w-3.5 h-3.5" /> PDFs
          </button>
          <button
            class="exams-filter-btn"
            :class="
              activeMediaTypeFilter === 'document'
                ? 'exams-filter-btn--on'
                : 'exams-filter-btn--off'
            "
            @click="activeMediaTypeFilter = 'document'"
          >
            <i class="i-lucide-file-code-2 w-3.5 h-3.5" /> Documentos
          </button>
        </div>

        <!-- Empty state pasta vazia -->
        <div v-if="mediasInFolder.length === 0" class="exams-empty-state">
          <div class="exams-empty-icon">
            <i class="i-lucide-folder-open w-6 h-6" />
          </div>
          <p class="exams-empty-text">Esta pasta está vazia</p>
          <p class="exams-empty-hint">
            Faça upload ou arraste um arquivo de outra pasta
          </p>
        </div>

        <!-- Grade de arquivos -->
        <div
          v-else
          class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3"
        >
          <div
            v-for="media in mediasInFolder"
            :key="media.id"
            class="exams-card group relative"
            :class="{
              'exams-card--locked': mediaLockMap[media.id],
              'exam-card-dragging': draggedMediaId === media.id,
            }"
            draggable="true"
            @dragstart="onMediaDragStart($event, media.id)"
            @dragend="draggedMediaId = null"
          >
            <!-- Lock badge -->
            <div
              v-if="mediaLockMap[media.id]"
              class="exams-lock-badge"
              title="Arquivo bloqueado"
            >
              <i class="i-lucide-lock text-[10px] text-white" />
            </div>

            <!-- Thumbnail -->
            <div class="exams-thumb" @click="openMediaLightbox(media)">
              <img
                v-if="media.url && !media.mime_type?.includes('pdf')"
                :src="media.url"
                class="object-cover w-full h-full"
              />
              <div
                v-else-if="
                  media.mime_type?.includes('pdf') ||
                  media.file_name?.toLowerCase().endsWith('.pdf')
                "
                class="exams-thumb-pdf"
              >
                <div class="exams-thumb-pdf-icon">
                  <i class="i-lucide-file-text w-7 h-7 text-red-400" />
                </div>
                <span class="exams-thumb-pdf-label">PDF</span>
              </div>
              <i v-else class="i-lucide-image text-slate-600 text-4xl" />

              <!-- Overlay view -->
              <div class="exams-thumb-overlay">
                <div class="exams-thumb-eye">
                  <i class="i-lucide-eye text-white w-4 h-4" />
                </div>
              </div>
            </div>

            <!-- Footer -->
            <div class="exams-card-footer">
              <!-- Renomear inline -->
              <div
                v-if="renamingMediaId === media.id"
                class="flex items-center gap-1 mb-1.5"
              >
                <input
                  v-model="renamingMediaName"
                  class="flex-1 bg-slate-700 border border-slate-600 rounded px-1.5 py-0.5 text-[11px] text-slate-200 focus:outline-none focus:border-blue-500 min-w-0"
                  autofocus
                  @keyup.enter="confirmRenameMedia"
                  @keyup.escape="renamingMediaId = null"
                  @click.stop
                />
                <button
                  class="p-0.5 bg-blue-600 hover:bg-blue-500 rounded text-white shrink-0"
                  @click.stop="confirmRenameMedia"
                >
                  <i class="i-lucide-check text-xs" />
                </button>
              </div>
              <div v-else class="exams-card-name-row">
                <span class="exams-card-name">{{
                  media.file_name || 'Arquivo'
                }}</span>
                <span v-if="media.created_at" class="exams-card-date">{{
                  formatDate(media.created_at)
                }}</span>
              </div>

              <!-- Actions -->
              <div class="exams-card-actions">
                <span class="exams-card-category">{{ media.category }}</span>
                <button
                  class="exams-card-btn"
                  title="Renomear"
                  @click.stop="startRenameMedia(media)"
                >
                  <i class="i-lucide-pencil w-3 h-3" />
                </button>
                <a
                  :href="media.url"
                  :download="media.file_name || 'arquivo'"
                  class="exams-card-btn"
                  title="Baixar arquivo"
                  @click.stop
                >
                  <i class="i-lucide-download w-3 h-3" />
                </a>
                <button
                  v-if="!mediaLockMap[media.id]"
                  class="exams-card-btn"
                  title="Bloquear arquivo"
                  @click.stop="openLockModal(media.id, 'lock')"
                >
                  <i class="i-lucide-unlock w-3 h-3" />
                </button>
                <button
                  v-else
                  class="exams-card-btn exams-card-btn--locked"
                  title="Desbloquear arquivo"
                  @click.stop="openLockModal(media.id, 'unlock')"
                >
                  <i class="i-lucide-lock w-3 h-3" />
                </button>
                <button
                  class="exams-card-btn exams-card-btn--danger"
                  :class="{
                    'opacity-40 cursor-not-allowed': mediaLockMap[media.id],
                  }"
                  title="Excluir"
                  @click.stop="requestDeleteMedia(media)"
                >
                  <i class="i-lucide-trash-2 w-3 h-3" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal: Criar Pasta -->
    <div
      v-if="showCreateFolderModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
      @click.self="showCreateFolderModal = false"
    >
      <div
        class="bg-slate-900 border border-slate-700/60 rounded-2xl shadow-2xl w-full max-w-sm p-6"
      >
        <h3
          class="text-lg font-semibold text-slate-100 mb-4 flex items-center gap-2"
        >
          <i class="i-lucide-folder-plus text-blue-400" /> Nova Pasta
        </h3>
        <input
          v-model="newFolderName"
          class="w-full bg-slate-800 border border-slate-600 rounded-xl px-4 py-2.5 text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-blue-500 mb-4"
          placeholder="Nome da pasta..."
          autofocus
          @keyup.enter="createFolder"
        />
        <div class="flex gap-3 justify-end">
          <button
            class="btn-secondary text-sm"
            @click="showCreateFolderModal = false"
          >
            Cancelar
          </button>
          <button
            class="btn-primary text-sm"
            :disabled="!newFolderName.trim()"
            @click="createFolder"
          >
            <i class="i-lucide-check mr-1" /> Criar Pasta
          </button>
        </div>
      </div>
    </div>

    <!-- Modal: Renomear Pasta + Cor -->
    <div
      v-if="showRenameFolderModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
      @click.self="showRenameFolderModal = false"
    >
      <div
        class="bg-slate-900 border border-slate-700/60 rounded-2xl shadow-2xl w-full max-w-sm p-6"
      >
        <h3
          class="text-lg font-semibold text-slate-100 mb-4 flex items-center gap-2"
        >
          <i class="i-lucide-pencil text-blue-400" /> Renomear Pasta
        </h3>
        <label class="text-xs text-slate-400 font-medium mb-1 block"
          >Nome</label
        >
        <input
          v-model="renamingFolderName"
          class="w-full bg-slate-800 border border-slate-600 rounded-xl px-4 py-2.5 text-sm text-slate-200 placeholder-slate-500 focus:outline-none focus:border-blue-500 mb-4"
          placeholder="Nome da pasta..."
          autofocus
          @keyup.enter="confirmRenameFolder"
        />
        <label class="text-xs text-slate-400 font-medium mb-2 block"
          >Cor da pasta</label
        >
        <div class="flex flex-wrap gap-2 mb-5">
          <button
            v-for="color in FOLDER_COLORS"
            :key="color.value"
            class="w-7 h-7 rounded-full border-2 transition-all hover:scale-110 focus:outline-none"
            :style="{
              backgroundColor: color.value,
              borderColor:
                renamingFolderColor === color.value ? '#fff' : 'transparent',
            }"
            :title="color.label"
            @click="renamingFolderColor = color.value"
          />
        </div>
        <!-- Preview -->
        <div
          class="flex items-center gap-2 mb-4 px-3 py-2 rounded-xl bg-slate-800/60 border border-slate-700/50"
        >
          <i
            class="i-lucide-folder text-lg"
            :style="{ color: renamingFolderColor }"
          />
          <span
            class="text-sm font-medium"
            :style="{ color: renamingFolderColor }"
            >{{ renamingFolderName || 'Pré-visualização' }}</span
          >
        </div>
        <div class="flex gap-3 justify-end">
          <button
            class="btn-secondary text-sm"
            @click="showRenameFolderModal = false"
          >
            Cancelar
          </button>
          <button
            class="btn-primary text-sm"
            :disabled="!renamingFolderName.trim()"
            @click="confirmRenameFolder"
          >
            <i class="i-lucide-check mr-1" /> Salvar
          </button>
        </div>
      </div>
    </div>

    <!-- Modal: Excluir Pasta -->
    <div
      v-if="showDeleteFolderModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
      @click.self="
        showDeleteFolderModal = false;
        folderToDelete = null;
        deleteBlockedMessage = '';
      "
    >
      <div
        class="bg-slate-900 border border-slate-700/60 rounded-2xl shadow-2xl w-full max-w-sm p-6"
      >
        <!-- Blocked: has locked files -->
        <template v-if="deleteBlockedMessage">
          <div class="flex items-center gap-3 mb-4">
            <div
              class="w-10 h-10 rounded-full bg-amber-500/10 border border-amber-500/20 flex items-center justify-center"
            >
              <i class="i-lucide-lock text-amber-400 text-lg" />
            </div>
            <h3 class="text-lg font-semibold text-amber-300">
              Exclusão Bloqueada
            </h3>
          </div>
          <p class="text-sm text-slate-400 mb-5">
            {{ deleteBlockedMessage }}
          </p>
          <div class="flex justify-end">
            <button
              class="btn-primary text-sm"
              @click="
                showDeleteFolderModal = false;
                folderToDelete = null;
                deleteBlockedMessage = '';
              "
            >
              Entendido
            </button>
          </div>
        </template>

        <!-- Normal delete -->
        <template v-else>
          <div class="flex items-center gap-3 mb-4">
            <div
              class="w-10 h-10 rounded-full bg-red-500/10 border border-red-500/20 flex items-center justify-center"
            >
              <i class="i-lucide-folder-minus text-red-400 text-lg" />
            </div>
            <h3 class="text-lg font-semibold text-slate-100">Excluir Pasta</h3>
          </div>
          <p class="text-sm text-slate-400 mb-5">
            Tem certeza que deseja excluir a pasta
            <strong class="text-slate-200">"{{ folderToDelete?.name }}"</strong
            >? Os arquivos dentro serão movidos para a raiz.
          </p>
          <div class="flex gap-3 justify-end">
            <button
              class="btn-secondary text-sm"
              @click="
                showDeleteFolderModal = false;
                folderToDelete = null;
              "
            >
              Cancelar
            </button>
            <button
              class="bg-red-600 hover:bg-red-500 text-white text-sm font-medium px-4 py-2 rounded-xl transition-colors"
              @click="confirmDeleteFolder"
            >
              Excluir
            </button>
          </div>
        </template>
      </div>
    </div>

    <!-- Modal: Lock/Unlock -->
    <div
      v-if="showLockModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
      @click.self="
        showLockModal = false;
        lockPinError = '';
      "
    >
      <div
        class="bg-slate-900 border border-slate-700/60 rounded-2xl shadow-2xl w-full max-w-sm p-6"
      >
        <div class="flex items-center gap-3 mb-4">
          <div
            class="w-10 h-10 rounded-full flex items-center justify-center"
            :class="
              lockActionType === 'lock'
                ? 'bg-amber-500/10 border border-amber-500/20'
                : 'bg-emerald-500/10 border border-emerald-500/20'
            "
          >
            <i
              :class="
                lockActionType === 'lock'
                  ? 'i-lucide-lock text-amber-400'
                  : 'i-lucide-unlock text-emerald-400'
              "
              class="text-lg"
            />
          </div>
          <h3 class="text-lg font-semibold text-slate-100">
            {{
              lockActionType === 'lock'
                ? 'Bloquear Arquivo'
                : 'Desbloquear Arquivo'
            }}
          </h3>
        </div>
        <p class="text-sm text-slate-400 mb-4">
          {{
            lockActionType === 'lock'
              ? 'Digite o código de segurança para bloquear este arquivo contra exclusão acidental.'
              : 'Digite o código de segurança para desbloquear este arquivo.'
          }}
        </p>
        <input
          v-model="lockPinInput"
          type="password"
          class="w-full bg-slate-800 border rounded-xl px-4 py-2.5 text-sm text-slate-200 placeholder-slate-500 focus:outline-none mb-1"
          :class="
            lockPinError
              ? 'border-red-500'
              : 'border-slate-600 focus:border-blue-500'
          "
          placeholder="Código de segurança"
          autofocus
          @keyup.enter="confirmLockAction"
        />
        <p v-if="lockPinError" class="text-xs text-red-400 mb-3">
          {{ lockPinError }}
        </p>
        <div v-else class="mb-3" />
        <div class="flex gap-3 justify-end">
          <button
            class="btn-secondary text-sm"
            @click="
              showLockModal = false;
              lockPinError = '';
            "
          >
            Cancelar
          </button>
          <button
            class="text-sm font-medium px-4 py-2 rounded-xl transition-colors text-white"
            :class="
              lockActionType === 'lock'
                ? 'bg-amber-600 hover:bg-amber-500'
                : 'bg-emerald-600 hover:bg-emerald-500'
            "
            @click="confirmLockAction"
          >
            <i
              :class="
                lockActionType === 'lock'
                  ? 'i-lucide-lock mr-1'
                  : 'i-lucide-unlock mr-1'
              "
            />
            Confirmar
          </button>
        </div>
      </div>
    </div>

    <!-- Modal: Excluir Arquivo -->
    <div
      v-if="showDeleteMediaModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm"
      @click.self="
        showDeleteMediaModal = false;
        mediaToDelete = null;
      "
    >
      <div
        class="bg-slate-900 border border-slate-700/60 rounded-2xl shadow-2xl w-full max-w-sm p-6"
      >
        <div class="flex items-center gap-3 mb-4">
          <div
            class="w-10 h-10 rounded-full bg-red-500/10 border border-red-500/20 flex items-center justify-center"
          >
            <i class="i-lucide-trash-2 text-red-400 text-lg" />
          </div>
          <h3 class="text-lg font-semibold text-slate-100">Excluir Arquivo</h3>
        </div>
        <p class="text-sm text-slate-400 mb-5">
          Tem certeza que deseja excluir o arquivo
          <strong class="text-slate-200"
            >"{{ mediaToDelete?.file_name || 'este arquivo' }}"</strong
          >? Esta ação não pode ser desfeita.
        </p>
        <div class="flex gap-3 justify-end">
          <button
            class="btn-secondary text-sm"
            @click="
              showDeleteMediaModal = false;
              mediaToDelete = null;
            "
          >
            Cancelar
          </button>
          <button
            class="bg-red-600 hover:bg-red-500 text-white text-sm font-medium px-4 py-2 rounded-xl transition-colors disabled:opacity-50"
            :disabled="isDeletingMedia"
            @click="confirmDeleteMedia"
          >
            {{ isDeletingMedia ? 'Excluindo...' : 'Excluir' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
