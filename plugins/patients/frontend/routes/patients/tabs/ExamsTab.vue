<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * ExamsTab — Aba "Exames e Imagens" do prontuário do paciente.
 *
 * Componente extraído de Record.vue (que tinha 18.6k linhas com 12 abas inline).
 * Auto-suficiente: lê patientId da rota, faz seu próprio fetch e seu próprio
 * gerenciamento de estado (mídias, pastas, drag/drop, modais, lightbox).
 *
 * Backend: ExamMediasController + ExamFoldersController (REST com AR; ver
 * docs/03-engineering/audit-exames-imagens.md).
 *
 * O componente carrega no mount e é responsável por seu próprio refresh.
 * Pai (Record.vue) só precisa de `<ExamsTab v-if="activeTab === 'exams'" />`.
 */
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import ExamMediasAPI from '@plugins/patients/frontend/api/patients/examMedias';
import ExamFoldersAPI from '@plugins/patients/frontend/api/patients/examFolders';

const route = useRoute();

// ── Mídias ─────────────────────────────────────────────────
const examMedias = ref([]);
const isUploadingMedia = ref(false);
const uploadProgress = ref(0);
const lightboxMedia = ref(null);
const mediaFileInput = ref(null);

// ── Pastas (estado e UI) ───────────────────────────────────
// `'root'` é apenas sentinel client-side ("Todos os arquivos") — não existe registro com esse id.
const examFolders = ref([]);
const activeFolderId = ref('root');
const activeMediaTypeFilter = ref('all');
const draggedMediaId = ref(null);
const isDraggingOverFolder = ref(null);

// Modal: criar pasta
const showCreateFolderModal = ref(false);
const newFolderName = ref('');
const isCreatingFolder = ref(false);

// Modal: renomear pasta + cor
const showRenameFolderModal = ref(false);
const renamingFolderId = ref(null);
const renamingFolderName = ref('');
const renamingFolderColor = ref('#60a5fa');

const FOLDER_COLORS = [
  { label: 'Azul', value: '#60a5fa' },
  { label: 'Violeta', value: '#a78bfa' },
  { label: 'Rosa', value: '#f472b6' },
  { label: 'Laranja', value: '#fb923c' },
  { label: 'Amarelo', value: '#fbbf24' },
  { label: 'Verde', value: '#34d399' },
  { label: 'Ciano', value: '#22d3ee' },
  { label: 'Vermelho', value: '#f87171' },
  { label: 'Branco', value: '#cbd5e1' },
  { label: 'Cinza', value: '#64748b' },
];

// Modal: excluir pasta
const showDeleteFolderModal = ref(false);
const folderToDelete = ref(null);
const deleteBlockedMessage = ref('');

// Lock/Unlock (PIN client-side é só UX; integridade real está em ExamMediasController#destroy)
const showLockModal = ref(false);
const lockTargetMediaId = ref(null);
const lockActionType = ref('lock'); // 'lock' or 'unlock'
const lockPinInput = ref('');
const lockPinError = ref('');
const LOCK_PIN = '123';

// Renomear mídia
const renamingMediaId = ref(null);
const renamingMediaName = ref('');

// Excluir mídia
const showDeleteMediaModal = ref(false);
const mediaToDelete = ref(null);
const isDeletingMedia = ref(false);

// Estado puramente de UI (não persistido)
const expandedFolderIds = ref(new Set());

// Drag & drop de pastas na sidebar
const draggedFolderId = ref(null);
const dragOverFolderTarget = ref(null); // { id, position: 'before'|'after'|'inside' }
const dragPromoteActive = ref(false);

// ── Helpers ────────────────────────────────────────────────
const formatDate = dateStr => {
  if (!dateStr) return '—';
  return formatDateBR(dateStr) || '—';
};

const isMediaLocked = media => Boolean(media?.locked);

// Helpers de classificação por mime/extensão (usados em galeria e lightbox)
const isVideo = m =>
  (m?.mime_type || '').startsWith('video/') ||
  /\.(mp4|mov|webm|avi|mkv|m4v)$/i.test(m?.file_name || '');
const isPdf = m =>
  (m?.mime_type || '').includes('pdf') ||
  /\.pdf$/i.test(m?.file_name || '');
const isImage = m =>
  (m?.mime_type || '').startsWith('image/') ||
  /\.(jpe?g|png|gif|webp|heic|heif)$/i.test(m?.file_name || '');

// ── Computeds ──────────────────────────────────────────────
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
  if (folderId === 'root') return [];
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

// Conta itens totais de uma pasta (subpastas + arquivos diretos + arquivos das subpastas)
const getTotalItemCount = folderId => {
  const subs = getSubfolders(folderId);
  const directFiles = examMedias.value.filter(
    m => (m.folder_id || 'root') === folderId
  ).length;
  return (
    subs.length +
    directFiles +
    subs.reduce(
      (sum, sub) =>
        sum +
        examMedias.value.filter(m => (m.folder_id || 'root') === sub.id).length,
      0
    )
  );
};

const mediasInFolder = computed(() => {
  let list = examMedias.value;

  if (activeFolderId.value !== 'root') {
    list = list.filter(m => m.folder_id === activeFolderId.value);
  }

  if (activeMediaTypeFilter.value !== 'all') {
    list = list.filter(m => {
      const mime = (m.mime_type || '').toLowerCase();
      const ext = (m.file_name || '').toLowerCase().split('.').pop();

      switch (activeMediaTypeFilter.value) {
        case 'image':
          return (
            mime.startsWith('image/') ||
            ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'].includes(ext)
          );
        case 'video':
          return (
            mime.startsWith('video/') ||
            ['mp4', 'mov', 'avi', 'mkv', 'webm'].includes(ext)
          );
        case 'pdf':
          return mime.includes('pdf') || ext === 'pdf';
        case 'document':
          return (
            mime.includes('document') ||
            mime.includes('msword') ||
            mime.includes('excel') ||
            mime.includes('csv') ||
            mime.includes('presentation') ||
            ['doc', 'docx', 'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'rtf', 'txt'].includes(ext)
          );
        default:
          return true;
      }
    });
  }

  return list;
});

// ── Fetch ──────────────────────────────────────────────────
const fetchExamMedias = async () => {
  try {
    const res = await ExamMediasAPI.get(route.params.patientId);
    examMedias.value = res.data?.data || res.data || [];
  } catch (error) {
    // ignora — UI mantém última lista válida
  }
};

const loadFolderData = async patientId => {
  if (!patientId) return;
  try {
    const { data } = await ExamFoldersAPI.getAll(patientId);
    examFolders.value = data?.data || [];
  } catch (e) {
    examFolders.value = [];
  }
};

// ── Pastas: drag/reorder/persistência ─────────────────────
const isAncestorOf = (potentialAncestorId, folderId) => {
  let current = examFolders.value.find(f => f.id === folderId);
  while (current?.parent_id) {
    if (current.parent_id === potentialAncestorId) return true;
    current = examFolders.value.find(f => f.id === current.parent_id);
  }
  return false;
};

// Persiste reorder; em caso de erro, recarrega do servidor para corrigir divergência otimista.
const persistFolderReorder = async items => {
  if (!items.length) return;
  try {
    await ExamFoldersAPI.reorder(route.params.patientId, items);
  } catch (e) {
    await loadFolderData(route.params.patientId);
  }
};

// Renumera siblings de um parent (compactando posições) e devolve items para reorder.
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

const onFolderSidebarDragStart = (e, folder) => {
  draggedFolderId.value = folder.id;
  e.dataTransfer.effectAllowed = 'move';
};

const promoteFolderToRoot = async () => {
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

  draggedFolderId.value = null;
  dragOverFolderTarget.value = null;
  await persistFolderReorder(items);
};

const onFolderSidebarDragOver = (e, folder) => {
  e.preventDefault();
  e.stopPropagation();
  if (!draggedFolderId.value || draggedFolderId.value === folder.id) return;
  const rect = e.currentTarget.getBoundingClientRect();
  const y = e.clientY - rect.top;
  const pct = y / rect.height;
  let position;
  if (pct < 0.28) position = 'before';
  else if (pct > 0.72) position = 'after';
  else position = 'inside';
  dragOverFolderTarget.value = { id: folder.id, position };
};

const onFolderSidebarDragLeave = () => {
  dragOverFolderTarget.value = null;
};

const onFolderSidebarDrop = async (e, targetFolder) => {
  e.preventDefault();
  e.stopPropagation();
  if (!draggedFolderId.value || draggedFolderId.value === targetFolder.id) {
    draggedFolderId.value = null;
    dragOverFolderTarget.value = null;
    return;
  }
  const dragged = examFolders.value.find(f => f.id === draggedFolderId.value);
  if (!dragged) return;

  const pos = dragOverFolderTarget.value?.position;
  const oldParent = dragged.parent_id ?? null;
  let items = [];

  if (pos === 'inside') {
    if (targetFolder.parent_id) {
      useAlert(
        'Não é possível criar subpastas dentro de subpastas. Máximo de 1 nível de aninhamento permitido.'
      );
      draggedFolderId.value = null;
      dragOverFolderTarget.value = null;
      return;
    }
    if (isAncestorOf(draggedFolderId.value, targetFolder.id)) {
      useAlert('Não é possível criar uma hierarquia circular.');
      draggedFolderId.value = null;
      dragOverFolderTarget.value = null;
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
    useAlert(`"${dragged.name}" movida para dentro de "${targetFolder.name}"`);
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

  draggedFolderId.value = null;
  dragOverFolderTarget.value = null;
  await persistFolderReorder(items);
};

// ── Pastas: CRUD ───────────────────────────────────────────
const createFolder = async () => {
  const name = newFolderName.value.trim();
  if (!name || isCreatingFolder.value) return;
  isCreatingFolder.value = true;
  const maxPos = topLevelFolders.value.reduce(
    (m, f) => Math.max(m, f.position ?? 0),
    -1
  );
  try {
    const { data } = await ExamFoldersAPI.create(route.params.patientId, {
      name,
      color: '#60a5fa',
      parent_id: null,
      position: maxPos + 1,
    });
    examFolders.value.push(data);
    newFolderName.value = '';
    showCreateFolderModal.value = false;
  } catch (error) {
    const errs = error?.response?.data?.errors;
    useAlert(Array.isArray(errs) ? errs.join('. ') : 'Erro ao criar pasta.');
  } finally {
    isCreatingFolder.value = false;
  }
};

const startRenameFolder = folder => {
  renamingFolderId.value = folder.id;
  renamingFolderName.value = folder.name;
  renamingFolderColor.value = folder.color || '#60a5fa';
  showRenameFolderModal.value = true;
};

const confirmRenameFolder = async () => {
  const name = renamingFolderName.value.trim();
  if (!name) return;
  const folder = examFolders.value.find(f => f.id === renamingFolderId.value);
  if (!folder) return;
  const previousName = folder.name;
  const previousColor = folder.color;
  folder.name = name;
  folder.color = renamingFolderColor.value;
  showRenameFolderModal.value = false;
  renamingFolderId.value = null;
  renamingFolderName.value = '';
  try {
    await ExamFoldersAPI.update(route.params.patientId, folder.id, {
      name,
      color: renamingFolderColor.value,
    });
  } catch (error) {
    folder.name = previousName;
    folder.color = previousColor;
    const errs = error?.response?.data?.errors;
    useAlert(Array.isArray(errs) ? errs.join('. ') : 'Erro ao renomear pasta.');
  }
};

const requestDeleteFolder = folder => {
  // Bloqueia exclusão se houver mídia bloqueada na pasta ou em subpastas
  const subIds = getSubfolders(folder.id).map(s => s.id);
  const containedIds = [folder.id, ...subIds];
  const hasLockedMedia = examMedias.value.some(
    m => containedIds.includes(m.folder_id) && isMediaLocked(m)
  );
  if (hasLockedMedia) {
    deleteBlockedMessage.value =
      'Há um ou mais arquivos bloqueados dentro desta pasta. Desbloqueie-os antes de excluir a pasta.';
    folderToDelete.value = folder;
    showDeleteFolderModal.value = true;
    return;
  }
  deleteBlockedMessage.value = '';
  folderToDelete.value = folder;
  showDeleteFolderModal.value = true;
};

const confirmDeleteFolder = async () => {
  if (!folderToDelete.value || deleteBlockedMessage.value) {
    showDeleteFolderModal.value = false;
    folderToDelete.value = null;
    deleteBlockedMessage.value = '';
    return;
  }
  const target = folderToDelete.value;
  showDeleteFolderModal.value = false;
  folderToDelete.value = null;
  deleteBlockedMessage.value = '';
  try {
    await ExamFoldersAPI.delete(route.params.patientId, target.id);
    const subIds = getSubfolders(target.id).map(s => s.id);
    const removedIds = new Set([target.id, ...subIds]);
    examFolders.value = examFolders.value.filter(f => !removedIds.has(f.id));
    if (removedIds.has(activeFolderId.value)) activeFolderId.value = 'root';
    // Re-fetch medias para refletir folder_id zerado pelo backend
    await fetchExamMedias();
  } catch (error) {
    useAlert('Erro ao excluir pasta.');
  }
};

// ── Mídia: drag/lock/rename/delete ─────────────────────────
//
// Drag image custom: o default do browser é uma "sombra" do card inteiro
// (translúcida, atrapalha visualmente). Substituímos por uma pílula compacta
// com nome do arquivo + ícone, ancorada no cursor.
const onMediaDragStart = (e, mediaId) => {
  draggedMediaId.value = mediaId;
  e.dataTransfer.effectAllowed = 'move';

  const media = examMedias.value.find(m => m.id === mediaId);
  const label = media?.file_name || 'Arquivo';

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

  e.dataTransfer.setDragImage(ghost, 16, 16);

  // Cleanup após o browser capturar a imagem (próximo tick é seguro).
  requestAnimationFrame(() => {
    if (ghost.parentNode) ghost.parentNode.removeChild(ghost);
  });
};

const onFolderDragOver = (e, folderId) => {
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';
  isDraggingOverFolder.value = folderId;
};

const onFolderDragLeave = () => {
  isDraggingOverFolder.value = null;
};

const onFolderDrop = async (e, folderId) => {
  e.preventDefault();
  isDraggingOverFolder.value = null;
  const mediaId = draggedMediaId.value;
  draggedMediaId.value = null;
  if (!mediaId) return;
  const media = examMedias.value.find(m => m.id === mediaId);
  if (!media) return;
  const targetId = folderId === 'root' ? null : folderId;
  if ((media.folder_id || null) === targetId) return;

  const previous = media.folder_id;
  media.folder_id = targetId;
  media.exam_folder_id = targetId;
  try {
    await ExamMediasAPI.update(route.params.patientId, mediaId, {
      exam_folder_id: targetId,
    });
    useAlert('Arquivo movido com sucesso!');
  } catch (error) {
    media.folder_id = previous;
    media.exam_folder_id = previous;
    useAlert('Erro ao mover arquivo.');
  }
};

const openLockModal = (mediaId, action) => {
  lockTargetMediaId.value = mediaId;
  lockActionType.value = action;
  lockPinInput.value = '';
  lockPinError.value = '';
  showLockModal.value = true;
};

const confirmLockAction = async () => {
  if (lockPinInput.value !== LOCK_PIN) {
    lockPinError.value = 'Código incorreto. Tente novamente.';
    return;
  }
  const mediaId = lockTargetMediaId.value;
  const desiredLocked = lockActionType.value === 'lock';
  const media = examMedias.value.find(m => m.id === mediaId);
  if (!media) return;
  const previous = media.locked;
  media.locked = desiredLocked;
  showLockModal.value = false;
  lockTargetMediaId.value = null;
  lockPinInput.value = '';
  lockPinError.value = '';
  try {
    await ExamMediasAPI.update(route.params.patientId, mediaId, {
      locked: desiredLocked,
    });
    useAlert(
      desiredLocked
        ? 'Arquivo bloqueado com sucesso!'
        : 'Arquivo desbloqueado com sucesso!'
    );
  } catch (error) {
    media.locked = previous;
    useAlert('Erro ao alterar bloqueio.');
  }
};

const startRenameMedia = media => {
  renamingMediaId.value = media.id;
  renamingMediaName.value = media.file_name || '';
};

const confirmRenameMedia = async () => {
  const name = renamingMediaName.value.trim();
  if (!name) return;
  const mediaId = renamingMediaId.value;
  const media = examMedias.value.find(m => m.id === mediaId);
  if (!media) return;
  const previous = media.file_name;
  media.file_name = name;
  renamingMediaId.value = null;
  renamingMediaName.value = '';
  try {
    await ExamMediasAPI.update(route.params.patientId, mediaId, {
      file_name: name,
    });
  } catch (error) {
    media.file_name = previous;
    useAlert('Erro ao renomear arquivo.');
  }
};

const requestDeleteMedia = media => {
  if (isMediaLocked(media)) {
    useAlert(
      'Este arquivo está bloqueado e não pode ser excluído. Desbloqueie-o primeiro.'
    );
    return;
  }
  mediaToDelete.value = media;
  showDeleteMediaModal.value = true;
};

const confirmDeleteMedia = async () => {
  if (!mediaToDelete.value) return;
  isDeletingMedia.value = true;
  try {
    await ExamMediasAPI.delete(route.params.patientId, mediaToDelete.value.id);
    useAlert('Arquivo excluído com sucesso.');
    await fetchExamMedias();
  } catch (error) {
    const errs = error?.response?.data?.errors;
    useAlert(Array.isArray(errs) ? errs.join('. ') : 'Erro ao excluir arquivo.');
  } finally {
    isDeletingMedia.value = false;
    showDeleteMediaModal.value = false;
    mediaToDelete.value = null;
  }
};

// ── Upload ─────────────────────────────────────────────────
// Limites por tipo — alinhados com backend (ExamMedia::SIZE_LIMITS).
// Mantenha em sync com plugins/patients/app/models/exam_media.rb.
const UPLOAD_LIMITS = {
  image: 5 * 1024 * 1024, // 5MB
  pdf: 10 * 1024 * 1024, // 10MB
  video: 20 * 1024 * 1024, // 20MB
};
const ACCEPTED_MIME = {
  image: /^image\/(jpeg|png|gif|webp|heic|heif)$/i,
  pdf: /^application\/pdf$/i,
  video: /^video\/(mp4|quicktime|webm)$/i,
};
const ACCEPTED_EXT = {
  image: /\.(jpe?g|png|gif|webp|heic|heif)$/i,
  pdf: /\.pdf$/i,
  video: /\.(mp4|mov|webm)$/i,
};

const classifyUpload = file => {
  const name = file.name || '';
  const type = file.type || '';
  for (const kind of ['image', 'pdf', 'video']) {
    if (ACCEPTED_MIME[kind].test(type) || ACCEPTED_EXT[kind].test(name)) {
      return kind;
    }
  }
  return null;
};

const detectMediaCategory = file => {
  const kind = classifyUpload(file);
  if (kind === 'image') return 'foto_clinica';
  if (kind === 'video') return 'video';
  if (kind === 'pdf') return 'laudo';
  return 'outro';
};

const formatMb = bytes => `${Math.round(bytes / 1024 / 1024)}MB`;

const triggerMediaUpload = () => {
  if (mediaFileInput.value) mediaFileInput.value.click();
};

const onMediaFileSelected = async event => {
  const file = event.target.files[0];
  if (!file) return;

  const kind = classifyUpload(file);
  if (!kind) {
    useAlert(
      'Formato não suportado. Aceitos: imagem (JPG/PNG/WEBP/HEIC), PDF ou vídeo (MP4/MOV/WEBM).'
    );
    event.target.value = null;
    return;
  }

  const limit = UPLOAD_LIMITS[kind];
  if (file.size > limit) {
    const labels = { image: 'imagem', pdf: 'PDF', video: 'vídeo' };
    useAlert(
      `Arquivo muito grande. Máximo ${formatMb(limit)} para ${labels[kind]}.`
    );
    event.target.value = null;
    return;
  }

  try {
    isUploadingMedia.value = true;
    uploadProgress.value = 0;
    const category = detectMediaCategory(file);
    await ExamMediasAPI.create(route.params.patientId, {
      file,
      category,
      onUploadProgress: e => {
        if (!e.total) return;
        uploadProgress.value = Math.round((e.loaded * 100) / e.total);
      },
    });
    useAlert('Mídia enviada com sucesso!');
    await fetchExamMedias();
  } catch (error) {
    const errs = error?.response?.data?.errors;
    const msg = Array.isArray(errs)
      ? errs.join('. ')
      : errs || 'Erro no upload de mídia.';
    useAlert(msg);
  } finally {
    isUploadingMedia.value = false;
    uploadProgress.value = 0;
    event.target.value = null;
  }
};

// ── Lightbox ───────────────────────────────────────────────
const openMediaLightbox = media => {
  lightboxMedia.value = media;
};

const handleLightboxKey = e => {
  if (e.key === 'Escape') lightboxMedia.value = null;
};

// ── Lifecycle ──────────────────────────────────────────────
onMounted(() => {
  fetchExamMedias();
  loadFolderData(route.params.patientId);
  window.addEventListener('keydown', handleLightboxKey);
});

onUnmounted(() => {
  window.removeEventListener('keydown', handleLightboxKey);
});
</script>

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
        <p class="text-xs text-slate-500 mt-1">
          Aceitos: imagens (JPG, PNG, WEBP, HEIC) até 5MB · PDF até 10MB · vídeo
          (MP4, MOV, WEBM) até 20MB
        </p>
      </div>
      <div class="flex items-center gap-3">
        <input
          ref="mediaFileInput"
          type="file"
          class="hidden"
          accept="image/jpeg,image/png,image/gif,image/webp,image/heic,image/heif,application/pdf,video/mp4,video/webm,video/quicktime"
          @change="onMediaFileSelected"
        />
        <button
          class="geral-header-btn"
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
          {{ isUploadingMedia ? `Enviando... ${uploadProgress}%` : 'Fazer Upload' }}
        </button>
      </div>
    </div>

    <!-- Barra de progresso de upload -->
    <div v-if="isUploadingMedia" class="exams-upload-progress mb-4">
      <div
        class="exams-upload-progress-bar"
        :style="{ width: `${uploadProgress}%` }"
      />
      <span class="exams-upload-progress-label"
        >Enviando arquivo... {{ uploadProgress }}%</span
      >
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

        <!-- Pastas top-level -->
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
              <!-- Indicador ANTES sub -->
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

              <!-- Indicador DEPOIS sub -->
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
              'exams-card--locked': media.locked,
              'exam-card-dragging': draggedMediaId === media.id,
            }"
            draggable="true"
            @dragstart="onMediaDragStart($event, media.id)"
            @dragend="draggedMediaId = null"
          >
            <!-- Lock badge -->
            <div
              v-if="media.locked"
              class="exams-lock-badge"
              title="Arquivo bloqueado"
            >
              <i class="i-lucide-lock text-[10px] text-white" />
            </div>

            <!-- Thumbnail -->
            <div class="exams-thumb" @click="openMediaLightbox(media)">
              <video
                v-if="isVideo(media) && media.url"
                :src="media.url"
                class="object-cover w-full h-full"
                preload="metadata"
                muted
                playsinline
              />
              <img
                v-else-if="isImage(media) && (media.thumbnail_url || media.url)"
                :src="media.thumbnail_url || media.url"
                class="object-cover w-full h-full"
                loading="lazy"
              />
              <div v-else-if="isPdf(media)" class="exams-thumb-pdf">
                <div class="exams-thumb-pdf-icon">
                  <i class="i-lucide-file-text w-7 h-7 text-red-400" />
                </div>
                <span class="exams-thumb-pdf-label">PDF</span>
              </div>
              <i v-else class="i-lucide-file text-slate-600 text-4xl" />

              <!-- Badge de tipo de mídia (canto superior direito) -->
              <div v-if="isVideo(media)" class="exams-thumb-badge">
                <i class="i-lucide-play w-3 h-3" />
                <span>VÍDEO</span>
              </div>

              <!-- Overlay view -->
              <div class="exams-thumb-overlay">
                <div class="exams-thumb-eye">
                  <i class="i-lucide-eye w-4 h-4" />
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
                  class="flex-1 h-6 bg-white dark:bg-slate-700 border border-slate-300 dark:border-slate-600 rounded px-1.5 text-[11px] text-slate-800 dark:text-slate-100 focus:outline-none focus:border-blue-500 dark:focus:border-blue-500 min-w-0"
                  autofocus
                  @keyup.enter="confirmRenameMedia"
                  @keyup.escape="renamingMediaId = null"
                  @click.stop
                />
                <button
                  class="h-6 w-6 p-0 flex items-center justify-center bg-blue-600 hover:bg-blue-500 rounded text-white shrink-0"
                  @click.stop="confirmRenameMedia"
                >
                  <i class="i-lucide-check text-base leading-none" />
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
                  v-if="!media.locked"
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
                  :class="{ 'opacity-40 cursor-not-allowed': media.locked }"
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
        class="record-modal-box rounded-2xl shadow-xl w-full max-w-sm p-6 border"
      >
        <h3
          class="record-modal-title text-lg font-semibold mb-4 flex items-center gap-2"
        >
          <i class="i-lucide-folder-plus text-blue-400" /> Nova Pasta
        </h3>
        <input
          v-model="newFolderName"
          class="record-modal-input w-full rounded-xl px-4 py-2.5 text-sm focus:outline-none mb-4 border"
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
            :disabled="!newFolderName.trim() || isCreatingFolder"
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
        class="record-modal-box rounded-2xl shadow-xl w-full max-w-sm p-6 border"
      >
        <h3
          class="record-modal-title text-lg font-semibold mb-4 flex items-center gap-2"
        >
          <i class="i-lucide-pencil text-blue-400" /> Renomear Pasta
        </h3>
        <label class="record-modal-label text-xs font-medium mb-1 block"
          >Nome</label
        >
        <input
          v-model="renamingFolderName"
          class="record-modal-input w-full rounded-xl px-4 py-2.5 text-sm focus:outline-none mb-4 border"
          placeholder="Nome da pasta..."
          autofocus
          @keyup.enter="confirmRenameFolder"
        />
        <label class="record-modal-label text-xs font-medium mb-2 block"
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
          class="record-modal-preview flex items-center gap-2 mb-4 px-3 py-2 rounded-xl border"
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
        class="record-modal-box rounded-2xl shadow-xl w-full max-w-sm p-6 border"
      >
        <!-- Bloqueado: tem arquivos lockados -->
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
          <p class="record-modal-muted text-sm mb-5">
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

        <!-- Exclusão normal -->
        <template v-else>
          <div class="flex items-center gap-3 mb-4">
            <div
              class="w-10 h-10 rounded-full bg-red-500/10 border border-red-500/20 flex items-center justify-center"
            >
              <i class="i-lucide-folder-minus text-red-400 text-lg" />
            </div>
            <h3 class="record-modal-title text-lg font-semibold">
              Excluir Pasta
            </h3>
          </div>
          <p class="record-modal-muted text-sm mb-5">
            Tem certeza que deseja excluir a pasta
            <strong class="record-modal-title"
              >"{{ folderToDelete?.name }}"</strong
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
              lockActionType === 'lock' ? 'Bloquear Arquivo' : 'Desbloquear Arquivo'
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

  <!-- Lightbox: Visualizar Mídia (raiz separada para overlay fullscreen) -->
  <div
    v-if="lightboxMedia"
    class="fixed inset-0 z-[99999] bg-black/90 backdrop-blur-sm flex flex-col"
    @click.self="lightboxMedia = null"
  >
    <!-- Header (apenas botões; lightbox sempre dark independente do tema) -->
    <div class="flex items-center justify-end px-6 py-4 gap-2">
      <a
        :href="lightboxMedia.url"
        target="_blank"
        rel="noopener noreferrer"
        title="Abrir em nova aba"
        class="h-9 w-9 rounded-lg bg-[#1e293b] hover:bg-[#334155] text-white flex items-center justify-center transition-colors border-0 cursor-pointer no-underline"
      >
        <i class="i-lucide-download w-4 h-4" />
      </a>
      <button
        title="Fechar"
        class="h-9 w-9 rounded-lg bg-[#1e293b] hover:bg-[#334155] text-white flex items-center justify-center transition-colors border-0 cursor-pointer"
        @click="lightboxMedia = null"
      >
        <i class="i-lucide-x w-4 h-4" />
      </button>
    </div>
    <!-- Conteúdo -->
    <div class="flex-1 flex items-center justify-center p-4 overflow-hidden">
      <template v-if="isPdf(lightboxMedia)">
        <iframe
          :src="lightboxMedia.url"
          class="w-full h-full rounded-lg bg-white"
          style="max-height: calc(100vh - 120px)"
        />
      </template>
      <template v-else-if="isVideo(lightboxMedia)">
        <video
          :src="lightboxMedia.url"
          class="max-w-full max-h-full rounded-lg bg-black"
          style="max-height: calc(100vh - 120px)"
          controls
          autoplay
          playsinline
        />
      </template>
      <template v-else>
        <img
          :src="lightboxMedia.url"
          class="max-w-full max-h-full object-contain rounded-lg"
          style="max-height: calc(100vh - 120px)"
        />
      </template>
    </div>
  </div>
</template>

<style scoped>
/* ═══════════════════════════════════════════
   EXAMES E IMAGENS — estilos exclusivos
═══════════════════════════════════════════ */

/* Breadcrumb */
.exams-breadcrumb {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-bottom: 16px;
  font-size: 13px;
}
.exams-breadcrumb-sep {
  color: #334155;
  width: 12px;
  height: 12px;
}
.exams-breadcrumb-link {
  font-weight: 500;
  transition: opacity 0.15s;
}
.exams-breadcrumb-link:hover {
  opacity: 0.75;
}
.exams-breadcrumb-count {
  margin-left: 4px;
  font-size: 11px;
  color: #475569;
}
.exams-drag-hint {
  margin-left: 12px;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: #60a5fa;
  animation: pulse 1.5s infinite;
}

/* Sidebar de pastas */
.exams-sidebar {
  width: 196px;
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.exams-sidebar-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 500;
  width: 100%;
  text-align: left;
  transition:
    background 0.15s,
    color 0.15s;
  border: 1px solid transparent;
}
.exams-sidebar-item--active {
  background: rgba(59, 130, 246, 0.12);
  color: #93c5fd;
  border-color: rgba(59, 130, 246, 0.2);
}
.exams-sidebar-item--idle {
  color: #64748b;
}
.exams-sidebar-item--idle:hover {
  background: rgba(255, 255, 255, 0.04);
  color: #cbd5e1;
}
.exams-sidebar-section-label {
  padding: 10px 12px 4px;
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: #475569;
}

/* Filtros de tipo (pills) */
.exams-filters {
  display: flex;
  align-items: center;
  gap: 6px;
  overflow-x: auto;
  padding-bottom: 2px;
}
.exams-filter-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border-radius: 99px;
  font-size: 12px;
  font-weight: 500;
  white-space: nowrap;
  border: 1px solid transparent;
  transition:
    background 0.15s,
    color 0.15s,
    border-color 0.15s;
}
.exams-filter-btn--on {
  background: rgba(59, 130, 246, 0.12);
  border-color: rgba(59, 130, 246, 0.25);
  color: #93c5fd;
}
.exams-filter-btn--off {
  background: rgba(255, 255, 255, 0.03);
  border-color: rgba(255, 255, 255, 0.06);
  color: #64748b;
}
.exams-filter-btn--off:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #cbd5e1;
}

/* Empty state da galeria */
.exams-empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 56px 24px;
  text-align: center;
}
.exams-empty-icon {
  width: 52px;
  height: 52px;
  border-radius: 14px;
  background: rgba(100, 116, 139, 0.1);
  border: 1px solid rgba(255, 255, 255, 0.05);
  color: #475569;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 16px;
}
.exams-empty-text {
  font-size: 14px;
  font-weight: 500;
  color: #64748b;
  margin: 0;
}
.exams-empty-hint {
  font-size: 12px;
  color: #475569;
  margin: 6px 0 0;
}

/* Card de galeria */
.exams-card {
  position: relative;
  border-radius: 10px;
  overflow: hidden;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  display: flex;
  flex-direction: column;
  cursor: grab;
  transition: border-color 0.15s;
}
.exams-card:hover {
  border-color: rgba(255, 255, 255, 0.12);
}
.exams-card--locked {
  border-color: rgba(251, 191, 36, 0.35);
  box-shadow: 0 0 0 1px rgba(251, 191, 36, 0.12);
}
.exams-lock-badge {
  position: absolute;
  top: 8px;
  left: 8px;
  z-index: 20;
  width: 22px;
  height: 22px;
  border-radius: 99px;
  background: rgba(245, 158, 11, 0.9);
  display: flex;
  align-items: center;
  justify-content: center;
}

/* Thumbnail */
.exams-thumb {
  aspect-ratio: 1 / 1;
  background: rgba(0, 0, 0, 0.3);
  width: 100%;
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
}
.exams-thumb-pdf {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  width: 100%;
  height: 100%;
  background: linear-gradient(
    160deg,
    rgba(127, 29, 29, 0.15) 0%,
    rgba(127, 29, 29, 0.05) 100%
  );
}
.exams-thumb-pdf-icon {
  width: 48px;
  height: 48px;
  border-radius: 10px;
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.15);
  display: flex;
  align-items: center;
  justify-content: center;
}
.exams-thumb-pdf-label {
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: rgba(252, 165, 165, 0.6);
}
.exams-thumb-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.45);
  opacity: 0;
  transition: opacity 0.15s;
  display: flex;
  align-items: center;
  justify-content: center;
}
.exams-card:hover .exams-thumb-overlay {
  opacity: 1;
}
.exams-thumb-eye {
  width: 34px;
  height: 34px;
  padding: 0;
  border-radius: 99px;
  background: rgba(15, 23, 42, 0.72);
  backdrop-filter: blur(6px);
  border: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  transition: background 0.2s;
}
.exams-card:hover .exams-thumb-eye {
  background: rgba(59, 130, 246, 0.85);
}

/* ── Barra de progresso de upload ── */
.exams-upload-progress {
  position: relative;
  width: 100%;
  height: 6px;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 999px;
  overflow: hidden;
}
.exams-upload-progress-bar {
  height: 100%;
  background: linear-gradient(90deg, #3b82f6, #60a5fa);
  border-radius: 999px;
  transition: width 0.15s ease-out;
}
.exams-upload-progress-label {
  position: absolute;
  top: 10px;
  left: 0;
  font-size: 11px;
  color: rgb(var(--slate-10));
}

/* Footer do card */
.exams-card-footer {
  padding: 10px 10px 8px;
  background: rgba(0, 0, 0, 0.15);
  border-top: 1px solid rgba(255, 255, 255, 0.04);
}
.exams-card-name-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 6px;
}
.exams-card-name {
  font-size: 11px;
  font-weight: 500;
  color: #e2e8f0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  line-height: 1.3;
}
.exams-card-date {
  font-size: 10px;
  color: #475569;
  flex-shrink: 0;
  margin-left: 6px;
}
.exams-card-actions {
  display: flex;
  align-items: center;
  gap: 2px;
}
.exams-card-category {
  font-size: 9px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #60a5fa;
  background: rgba(59, 130, 246, 0.08);
  padding: 2px 6px;
  border-radius: 4px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  margin-right: auto;
}
.exams-card-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  padding: 0;
  border-radius: 4px;
  border: none;
  background: transparent;
  color: #475569;
  cursor: pointer;
  transition:
    background 0.12s,
    color 0.12s;
  flex-shrink: 0;
  text-decoration: none;
}
.exams-card-btn:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #94a3b8;
}
.exams-card-btn--locked {
  color: #fbbf24;
}
.exams-card-btn--locked:hover {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
}
.exams-card-btn--danger:hover {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
}
</style>
