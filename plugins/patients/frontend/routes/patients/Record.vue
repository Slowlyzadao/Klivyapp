<script setup>
import './record.css';

import { ref, computed, onMounted, onUnmounted, onBeforeUnmount, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import AuditLogsAPI from '@plugins/patients/frontend/api/patients/auditLogs';
import AnamnesisAPI from '@plugins/patients/frontend/api/patients/anamnesis';
import ClinicalNotesAPI from '@plugins/patients/frontend/api/patients/clinicalNotes';
import ExamMediasAPI from '@plugins/patients/frontend/api/patients/examMedias';
import DocumentsAPI from '@plugins/patients/frontend/api/patients/documents';
import ConsentsAPI from '@plugins/patients/frontend/api/patients/consents';
import TreatmentPlansAPI from '@plugins/patients/frontend/api/patients/treatmentPlans';
import SessionLogsAPI from '@plugins/patients/frontend/api/patients/sessionLogs';
import FinancialEstimatesAPI from '@plugins/patients/frontend/api/patients/financialEstimates';
import TransactionsAPI from '@plugins/patients/frontend/api/patients/transactions';
import PatientAppointmentsAPI from '@plugins/patients/frontend/api/patients/appointments';
import PatientTimelineAPI from '@plugins/patients/frontend/api/patients/patientTimeline';
import ExamFoldersAPI from '@plugins/patients/frontend/api/patients/examFolders';
import AgendaServicesAPI from '@plugins/agenda/frontend/api/agendaServices';
import ContactAPI from 'dashboard/api/contacts';
import bankAccountsApi from '@plugins/financial/frontend/features/financial/api/bankAccounts';
import { useAlert } from 'dashboard/composables';
import { usePermissions } from 'dashboard/composables/usePermissions';
import EvolutionTab from './tabs/EvolutionTab.vue';

const router = useRouter();
const route = useRoute();
const store = useStore();

const { can } = usePermissions();

const currentUser = computed(() => store.getters.getCurrentUser);

const goBack = () => {
  router.back();
};

const isLoading = ref(true);
const changeHistory = ref([]);
const isHistoryLoading = ref(false);

const BRT = 'America/Sao_Paulo';

const formatTime = dateString => {
  if (!dateString) return '';
  return new Date(dateString).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: BRT,
  });
};

const formatCurrency = value => {
  if (!value) return 'R$ 0,00';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value);
};

// ── Audit Log state ─────────────────────────────────────────
const auditLogs = ref([]);
const expandedLogs = ref(new Set());

const toggleLogDetails = logId => {
  if (expandedLogs.value.has(logId)) {
    expandedLogs.value.delete(logId);
  } else {
    expandedLogs.value.add(logId);
  }
  // For reactivity trigger since Set doesn't trigger cleanly across component without new Set reference sometimes
  expandedLogs.value = new Set(expandedLogs.value);
};
const isAuditLoading = ref(false);
const isExportingPdf = ref(false);
const auditMeta = ref({ total_count: 0, current_page: 1, total_pages: 1 });
const auditFilters = ref({
  action_type: '',
  actor_id: '',
  start_date: '',
  end_date: '',
  page: 1,
});
const AUDIT_ACTION_OPTIONS = [
  { value: '', label: 'Todas as ações' },
  { value: 'view', label: 'Visualização' },
  { value: 'create', label: 'Criação' },
  { value: 'update', label: 'Edição' },
  { value: 'delete', label: 'Exclusão' },
  { value: 'sign', label: 'Assinatura' },
  { value: 'export', label: 'Exportação' },
  { value: 'finalize', label: 'Finalização' },
  { value: 'approve', label: 'Aprovação' },
  { value: 'pay', label: 'Pagamento' },
  { value: 'print', label: 'Impressão' },
];

// ── Anamnesis State ──────────────────────────────────────
const EMPTY_ANAMNESIS = () => ({
  id: null,
  specialty: 'Odontologia Geral',
  chief_complaint: '',
  medical_history: {
    hypertension: false,
    diabetes: false,
    bleeding_disorder: false,
    pregnant: false,
    oncology: false,
    hepatitis: false,
    other: '',
    has_recent_surgeries: false,
    has_implants: false,
    has_anesthesia_complications: false,
  },
  allergies: [],
  current_medications: [],
  contraindications: [],
  surgical_history: '',
  family_history: '',
  relevant_habits: {
    smoker: 'Não',
    alcohol: 'Não consome',
    sports: 'Sedentário',
  },
  pregnancy: {},
  additional_notes: '',
  status: 'draft',
});

// JSON round-trip: safe com Vue Proxies (structuredClone falha em Proxies reativos);
// os dados da anamnese são 100% JSON-seguros (sem Date/Map/Set).
const deepCloneAnamnesis = value => JSON.parse(JSON.stringify(value));

const normalizeAnamnesisFromServer = remote => {
  const base = EMPTY_ANAMNESIS();
  const clone = deepCloneAnamnesis(remote || {});
  return {
    ...base,
    ...clone,
    medical_history: {
      ...base.medical_history,
      ...(clone.medical_history ?? {}),
    },
    relevant_habits: {
      ...base.relevant_habits,
      ...(clone.relevant_habits ?? {}),
    },
    pregnancy: { ...base.pregnancy, ...(clone.pregnancy ?? {}) },
    allergies: Array.isArray(clone.allergies) ? clone.allergies : [],
    current_medications: Array.isArray(clone.current_medications)
      ? clone.current_medications
      : [],
    contraindications: Array.isArray(clone.contraindications)
      ? clone.contraindications
      : [],
  };
};

const anamneses = ref([]);
const currentAnamnesis = ref(EMPTY_ANAMNESIS());
const allergyInput = ref('');
const medicationInput = ref('');
const isSavingAnamnesis = ref(false);

const activeTab = ref('general');
const isSidebarOpen = ref(false);
const showCriticalAlert = ref(false);
const agendaServices = ref([]);
const avatarInputRef = ref(null);
const showCameraModal = ref(false);
const videoElement = ref(null);
const canvasElement = ref(null);
const capturedPhoto = ref(null);
const cameraStream = ref(null);
const cameraError = ref(false);

// ── Clinical Notes State ──────────────────────────────────
const clinicalNotes = ref([]);
const currentNote = ref({
  note_template: 'Evolução Padrão',
  complaint_of_day: '',
  assessment: '',
  conduct: '',
  complications: '',
  guidance_given: '',
  return_recommended: '',
});
const isSavingNote = ref(false);
const showConfirmDeleteNote = ref(false);
const noteToDelete = ref(null);
const isDeletingNote = ref(false);

// ── Exam Medias & Documents State ─────────────────────────
const examMedias = ref([]);
const isUploadingMedia = ref(false);
const lightboxMedia = ref(null);
const documents = ref([]);
const isGeneratingDoc = ref(false);
const mediaFileInput = ref(null);

// Document generation modal
const showDocModal = ref(false);
const docModalLoading = ref(false);
const docActionsOpenId = ref(null);
// Confirmação de exclusão
const showDeleteDocModal = ref(false);
const pendingDeleteDocId = ref(null);
const docForm = ref({
  document_type: 'atestado',
  title: '',
  cid: '',
  dias_afastamento: '',
  observacoes: '',
  medicamentos: '',
  posologia: '',
  exames_solicitados: '',
  encaminhado_para: '',
  especialidade: '',
  conteudo_livre: '',
});

const DOC_TYPE_LABELS = {
  receita: 'Receita Médica',
  atestado: 'Atestado Médico',
  pedido_exame: 'Pedido de Exame',
  declaracao: 'Declaração',
  relatorio_clinico: 'Relatório Clínico',
  encaminhamento: 'Encaminhamento',
  contrato: 'Contrato',
  orcamento: 'Orçamento',
  instrucao_procedimento: 'Instruções de Procedimento',
  questionario: 'Questionário',
  outro: 'Outro',
};

const DOC_STATUS_CONFIG = {
  gerado: {
    label: 'Gerado',
    cls: 'bg-blue-500/15 text-blue-400 border-blue-500/25',
  },
  pendente_assinatura: {
    label: 'Aguard. Assinatura',
    cls: 'bg-amber-500/15 text-amber-400 border-amber-500/25',
  },
  assinado: {
    label: 'Assinado',
    cls: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/25',
  },
  enviado: {
    label: 'Enviado',
    cls: 'bg-purple-500/15 text-purple-400 border-purple-500/25',
  },
  arquivado: {
    label: 'Arquivado',
    cls: 'bg-slate-500/15 text-slate-400 border-slate-500/25',
  },
};

const openDocModal = () => {
  docForm.value = {
    document_type: 'atestado',
    title: '',
    cid: '',
    dias_afastamento: '',
    observacoes: '',
    medicamentos: '',
    posologia: '',
    exames_solicitados: '',
    encaminhado_para: '',
    especialidade: '',
    conteudo_livre: '',
  };
  showDocModal.value = true;
};

// ── Folder Management State ────────────────────────────────
const examFolders = ref([{ id: 'root', name: 'root', isRoot: true }]);
const activeFolderId = ref('root');
const activeMediaTypeFilter = ref('all');
const draggedMediaId = ref(null);
const isDraggingOverFolder = ref(null);

// Folder creation modal
const showCreateFolderModal = ref(false);
const newFolderName = ref('');
const isCreatingFolder = ref(false);

// Rename folder modal (separate from inline — now includes color picker)
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

// Delete folder
const showDeleteFolderModal = ref(false);
const folderToDelete = ref(null);
const deleteBlockedMessage = ref('');

// Lock/Unlock state per media (stored locally via reactive map)
const mediaLockMap = ref({});
const showLockModal = ref(false);
const lockTargetMediaId = ref(null);
const lockActionType = ref('lock'); // 'lock' or 'unlock'
const lockPinInput = ref('');
const lockPinError = ref('');
const LOCK_PIN = '123';

// Rename media
const renamingMediaId = ref(null);
const renamingMediaName = ref('');

// Delete media confirmation
const showDeleteMediaModal = ref(false);
const mediaToDelete = ref(null);
const isDeletingMedia = ref(false);

const expandedFolderIds = ref(new Set());
const mediaFolderMap = ref({}); // { [mediaId]: folderId } persisted to API

let saveFolderDebounceTimer = null;
let lastFolderPayloadJson = '';

const loadFolderData = async patientId => {
  try {
    const { data } = await ExamFoldersAPI.getAll(patientId);
    if (data && data.folders) {
      examFolders.value = data.folders;
      mediaLockMap.value = data.lock_map || {};
      expandedFolderIds.value = new Set(data.expanded_ids || []);
      mediaFolderMap.value = data.media_folder_map || {};
    }
  } catch (e) {
    // keep defaults on error
  }
};

const buildFolderPayload = () => ({
  folders: examFolders.value,
  lock_map: mediaLockMap.value,
  expanded_ids: [...expandedFolderIds.value],
  media_folder_map: mediaFolderMap.value,
});

// Flush imediato — sem debounce. Chamado em beforeunload, onBeforeUnmount
// e ao trocar de aba. Usa sendBeacon como fallback síncrono confiável no unload.
const flushFolderData = (patientId, { useBeacon = false } = {}) => {
  clearTimeout(saveFolderDebounceTimer);
  const payload = buildFolderPayload();
  const body = JSON.stringify(payload);
  if (body === lastFolderPayloadJson) return;
  lastFolderPayloadJson = body;

  if (useBeacon && navigator.sendBeacon) {
    const url = `/api/v1/accounts/${route.params.accountId}/patients/${patientId}/exam_folders/bulk`;
    const blob = new Blob([body], { type: 'application/json' });
    navigator.sendBeacon(url, blob);
    return;
  }
  // melhor esforço — erros silenciados propositalmente
  ExamFoldersAPI.update(patientId, 'bulk', payload).catch(() => {});
};

const saveFolderData = patientId => {
  clearTimeout(saveFolderDebounceTimer);
  saveFolderDebounceTimer = setTimeout(() => {
    flushFolderData(patientId);
  }, 500);
};

const handleFolderBeforeUnload = () => {
  const pid = route.params.patientId;
  if (!pid) return;
  flushFolderData(pid, { useBeacon: true });
};

// Apply stored folder assignments to freshly fetched medias
const applyMediaFolderMap = () => {
  const map = mediaFolderMap.value;
  examMedias.value.forEach(m => {
    if (map[m.id]) m.folder_id = map[m.id];
  });
};

// Count all items inside a folder recursively (subfolders + their files)
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

const activeFolder = computed(
  () =>
    examFolders.value.find(f => f.id === activeFolderId.value) ||
    examFolders.value[0]
);

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
            [
              'doc',
              'docx',
              'xls',
              'xlsx',
              'csv',
              'ppt',
              'pptx',
              'rtf',
              'txt',
            ].includes(ext)
          );
        default:
          return true;
      }
    });
  }

  return list;
});

const nonRootFolders = computed(() => examFolders.value.filter(f => !f.isRoot));

// Top-level = no parentId, sorted by order
const topLevelFolders = computed(() =>
  examFolders.value
    .filter(f => !f.isRoot && !f.parentId)
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
);

const getSubfolders = parentId =>
  examFolders.value
    .filter(f => f.parentId === parentId)
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0));

const getFolderPath = folderId => {
  const path = [];
  let current = examFolders.value.find(f => f.id === folderId);
  while (current && !current.isRoot) {
    path.unshift(current);
    current = current.parentId
      ? examFolders.value.find(f => f.id === current.parentId)
      : null;
  }
  return path;
};

const toggleFolderExpand = folderId => {
  const next = new Set(expandedFolderIds.value);
  if (next.has(folderId)) {
    next.delete(folderId);
  } else {
    next.add(folderId);
  }
  expandedFolderIds.value = next;
  saveFolderData(route.params.patientId);
};

// ── Folder sidebar drag (reorder + nest) ─────────────────────────────
const draggedFolderId = ref(null);
const dragOverFolderTarget = ref(null); // { id, position: 'before'|'after'|'inside' }
const dragPromoteActive = ref(false);

const isAncestorOf = (potentialAncestorId, folderId) => {
  let current = examFolders.value.find(f => f.id === folderId);
  while (current?.parentId) {
    if (current.parentId === potentialAncestorId) return true;
    current = examFolders.value.find(f => f.id === current.parentId);
  }
  return false;
};

// Click fold: navigate + toggle expand when has subfolders
const clickFolderRow = folder => {
  activeFolderId.value = folder.id;
  if (getSubfolders(folder.id).length > 0) toggleFolderExpand(folder.id);
};

const onFolderSidebarDragStart = (e, folder) => {
  draggedFolderId.value = folder.id;
  e.dataTransfer.effectAllowed = 'move';
};

const promoteFolderToRoot = () => {
  if (!draggedFolderId.value) return;
  const folder = examFolders.value.find(f => f.id === draggedFolderId.value);
  if (!folder) return;
  folder.parentId = null;
  const maxOrder = topLevelFolders.value
    .filter(f => f.id !== folder.id)
    .reduce((m, f) => Math.max(m, f.order ?? 0), -1);
  folder.order = maxOrder + 1;
  saveFolderData(route.params.patientId);
  draggedFolderId.value = null;
  dragOverFolderTarget.value = null;
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

const onFolderSidebarDrop = (e, targetFolder) => {
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

  if (pos === 'inside') {
    // Bloquear aninhamento duplo (m\u00e1x. 1 n\u00edvel)
    if (targetFolder.parentId) {
      useAlert(
        'N\u00e3o \u00e9 poss\u00edvel criar subpastas dentro de subpastas. M\u00e1ximo de 1 n\u00edvel de aninhamento permitido.'
      );
    } else if (isAncestorOf(draggedFolderId.value, targetFolder.id)) {
      useAlert('N\u00e3o \u00e9 poss\u00edvel criar uma hierarquia circular.');
    } else {
      dragged.parentId = targetFolder.id;
      const next = new Set(expandedFolderIds.value);
      next.add(targetFolder.id);
      expandedFolderIds.value = next;
      useAlert(
        `"${dragged.name}" movida para dentro de "${targetFolder.name}"`
      );
    }
  } else {
    // Reorder within same parent level
    dragged.parentId = targetFolder.parentId || null;
    const siblings = examFolders.value
      .filter(
        f =>
          !f.isRoot && (f.parentId || null) === (targetFolder.parentId || null)
      )
      .sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
    const withoutDragged = siblings.filter(f => f.id !== dragged.id);
    const targetIdx = withoutDragged.findIndex(f => f.id === targetFolder.id);
    const insertAt = pos === 'before' ? targetIdx : targetIdx + 1;
    withoutDragged.splice(insertAt, 0, dragged);
    withoutDragged.forEach((f, i) => {
      f.order = i;
    });
  }

  saveFolderData(route.params.patientId);
  draggedFolderId.value = null;
  dragOverFolderTarget.value = null;
};

const createFolder = () => {
  const name = newFolderName.value.trim();
  if (!name) return;
  const maxOrder = topLevelFolders.value.reduce(
    (m, f) => Math.max(m, f.order ?? 0),
    -1
  );
  const folder = {
    id: `folder_${Date.now()}`,
    name,
    color: '#60a5fa',
    isRoot: false,
    parentId: null,
    order: maxOrder + 1,
  };
  examFolders.value.push(folder);
  saveFolderData(route.params.patientId);
  newFolderName.value = '';
  showCreateFolderModal.value = false;
};

const startRenameFolder = folder => {
  renamingFolderId.value = folder.id;
  renamingFolderName.value = folder.name;
  renamingFolderColor.value = folder.color || '#60a5fa';
  showRenameFolderModal.value = true;
};

const confirmRenameFolder = () => {
  const name = renamingFolderName.value.trim();
  if (!name) return;
  const folder = examFolders.value.find(f => f.id === renamingFolderId.value);
  if (folder) {
    folder.name = name;
    folder.color = renamingFolderColor.value;
  }
  saveFolderData(route.params.patientId);
  showRenameFolderModal.value = false;
  renamingFolderId.value = null;
  renamingFolderName.value = '';
};

const requestDeleteFolder = folder => {
  // Check if any media inside is locked
  const mediasInside = examMedias.value.filter(m => m.folder_id === folder.id);
  const hasLockedMedia = mediasInside.some(m => mediaLockMap.value[m.id]);
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

const confirmDeleteFolder = () => {
  if (!folderToDelete.value || deleteBlockedMessage.value) {
    showDeleteFolderModal.value = false;
    folderToDelete.value = null;
    deleteBlockedMessage.value = '';
    return;
  }
  // Move all media from this folder back to root
  examMedias.value.forEach(m => {
    if (m.folder_id === folderToDelete.value.id) {
      m.folder_id = 'root';
    }
  });
  examFolders.value = examFolders.value.filter(
    f => f.id !== folderToDelete.value.id
  );
  if (activeFolderId.value === folderToDelete.value.id) {
    activeFolderId.value = 'root';
  }
  saveFolderData(route.params.patientId);
  showDeleteFolderModal.value = false;
  folderToDelete.value = null;
  deleteBlockedMessage.value = '';
};

// Drag & Drop
const onMediaDragStart = (e, mediaId) => {
  draggedMediaId.value = mediaId;
  e.dataTransfer.effectAllowed = 'move';
};

const onFolderDragOver = (e, folderId) => {
  e.preventDefault();
  e.dataTransfer.dropEffect = 'move';
  isDraggingOverFolder.value = folderId;
};

const onFolderDragLeave = () => {
  isDraggingOverFolder.value = null;
};

const onFolderDrop = (e, folderId) => {
  e.preventDefault();
  isDraggingOverFolder.value = null;
  if (!draggedMediaId.value) return;
  const media = examMedias.value.find(m => m.id === draggedMediaId.value);
  if (media) {
    media.folder_id = folderId;
    // Persist the media→folder assignment
    const newMap = { ...mediaFolderMap.value, [media.id]: folderId };
    mediaFolderMap.value = newMap;
    saveFolderData(route.params.patientId);
    useAlert('Arquivo movido para a pasta com sucesso!');
  }
  draggedMediaId.value = null;
};

// Lock
const openLockModal = (mediaId, action) => {
  lockTargetMediaId.value = mediaId;
  lockActionType.value = action;
  lockPinInput.value = '';
  lockPinError.value = '';
  showLockModal.value = true;
};

const confirmLockAction = () => {
  if (lockPinInput.value !== LOCK_PIN) {
    lockPinError.value = 'Código incorreto. Tente novamente.';
    return;
  }
  if (lockActionType.value === 'lock') {
    mediaLockMap.value = {
      ...mediaLockMap.value,
      [lockTargetMediaId.value]: true,
    };
    useAlert('Arquivo bloqueado com sucesso!');
  } else {
    const updated = { ...mediaLockMap.value };
    delete updated[lockTargetMediaId.value];
    mediaLockMap.value = updated;
    useAlert('Arquivo desbloqueado com sucesso!');
  }
  saveFolderData(route.params.patientId);
  showLockModal.value = false;
  lockTargetMediaId.value = null;
  lockPinInput.value = '';
  lockPinError.value = '';
};

// Rename media
const startRenameMedia = media => {
  renamingMediaId.value = media.id;
  renamingMediaName.value = media.file_name || '';
};

const confirmRenameMedia = () => {
  const name = renamingMediaName.value.trim();
  if (!name) return;
  const media = examMedias.value.find(m => m.id === renamingMediaId.value);
  if (media) media.file_name = name;
  saveFolderData(route.params.patientId);
  renamingMediaId.value = null;
  renamingMediaName.value = '';
};

// Delete media
const requestDeleteMedia = media => {
  if (mediaLockMap.value[media.id]) {
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
    useAlert('Erro ao excluir arquivo.');
  } finally {
    isDeletingMedia.value = false;
    showDeleteMediaModal.value = false;
    mediaToDelete.value = null;
  }
};

const patient = ref({
  id: null,
  name: '',
  avatar_url: '',
  phone: '',
  email: '',
  cpf: '',
  rg: '',
  birthdate: '',
  age: null,
  sex: '',
  contact_id: null,
  patient_status: 'novo',
  financialStatus: 'Adimplente',
  activeTreatment: '---',
  origin: '',
  unit: '',
  critical_alerts: [],
  clinicalTags: [],
  address: {
    street: '',
    number: '',
    complement: '',
    neighborhood: '',
    city: '',
    state: '',
    zip_code: '',
  },
  emergency_contact: {
    name: '',
    phone: '',
    relationship: '',
  },
  insurance: {
    name: '',
    number: '',
    plan: '',
    valid_until: '',
  },
  communication_opt_ins: {
    whatsapp: false,
    email: false,
  },
  lgpd_consent: {
    accepted: false,
    image_use_accepted: false,
  },
});

const fetchPatientSummary = async () => {
  try {
    isLoading.value = true;
    const response = await PatientsAPI.summary(route.params.patientId);

    // Merge nested objects safely
    const data = response.data?.payload || {};
    patient.value = {
      ...patient.value,
      ...data,
      address: { ...patient.value.address, ...(data.address || {}) },
      emergency_contact: {
        ...patient.value.emergency_contact,
        ...(data.emergency_contact || {}),
      },
      insurance: { ...patient.value.insurance, ...(data.insurance || {}) },
      communication_opt_ins: {
        ...patient.value.communication_opt_ins,
        ...(data.communication_opt_ins || {}),
      },
      lgpd_consent: {
        ...patient.value.lgpd_consent,
        ...(data.lgpd_consent || {}),
      },
    };

    // Split full name into first / last for the form
    const parts = (data.name || '').trim().split(' ');
    editFirstName.value = parts[0] || '';
    editLastName.value = parts.slice(1).join(' ') || '';

    // Restore recall dismiss state from server
    if (data.recall_dismissed_at) {
      recallDismissedForever.value = true;
    }
  } catch (error) {
    // ignorar erro
  } finally {
    isLoading.value = false;
  }
};

const fetchChangeHistory = async () => {
  try {
    isHistoryLoading.value = true;
    const response = await PatientsAPI.changeHistory(route.params.patientId);
    changeHistory.value = response.data?.payload || [];
  } catch (error) {
    // ignorar erro
  } finally {
    isHistoryLoading.value = false;
  }
};

// ── Anamnesis Actions ───────────────────────────────────
// Aplica o state de forma cirúrgica: muta propriedades in-place em vez de
// substituir o Ref inteiro. Isso preserva a reatividade dos v-models aninhados
// (ex: currentAnamnesis.medical_history.hypertension) após fetchAnamneses.
const applyAnamnesisState = source => {
  const target = currentAnamnesis.value;
  const normalized = source ? normalizeAnamnesisFromServer(source) : EMPTY_ANAMNESIS();

  // campos escalares no root
  [
    'id',
    'specialty',
    'chief_complaint',
    'surgical_history',
    'family_history',
    'additional_notes',
    'status',
    'version_number',
    'finalized_at',
    'pdf_url',
    'updated_at',
  ].forEach(key => {
    target[key] = normalized[key] ?? (key === 'id' ? null : '');
  });

  // hashes aninhados — mutar in-place
  Object.keys(target.medical_history).forEach(key => {
    target.medical_history[key] = normalized.medical_history[key] ?? false;
  });
  Object.keys(normalized.medical_history).forEach(key => {
    target.medical_history[key] = normalized.medical_history[key];
  });

  Object.keys(target.relevant_habits).forEach(key => {
    target.relevant_habits[key] = normalized.relevant_habits[key] ?? target.relevant_habits[key];
  });

  target.pregnancy = { ...normalized.pregnancy };

  // arrays — substituir referência (Vue reage bem a substituição de array)
  target.allergies = Array.isArray(normalized.allergies) ? [...normalized.allergies] : [];
  target.current_medications = Array.isArray(normalized.current_medications)
    ? [...normalized.current_medications]
    : [];
  target.contraindications = Array.isArray(normalized.contraindications)
    ? [...normalized.contraindications]
    : [];
};

const startNewAnamnesis = () => {
  applyAnamnesisState(null);
};

const flushAllergyInput = () => {
  const value = allergyInput.value?.trim();
  if (!value) return;
  currentAnamnesis.value.allergies = [
    ...(currentAnamnesis.value.allergies || []),
    { name: value },
  ];
  allergyInput.value = '';
};

const flushMedicationInput = () => {
  const value = medicationInput.value?.trim();
  if (!value) return;
  currentAnamnesis.value.current_medications = [
    ...(currentAnamnesis.value.current_medications || []),
    { name: value },
  ];
  medicationInput.value = '';
};

const removeAllergy = idx => {
  if (currentAnamnesis.value.status === 'finalized') return;
  currentAnamnesis.value.allergies = (currentAnamnesis.value.allergies || []).filter(
    (_, i) => i !== idx
  );
};

const removeMedication = idx => {
  if (currentAnamnesis.value.status === 'finalized') return;
  currentAnamnesis.value.current_medications = (
    currentAnamnesis.value.current_medications || []
  ).filter((_, i) => i !== idx);
};

const fetchAnamneses = async () => {
  try {
    const response = await AnamnesisAPI.get(route.params.patientId);
    anamneses.value = response.data?.payload || response.data || [];
    applyAnamnesisState(anamneses.value[0] || null);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error fetching anamneses', error);
    useAlert('Não foi possível carregar a anamnese.');
  }
};

const UNPERMITTED_ANAMNESIS_KEYS = [
  'id',
  'status',
  'version_number',
  'account_id',
  'patient_id',
  'professional_id',
  'finalized_at',
  'created_at',
  'updated_at',
  'pdf_url',
];

const saveAnamnesis = async (finalize = false) => {
  if (isSavingAnamnesis.value) return;
  try {
    isSavingAnamnesis.value = true;

    // flush inputs soltos antes de montar o payload
    flushAllergyInput();
    flushMedicationInput();

    const payload = deepCloneAnamnesis(currentAnamnesis.value);
    UNPERMITTED_ANAMNESIS_KEYS.forEach(key => delete payload[key]);

    let response;
    if (currentAnamnesis.value.id) {
      response = await AnamnesisAPI.update(
        route.params.patientId,
        currentAnamnesis.value.id,
        payload
      );
    } else {
      response = await AnamnesisAPI.create(route.params.patientId, payload);
    }

    const persisted = response.data?.payload || response.data;
    const savedId = persisted?.id || currentAnamnesis.value.id;

    if (finalize && savedId) {
      // ao finalizar, delegamos o sync do state apenas ao fetchAnamneses final
      // (evita duplo-sync reativo entre save → finalize).
      await AnamnesisAPI.finalize(route.params.patientId, savedId);
      await fetchAnamneses();
      useAlert('Anamnese assinada e finalizada com sucesso!');
    } else {
      if (persisted) {
        applyAnamnesisState(persisted);
      }
      useAlert('Anamnese salva como rascunho com sucesso!');
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error saving anamnesis', error);
    useAlert(error?.response?.data?.error || 'Erro ao salvar anamnese.');
  } finally {
    isSavingAnamnesis.value = false;
  }
};

// ── Clinical Notes Actions ────────────────────────────────
const fetchClinicalNotes = async () => {
  try {
    const response = await ClinicalNotesAPI.get(route.params.patientId);
    clinicalNotes.value = response.data?.payload || response.data || [];
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error fetching clinical notes', error);
  }
};

const requestDeleteNote = noteId => {
  noteToDelete.value = noteId;
  showConfirmDeleteNote.value = true;
};

const cancelDeleteNote = () => {
  showConfirmDeleteNote.value = false;
  noteToDelete.value = null;
  isDeletingNote.value = false;
};

const confirmDeleteNote = async () => {
  if (!noteToDelete.value) return;
  isDeletingNote.value = true;
  try {
    await ClinicalNotesAPI.delete(route.params.patientId, noteToDelete.value);
    useAlert('Rascunho excluído com sucesso!');
    await fetchClinicalNotes();
    if (currentNote.value.id === noteToDelete.value) {
      currentNote.value = {
        note_template: 'Evolução Padrão',
        complaint_of_day: '',
        assessment: '',
        conduct: '',
        complications: '',
        guidance_given: '',
        return_recommended: '',
      };
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error deleting clinical note', error);
    useAlert('Erro ao excluir o rascunho.');
  } finally {
    cancelDeleteNote();
  }
};

const saveClinicalNote = async (sign = false) => {
  try {
    isSavingNote.value = true;
    const payload = { ...currentNote.value };

    // Converter número de dias para data ISO (coluna type:date no banco)
    if (
      payload.return_recommended !== '' &&
      payload.return_recommended !== null
    ) {
      const days = parseInt(payload.return_recommended, 10);
      if (!Number.isNaN(days) && days >= 0) {
        const date = new Date();
        date.setDate(date.getDate() + days);
        payload.return_recommended = date.toISOString().split('T')[0]; // YYYY-MM-DD
      } else {
        payload.return_recommended = null;
      }
    } else {
      payload.return_recommended = null;
    }

    let response;
    if (payload.id) {
      response = await ClinicalNotesAPI.update(
        route.params.patientId,
        payload.id,
        payload
      );
    } else {
      response = await ClinicalNotesAPI.create(route.params.patientId, payload);
      currentNote.value.id = response.data?.payload?.id || response.data.id;
    }

    if (sign && currentNote.value.id) {
      await ClinicalNotesAPI.sign(route.params.patientId, currentNote.value.id);
      useAlert('Evolução assinada com sucesso!');
      currentNote.value = {
        note_template: 'Evolução Padrão',
        complaint_of_day: '',
        assessment: '',
        conduct: '',
        complications: '',
        guidance_given: '',
        return_recommended: '',
      };
      await fetchClinicalNotes();
    } else {
      useAlert('Evolução salva como rascunho com sucesso!');
      await fetchClinicalNotes();
    }
  } catch (error) {
    useAlert('Erro ao salvar evolução.');
  } finally {
    isSavingNote.value = false;
  }
};

const editClinicalNote = note => {
  const loaded = { ...note };

  // Converter data de retorno de volta para número de dias
  if (loaded.return_recommended) {
    const returnDate = new Date(loaded.return_recommended);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const diffMs = returnDate.getTime() - today.getTime();
    const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));
    loaded.return_recommended = diffDays > 0 ? String(diffDays) : '';
  }

  currentNote.value = loaded;
  nextTick(() => {
    const formEl = document.querySelector('.evolution-form');
    if (formEl) {
      formEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }

    // Fallback: se houver container de rolagem específico, move até o topo dele
    const container = document.querySelector('.record-container');
    if (container) {
      container.scrollTo({ top: 0, behavior: 'smooth' });
    } else {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  });
};

// ── Exam Medias & Documents Actions ─────────────────────────
const fetchExamMedias = async () => {
  try {
    const res = await ExamMediasAPI.get(route.params.patientId);
    // jbuilder wraps array inside { data: [...], meta: {...} }
    examMedias.value = res.data?.data || res.data || [];
    // Restore persisted folder assignments
    applyMediaFolderMap();
  } catch (error) {
    // ignore
  }
};

const triggerMediaUpload = () => {
  if (mediaFileInput.value) mediaFileInput.value.click();
};

const openMediaLightbox = media => {
  lightboxMedia.value = media;
};

const handleLightboxKey = e => {
  if (e.key === 'Escape') lightboxMedia.value = null;
};

onMounted(() => {
  window.addEventListener('keydown', handleLightboxKey);
});

onUnmounted(() => {
  window.removeEventListener('keydown', handleLightboxKey);
});

const MAX_UPLOAD_BYTES = 500 * 1024 * 1024; // 500MB — alinha com backend (exam_media.rb)

const detectMediaCategory = file => {
  const type = file.type || '';
  if (type.startsWith('image/')) return 'foto_clinica';
  if (type.startsWith('video/')) return 'video';
  if (type === 'application/pdf') return 'laudo';
  return 'outro';
};

const uploadProgress = ref(0);

const onMediaFileSelected = async event => {
  const file = event.target.files[0];
  if (!file) return;

  if (file.size > MAX_UPLOAD_BYTES) {
    useAlert('Arquivo muito grande. Tamanho máximo: 500MB.');
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
    const msg = error?.response?.data?.errors?.[0] || 'Erro no upload de mídia.';
    useAlert(msg);
  } finally {
    isUploadingMedia.value = false;
    uploadProgress.value = 0;
    event.target.value = null;
  }
};

const fetchDocuments = async () => {
  try {
    const res = await DocumentsAPI.get(route.params.patientId);
    // API responds with { data: [...], meta: { total_count, ... } }
    documents.value = res.data?.data || res.data || [];
  } catch (error) {
    // ignore
  }
};

const generateDocument = async () => {
  docModalLoading.value = true;
  try {
    const form = docForm.value;

    // Build variables object based on document type
    const variables = {};
    if (form.document_type === 'atestado') {
      if (form.cid) variables.cid = form.cid;
      if (form.dias_afastamento)
        variables.dias_afastamento = form.dias_afastamento;
    } else if (form.document_type === 'receita') {
      if (form.medicamentos) variables.medicamentos = form.medicamentos;
      if (form.posologia) variables.posologia = form.posologia;
    } else if (form.document_type === 'pedido_exame') {
      if (form.exames_solicitados)
        variables.exames_solicitados = form.exames_solicitados;
    } else if (form.document_type === 'encaminhamento') {
      if (form.encaminhado_para)
        variables.encaminhado_para = form.encaminhado_para;
      if (form.especialidade) variables.especialidade = form.especialidade;
    } else if (form.conteudo_livre) variables.conteudo = form.conteudo_livre;
    if (form.observacoes) variables.observacoes = form.observacoes;

    const payload = {
      document_type: form.document_type,
      title:
        form.title || DOC_TYPE_LABELS[form.document_type] || form.document_type,
      variables,
    };

    const res = await DocumentsAPI.generate(route.params.patientId, payload);
    const docData = res.data;

    showDocModal.value = false;
    await fetchDocuments();

    // Open the generated PDF in a new tab if a signed URL is available
    if (docData?.url) {
      window.open(docData.url, '_blank');
    }
  } catch (error) {
    useAlert('Erro ao gerar documento. Verifique os dados e tente novamente.');
  } finally {
    docModalLoading.value = false;
  }
};

const downloadDocument = async doc => {
  if (!doc?.id) return;
  try {
    const res = await DocumentsAPI.download(route.params.patientId, doc.id);
    if (res.data?.url) {
      window.open(res.data.url, '_blank');
    }
  } catch {
    useAlert('Erro ao baixar o documento.');
  }
};

const sendWhatsAppDocument = async documentId => {
  if (!documentId) return;
  try {
    await DocumentsAPI.sendWhatsApp(route.params.patientId, documentId);
    useAlert('Documento enviado via WhatsApp com sucesso!');
  } catch {
    useAlert('Erro ao enviar documento via WhatsApp.');
  }
};

const deleteDocument = documentId => {
  if (!documentId) return;
  pendingDeleteDocId.value = documentId;
  showDeleteDocModal.value = true;
};

const confirmDeleteDocument = async () => {
  const id = pendingDeleteDocId.value;
  if (!id) return;
  try {
    await DocumentsAPI.delete(route.params.patientId, id);
    documents.value = documents.value.filter(d => d.id !== id);
  } catch {
    useAlert('Erro ao excluir o documento.');
  } finally {
    showDeleteDocModal.value = false;
    pendingDeleteDocId.value = null;
  }
};

// ── Consentimentos ─────────────────────────────────────────────────────
const consents = ref([]);
const consentLoading = ref(false);
const showConsentModal = ref(false);
const showSignModal = ref(false);
const showViewModal = ref(false);
const consentInView = ref(null);
const signingConsentId = ref(null);
const consentModalLoading = ref(false);
const signatureCanvas = ref(null);
const isDrawing = ref(false);
const hasSignature = ref(false);

const CONSENT_TYPES = [
  {
    value: 'lgpd',
    label: 'Termo LGPD / Privacidade de Dados',
    icon: 'i-lucide-shield-check',
    color: 'blue',
    description:
      'Autorização para coleta, uso e armazenamento de dados pessoais conforme LGPD (Lei 13.709/2018).',
    template:
      'TERMO DE CONSENTIMENTO PARA USO DE DADOS PESSOAIS (LGPD)\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], declaro que fui devidamente informado(a) sobre:\n\n1. DADOS COLETADOS: nome, data de nascimento, CPF, endereço, contatos, histórico de saúde, fotos e registros de atendimento.\n2. FINALIDADE: gestão do prontuário, agendamento, comunicação sobre tratamentos e emissão de documentos.\n3. ARMAZENAMENTO: servidores com criptografia e acesso restrito.\n4. COMPARTILHAMENTO: não ocorre sem autorização prévia, salvo exigência legal.\n5. DIREITOS: acesso, correção, exclusão ou revogação a qualquer momento.\n\nConsinto expressamente com o tratamento dos meus dados pessoais.',
  },
  {
    value: 'autorizacao_imagem',
    label: 'Autorização de Uso de Imagem',
    icon: 'i-lucide-camera',
    color: 'purple',
    description:
      'Autorização para captura e uso de fotos e vídeos para documentação clínica.',
    template:
      'AUTORIZAÇÃO DE USO DE IMAGEM\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], AUTORIZO a clínica a fotografar e/ou filmar minha imagem durante e após procedimentos estéticos para fins de documentação clínica e acompanhamento de resultados.\n\nDeclaro ciência de que as imagens são armazenadas com segurança e acesso restrito ao corpo clínico.',
  },
  {
    value: 'botox',
    label: 'Consentimento - Toxina Botulínica (Botox)',
    icon: 'i-lucide-syringe',
    color: 'emerald',
    description:
      'Termo de consentimento informado para aplicação de toxina botulínica.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - TOXINA BOTULÍNICA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], declaro ter sido informado(a) sobre:\n\n1. Aplicação de toxina botulínica tipo A em músculos-alvo para relaxamento temporário.\n2. Efeito esperado: início em 3-7 dias; duração de 3-6 meses.\n3. Riscos: hematoma, ptose palpebral, assimetria, cefaleia, reação alérgica (rara).\n4. Contraindicações: gestantes, lactantes, miastenia gravis.\n5. Sem garantia de resultado (obrigação de meios).\n\nDeclaro compreensão plena e consinto com o procedimento.',
  },
  {
    value: 'preenchimento',
    label: 'Consentimento - Preenchimento Dérmico (Filler)',
    icon: 'i-lucide-droplet',
    color: 'cyan',
    description:
      'Termo de consentimento para aplicação de preenchedores dérmicos.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - PREENCHIMENTO DÉRMICO\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de PREENCHIMENTO DÉRMICO com ácido hialurônico.\n\n1. Riscos: edema, equimose, assimetria, nódulos, migração, oclusão vascular (rara mas grave), cegueira (extremamente raro).\n2. Duração: 6 meses a 2 anos conforme produto e área.\n3. Contraindicações: gestação, lactação, doenças autoimunes ativas.\n4. Sem garantia de resultado.\n\nDeclaro ter entendido os riscos e alternativas ao tratamento.',
  },
  {
    value: 'fototerapia',
    label: 'Consentimento - Laser / Fototerapia / LED',
    icon: 'i-lucide-zap',
    color: 'amber',
    description:
      'Termo para procedimentos com laser, luz pulsada, LED ou radiofrequência.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - LASER / FOTOTERAPIA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de LASER / LUZ PULSADA / LED / RADIOFREQUÊNCIA.\n\n1. Riscos: eritema, edema, hiperpigmentação pós-inflamatória, hipopigmentação, queimaduras (raros).\n2. Cuidados: protetor solar FPS 60+ por 30 dias; evitar sol direto.\n3. Contraindicações: bronzeamento recente, gestação, fotossensibilizantes.\n\nDeclaro ciência dos riscos e autorizo o procedimento.',
  },
  {
    value: 'peeling',
    label: 'Consentimento - Peeling Químico / Dermabrasão',
    icon: 'i-lucide-layers',
    color: 'rose',
    description: 'Termo para peelings químicos de diferentes profundidades.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO - PEELING QUÍMICO\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com a realização de PEELING QUÍMICO.\n\n1. Riscos: eritema prolongado, descamação, hiperpigmentação, herpes recorrente, cicatrizes (raros).\n2. Cuidados: fotoproteção rigorosa por 60 dias; evitar maquiagem por 7 dias.\n3. Contraindicações: gestação, lactação, herpes ativo, isotretinoína nos últimos 6 meses.\n\nDeclaro compreensão e concordo com o procedimento.',
  },
  {
    value: 'menor_idade',
    label: 'Autorização - Paciente Menor de Idade',
    icon: 'i-lucide-baby',
    color: 'orange',
    description:
      'Autorização do responsável legal para tratamento de menor de 18 anos.',
    template:
      'AUTORIZAÇÃO PARA TRATAMENTO DE MENOR DE IDADE\n\nEu, [NOME DO RESPONSÁVEL], portador(a) do CPF [CPF], responsável legal de [NOME DO PACIENTE], AUTORIZO os procedimentos indicados.\n\n1. Tenho ciência plena dos procedimentos e seus riscos.\n2. Fui informado(a) sobre benefícios e alternativas.\n3. Autorizo uso de imagens apenas para documentação clínica.\n\nEm conformidade com ECA (Lei 8.069/90) e normativas do CFM/CFF.',
  },
  {
    value: 'procedimento_cirurgico',
    label: 'Consentimento - Procedimento Cirúrgico Minor',
    icon: 'i-lucide-activity',
    color: 'red',
    description:
      'Termo para pequenas cirurgias ambulatoriais (biópsia, exérese, etc.).',
    template:
      'TERMO DE CONSENTIMENTO - PROCEDIMENTO CIRÚRGICO MENOR\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], consinto com o procedimento cirúrgiico indicado.\n\n1. Fui informado sobre o tipo de procedimento, anestesia local e riscos de sangramento, infecção e cicatriz.\n2. Compreendo os cuidados pós-operatórios necessários.\n3. Aceito os riscos inerentes ao procedimento proposto.',
  },
  {
    value: 'anestesia',
    label: 'Consentimento - Anestesia Local/Tópica',
    icon: 'i-lucide-pill',
    color: 'violet',
    description:
      'Consentimento específico para uso de anestesia local ou tópica.',
    template:
      'TERMO DE CONSENTIMENTO - ANESTESIA LOCAL/TÓPICA\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], fui informado(a) sobre o uso de anestesia local ou tópica.\n\n1. Reações possíveis: ardência, eritema, edema, tonturas, reações alérgicas (raras).\n2. Alergias conhecidas: [ ] NÃO POSSUO / [ ] POSSUO: ___________\n3. Medicamentos em uso: ___________\n\nConsinto com o uso da anestesia necessária para o procedimento indicado.',
  },
  {
    value: 'geral',
    label: 'Termo de Consentimento Geral',
    icon: 'i-lucide-file-check',
    color: 'slate',
    description:
      'Termo geral para procedimentos não cobertos pelos tipos específicos acima.',
    template:
      'TERMO DE CONSENTIMENTO INFORMADO GERAL\n\nEu, [NOME DO PACIENTE], portador(a) do CPF [CPF], concordo com a realização do procedimento/tratamento indicado.\n\n1. Fui informado(a) sobre objetivos, riscos, benefícios e alternativas.\n2. Tive oportunidade de esclarecer todas as minhas dúvidas.\n3. Compreendo que resultados não são garantidos.\n4. Poderei revogar este consentimento a qualquer momento antes do procedimento.\n\nElaborado conforme resoluções do CFM e normas da ANVISA.',
  },
];

const CONSENT_STATUS_CONFIG = {
  pendente: {
    label: 'Pendente',
    cls: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
    icon: 'i-lucide-clock',
  },
  assinado_localmente: {
    label: 'Assinado',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    icon: 'i-lucide-check-circle',
  },
  assinado_remotamente: {
    label: 'Assinado (Remoto)',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    icon: 'i-lucide-check-circle',
  },
  signed: {
    label: 'Assinado',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    icon: 'i-lucide-check-circle',
  },
  vencido: {
    label: 'Vencido',
    cls: 'bg-red-500/10 text-red-400 border-red-500/20',
    icon: 'i-lucide-alert-triangle',
  },
  revogado: {
    label: 'Revogado',
    cls: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
    icon: 'i-lucide-x-circle',
  },
};

const newConsentForm = ref({
  consent_type: '',
  title: '',
  body: '',
  expires_in_months: 12,
  observations: '',
});

const fetchConsents = async () => {
  consentLoading.value = true;
  try {
    const res = await ConsentsAPI.get(route.params.patientId);
    consents.value = res.data?.data || res.data || [];
  } catch (error) {
    // ignore
  } finally {
    consentLoading.value = false;
  }
};

const consentTypeDetail = computed(() =>
  CONSENT_TYPES.find(t => t.value === newConsentForm.value.consent_type)
);

const selectConsentType = type => {
  if (!type) return;
  newConsentForm.value.consent_type = type.value;
  newConsentForm.value.title = type.label;

  // Formata data de nascimento para DD/MM/AAAA
  let birthFormatted = '________________';
  if (patient.value?.birthdate) {
    try {
      const d = new Date(patient.value.birthdate);
      birthFormatted = d.toLocaleDateString('pt-BR', { timeZone: BRT });
    } catch {
      birthFormatted = patient.value.birthdate;
    }
  }

  // Formata CPF
  let cpfFormatted = '________________';
  if (patient.value?.cpf) {
    cpfFormatted = patient.value.cpf.replace(
      /(\d{3})(\d{3})(\d{3})(\d{2})/,
      '$1.$2.$3-$4'
    );
  }

  // Monta endereço completo do cadastro
  const addr = patient.value?.address || {};
  const fullAddress =
    [
      addr.street,
      addr.number,
      addr.complement,
      addr.neighborhood,
      addr.city,
      addr.state,
      addr.zip,
    ]
      .filter(Boolean)
      .join(', ') || '________________';

  newConsentForm.value.body = type.template
    .replace('[NOME DO PACIENTE]', patient.value?.name || '________________')
    .replace('[NOME DO RESPONSÁVEL]', '________________')
    .replace('[CPF]', cpfFormatted)
    .replace('[DATA DE NASCIMENTO]', birthFormatted)
    .replace('[ENDEREÇO]', fullAddress)
    .replace('[RG]', patient.value?.rg || '________________')
    .replace('[EMAIL]', patient.value?.email || '________________')
    .replace('[TELEFONE]', patient.value?.phone || '________________');
};

const onConsentTypeChange = () => {
  const type = CONSENT_TYPES.find(
    t => t.value === newConsentForm.value.consent_type
  );
  selectConsentType(type);
};

const openConsentModal = () => {
  newConsentForm.value = {
    consent_type: '',
    title: '',
    body: '',
    expires_in_months: 12,
    observations: '',
  };
  showConsentModal.value = true;
};

const createConsent = async () => {
  if (!newConsentForm.value.consent_type || !newConsentForm.value.title) {
    useAlert('Selecione o tipo de consentimento.');
    return;
  }
  consentModalLoading.value = true;
  try {
    await ConsentsAPI.create(route.params.patientId, {
      title: newConsentForm.value.title,
      document_type: newConsentForm.value.consent_type,
      body: newConsentForm.value.body,
      expires_after_days: newConsentForm.value.expires_in_months * 30,
      observations: newConsentForm.value.observations,
    });
    showConsentModal.value = false;
    await fetchConsents();
    useAlert('Consentimento criado com sucesso!');
  } catch (err) {
    useAlert(
      `Erro ao criar consentimento: ${err?.response?.data?.error || 'Tente novamente.'}`
    );
  } finally {
    consentModalLoading.value = false;
  }
};

const openSignModal = id => {
  signingConsentId.value = id;
  hasSignature.value = false;
  showSignModal.value = true;
  nextTick(() => clearSignature());
};

let lastX = 0;
let lastY = 0;
const getCanvasCoords = (canvas, e) => {
  const rect = canvas.getBoundingClientRect();
  const clientX = e.touches ? e.touches[0].clientX : e.clientX;
  const clientY = e.touches ? e.touches[0].clientY : e.clientY;
  // Scale ratio: canvas intrinsic size vs CSS rendered size
  const scaleX = canvas.width / rect.width;
  const scaleY = canvas.height / rect.height;
  return {
    x: (clientX - rect.left) * scaleX,
    y: (clientY - rect.top) * scaleY,
  };
};
const startDrawing = e => {
  isDrawing.value = true;
  const coords = getCanvasCoords(signatureCanvas.value, e);
  lastX = coords.x;
  lastY = coords.y;
};
const draw = e => {
  if (!isDrawing.value || !signatureCanvas.value) return;
  e.preventDefault();
  const canvas = signatureCanvas.value;
  const ctx = canvas.getContext('2d');
  const coords = getCanvasCoords(canvas, e);
  ctx.beginPath();
  ctx.moveTo(lastX, lastY);
  ctx.lineTo(coords.x, coords.y);
  ctx.strokeStyle = '#60a5fa';
  ctx.lineWidth = 2.5;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.stroke();
  lastX = coords.x;
  lastY = coords.y;
  hasSignature.value = true;
};
const stopDrawing = () => {
  isDrawing.value = false;
};
const clearSignature = () => {
  if (!signatureCanvas.value) return;
  const canvas = signatureCanvas.value;
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  hasSignature.value = false;
};

const confirmSign = async () => {
  if (!hasSignature.value) {
    useAlert('Por favor, assine no campo acima.');
    return;
  }
  consentModalLoading.value = true;
  try {
    // Preferir WebP (menor tamanho), com fallback automático para PNG em browsers antigos
    const blob = signatureCanvas.value.toDataURL('image/webp', 0.85);

    await ConsentsAPI.sign(
      route.params.patientId,
      signingConsentId.value,
      blob
    );
    showSignModal.value = false;
    await fetchConsents();
    useAlert('Consentimento assinado com sucesso!');
  } catch (err) {
    useAlert(
      `Erro ao assinar: ${err?.response?.data?.error || 'Tente novamente.'}`
    );
  } finally {
    consentModalLoading.value = false;
  }
};

const viewConsent = async consent => {
  consentInView.value = consent;
  showViewModal.value = true;

  // Se assinado, busca o show para ter signature_blob e signature_image_url
  if (
    ['assinado_localmente', 'assinado_remotamente'].includes(consent.status)
  ) {
    try {
      const { data } = await ConsentsAPI.show(
        route.params.patientId,
        consent.id
      );
      consentInView.value = data;
    } catch (_) {
      // mantém o objeto da listagem se falhar
    }
  }
};

const sendConsentRemote = async consentId => {
  try {
    await ConsentsAPI.sendRemote(route.params.patientId, consentId);
    useAlert(
      'Link para assinatura enviado com sucesso para o WhatsApp do paciente!'
    );
  } catch (error) {
    useAlert('Erro ao enviar link para assinatura.');
  }
};

const revokeConsent = async consentId => {
  if (
    !confirm(
      'Tem certeza que deseja revogar este consentimento? Esta ação não pode ser desfeita.'
    )
  )
    return;
  try {
    await ConsentsAPI.revoke?.(route.params.patientId, consentId);
    await fetchConsents();
    useAlert('Consentimento revogado.');
  } catch (error) {
    useAlert('Erro ao revogar consentimento.');
  }
};

const consentStats = computed(() => ({
  total: consents.value.length,
  signed: consents.value.filter(c =>
    ['signed', 'assinado_localmente', 'assinado_remotamente'].includes(c.status)
  ).length,
  pending: consents.value.filter(c => c.status === 'pendente' || !c.status)
    .length,
  expired: consents.value.filter(c => c.status === 'vencido').length,
}));

const consentStatusLabel = status =>
  CONSENT_STATUS_CONFIG[status] || CONSENT_STATUS_CONFIG.pendente;
const consentTypeLabel = type =>
  CONSENT_TYPES.find(t => t.value === type)?.label || type || 'Consentimento';
const signConsentNow = id => openSignModal(id);
// ── Treatment Plans & Sessions ───────────────────────────────
const treatmentPlans = ref([]);
const sessionLogs = ref([]);
const uniqueProceduresLogged = computed(() => {
  const names = sessionLogs.value
    .map(log => log.procedure_name || log.treatment_plan_title)
    .filter(Boolean);
  return [...new Set(names)].sort();
});

const editingPlanId = ref(null);
const showItemModal = ref(false);
const activePlanId = ref(null);
const currentItem = ref({
  id: null,
  procedure_name: '',
  region: '',
  sessions_planned: 1,
});
const isSavingItem = ref(false);

const globalDiagnosisTitle = ref('');
const globalDiagnosisDescription = ref('');

const fetchTreatmentPlans = async () => {
  try {
    const { data } = await TreatmentPlansAPI.get(route.params.patientId);
    treatmentPlans.value = data?.data || data || [];
  } catch (error) {
    useAlert('Erro ao carregar planos de tratamento.');
  }
};

const createTreatmentPlan = async () => {
  try {
    const res = await TreatmentPlansAPI.create(route.params.patientId, {
      title: globalDiagnosisTitle.value,
      description: globalDiagnosisDescription.value,
    });
    useAlert('Novo plano criado!');
    await fetchTreatmentPlans();

    // Automatically set the new plan to editing mode
    const newId = res.data?.payload?.id || res.data?.id;
    if (newId) editingPlanId.value = newId;

    // Clear global form fields
    globalDiagnosisTitle.value = '';
    globalDiagnosisDescription.value = '';
  } catch (error) {
    useAlert('Erro ao criar plano.');
  }
};

const savePlan = async plan => {
  try {
    await TreatmentPlansAPI.update(route.params.patientId, plan.id, {
      title: plan.title,
      description: plan.description,
      estimated_duration: plan.estimated_duration,
    });
    editingPlanId.value = null;
    useAlert('Plano atualizado com sucesso!');
    fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao atualizar plano.');
  }
};

const approvePlan = async planId => {
  try {
    await TreatmentPlansAPI.approve(route.params.patientId, planId);
    editingPlanId.value = null;
    useAlert('Plano aprovado e comissionamento disparado!');
    await fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao aprovar plano.');
  }
};

const showConfirmDeletePlan = ref(false);
const planToDelete = ref(null);

const requestDeletePlan = planId => {
  planToDelete.value = planId;
  showConfirmDeletePlan.value = true;
};

const cancelDeletePlan = () => {
  showConfirmDeletePlan.value = false;
  planToDelete.value = null;
};

const confirmDeletePlan = async () => {
  if (!planToDelete.value) return;
  try {
    await TreatmentPlansAPI.destroy(route.params.patientId, planToDelete.value);
    useAlert('Plano excluído com sucesso!');
    await fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao excluir plano.');
  } finally {
    cancelDeletePlan();
  }
};

const openItemModal = async (plan, item = null) => {
  if (editingPlanId.value === plan.id) {
    try {
      await TreatmentPlansAPI.update(route.params.patientId, plan.id, {
        title: plan.title,
        description: plan.description,
        estimated_duration: plan.estimated_duration,
      });
      editingPlanId.value = null;
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
    }
  }

  activePlanId.value = plan.id;
  if (item) {
    currentItem.value = { ...item };
  } else {
    currentItem.value = {
      id: null,
      procedure_name: '',
      region: '',
      sessions_planned: 1,
      unit_price: 0,
    };
  }
  showItemModal.value = true;
};

const handleProcedureSelect = () => {
  const selectedService = agendaServices.value.find(
    s => s.name === currentItem.value.procedure_name
  );
  if (selectedService) {
    currentItem.value.unit_price = selectedService.price;
  }
};

const saveItem = async () => {
  isSavingItem.value = true;
  try {
    if (currentItem.value.id) {
      await TreatmentPlansAPI.updateItem(
        route.params.patientId,
        activePlanId.value,
        currentItem.value.id,
        currentItem.value
      );
      useAlert('Procedimento atualizado!');
    } else {
      await TreatmentPlansAPI.createItem(
        route.params.patientId,
        activePlanId.value,
        currentItem.value
      );
      useAlert('Procedimento adicionado!');
    }
    showItemModal.value = false;
    fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao salvar procedimento.');
  } finally {
    isSavingItem.value = false;
  }
};

const showConfirmDeleteItem = ref(false);
const itemToDelete = ref({ planId: null, itemId: null });

const requestDeleteItem = (planId, itemId) => {
  itemToDelete.value = { planId, itemId };
  showConfirmDeleteItem.value = true;
};

const cancelDeleteItem = () => {
  showConfirmDeleteItem.value = false;
  itemToDelete.value = { planId: null, itemId: null };
};

const confirmDeleteItem = async () => {
  if (!itemToDelete.value.planId || !itemToDelete.value.itemId) return;
  try {
    await TreatmentPlansAPI.deleteItem(
      route.params.patientId,
      itemToDelete.value.planId,
      itemToDelete.value.itemId
    );
    useAlert('Procedimento removido!');
    fetchTreatmentPlans();
  } catch (error) {
    useAlert('Erro ao remover procedimento.');
  } finally {
    cancelDeleteItem();
  }
};

const printPlan = plan => {
  if (plan && plan.pdf_url) {
    window.open(plan.pdf_url, '_blank');
  } else {
    window.print();
  }
};

// ── Procedures / Session Logs ─────────────────────────────────
const isSessionsLoading = ref(false);
const isSavingSession = ref(false);
const sessionHistoryFilter = ref({
  procedure_name: '',
  date_from: '',
  date_to: '',
});
const showFilterPanel = ref(false);

// Form reativo para registrar novo procedimento
const newSession = ref({
  procedure_name: '',
  area_treated: '',
  product_name: '',
  quantity: '',
  batch: '',
  complications: '',
  result_observed: '',
  return_needed: false,
  return_in_days: null,
  performed_at: new Date().toISOString().split('T')[0],
  duration_minutes: 30,
});

const resetSessionForm = () => {
  newSession.value = {
    procedure_name: '',
    area_treated: '',
    product_name: '',
    quantity: '',
    batch: '',
    complications: '',
    result_observed: '',
    return_needed: false,
    return_in_days: null,
    performed_at: new Date().toISOString().split('T')[0],
    duration_minutes: 30,
  };
};

const fetchSessionLogs = async () => {
  isSessionsLoading.value = true;
  try {
    const { data } = await SessionLogsAPI.get(route.params.patientId);
    sessionLogs.value = Array.isArray(data)
      ? data
      : data?.data || data?.payload || [];
  } catch (error) {
    useAlert('Erro ao carregar sessões.');
  } finally {
    isSessionsLoading.value = false;
  }
};

const saveSession = async () => {
  if (!newSession.value.performed_at) {
    useAlert('Informe a data da sessão.');
    return;
  }
  isSavingSession.value = true;
  try {
    const payload = {
      performed_at: newSession.value.performed_at,
      procedure_name: newSession.value.procedure_name,
      duration_minutes: newSession.value.duration_minutes || 30,
      complications: newSession.value.complications || null,
      result_observed: newSession.value.result_observed || null,
      return_needed: !!newSession.value.return_in_days,
      return_in_days: newSession.value.return_in_days || null,
      areas_treated: newSession.value.area_treated
        ? [
            {
              region: newSession.value.area_treated,
              description: newSession.value.procedure_name,
            },
          ]
        : [],
      products_used: newSession.value.product_name
        ? [
            {
              name: newSession.value.product_name,
              quantity: newSession.value.quantity || '1',
              unit: 'un',
              batch: newSession.value.batch || null,
            },
          ]
        : [],
    };
    await SessionLogsAPI.create(route.params.patientId, payload);
    useAlert('Sessão registrada com sucesso!');
    resetSessionForm();
    await fetchSessionLogs();
  } catch (error) {
    const msg = error?.response?.data?.error || 'Erro ao registrar sessão.';
    useAlert(msg);
  } finally {
    isSavingSession.value = false;
  }
};

const registerSession = () => {
  document
    .querySelector('.session-form-card')
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

const showConfirmDeleteSession = ref(false);
const sessionToDelete = ref(null);

const requestDeleteSessionLog = logId => {
  sessionToDelete.value = logId;
  showConfirmDeleteSession.value = true;
};

const cancelDeleteSessionLog = () => {
  showConfirmDeleteSession.value = false;
  sessionToDelete.value = null;
};

const confirmDeleteSessionLog = async () => {
  if (!sessionToDelete.value) return;
  try {
    await SessionLogsAPI.delete(route.params.patientId, sessionToDelete.value);
    useAlert('Registro removido com sucesso.');
    await fetchSessionLogs();
  } catch (error) {
    useAlert('Erro ao remover sessão.');
  } finally {
    cancelDeleteSessionLog();
  }
};

const toggleFilterPanel = () => {
  showFilterPanel.value = !showFilterPanel.value;
};

const applySessionFilter = async () => {
  isSessionsLoading.value = true;
  try {
    const params = {};
    if (sessionHistoryFilter.value.procedure_name)
      params.procedure_name = sessionHistoryFilter.value.procedure_name;
    if (sessionHistoryFilter.value.date_from)
      params.from = sessionHistoryFilter.value.date_from;
    if (sessionHistoryFilter.value.date_to)
      params.to = sessionHistoryFilter.value.date_to;
    const { data } = await SessionLogsAPI.get(route.params.patientId, params);
    sessionLogs.value = Array.isArray(data)
      ? data
      : data?.data || data?.payload || [];
    showFilterPanel.value = false;
    useAlert(`${sessionLogs.value.length} sessão(ões) encontrada(s).`);
  } catch (error) {
    useAlert('Erro ao filtrar histórico.');
  } finally {
    isSessionsLoading.value = false;
  }
};

const clearSessionFilter = async () => {
  sessionHistoryFilter.value = {
    procedure_name: '',
    date_from: '',
    date_to: '',
  };
  showFilterPanel.value = false;
  await fetchSessionLogs();
};

const openBeforeAfterPhotos = () => {
  activeTab.value = 'exams';
};

const financialSummary = ref(null);
const transactions = ref([]);
const financialEstimates = ref([]);
const activeFinancialTab = ref('transactions');
const financialFilter = ref('all');
const financialLoading = ref(false);

// Helpers de formatação BRL para inputs
const subtotalRaw = ref('');
const formatCurrencyInput = val => {
  const num = parseFloat(String(val).replace(/\./g, '').replace(',', '.'));
  if (Number.isNaN(num)) return '';
  return num.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};
const parseCurrencyInput = val => {
  const cleaned = String(val).replace(/\./g, '').replace(',', '.');
  const num = parseFloat(cleaned);
  return Number.isNaN(num) ? 0 : num;
};
const onSubtotalInput = e => {
  // Mantém apenas dígitos
  const raw = e.target.value.replace(/\D/g, '');
  const cents = parseInt(raw || '0', 10);
  const num = cents / 100;
  subtotalRaw.value = num.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  e.target.value = subtotalRaw.value;
};

// Modal: Receber Pagamento
const showPayModal = ref(false);
const payModalLoading = ref(false);
const selectedTxId = ref(null);
const bankAccountsForPay = ref([]);
const payForm = ref({
  payment_method: 'pix',
  paid_at: new Date().toISOString().split('T')[0],
  bank_account_id: '',
  notes: '',
});

const loadBankAccountsForPay = async () => {
  try {
    const { data } = await bankAccountsApi.get();
    bankAccountsForPay.value = data.bank_accounts || [];
  } catch {
    bankAccountsForPay.value = [];
  }
};

// Modal: Novo Orçamento
const showEstimateModal = ref(false);
const estimateModalLoading = ref(false);
const estimateForm = ref({
  discount_type: 'fixo',
  discount_value: 0,
  installments_count: 1,
  payment_method: 'pix',
  notes: '',
  valid_until: new Date(Date.now() + 30 * 864e5).toISOString().split('T')[0],
});

const TX_STATUS_CONFIG = {
  pago: {
    label: 'PAGO',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    icon: 'i-lucide-check-circle-2',
  },
  pendente: {
    label: 'EM ABERTO',
    cls: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
    icon: 'i-lucide-calendar',
  },
  vencido: {
    label: 'VENCIDO',
    cls: 'bg-red-500/10 text-red-400 border-red-500/20',
    icon: 'i-lucide-clock-3',
  },
  cancelado: {
    label: 'CANCELADO',
    cls: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
    icon: 'i-lucide-x-circle',
  },
  reembolsado: {
    label: 'ESTORNADO',
    cls: 'bg-purple-500/10 text-purple-400 border-purple-500/20',
    icon: 'i-lucide-rotate-ccw',
  },
};

const ESTIMATE_STATUS_CONFIG = {
  rascunho: {
    label: 'Rascunho',
    cls: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
  },
  enviado: {
    label: 'Enviado',
    cls: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
  },
  aprovado: {
    label: 'Aprovado',
    cls: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
  },
  cancelado: {
    label: 'Cancelado',
    cls: 'bg-red-500/10 text-red-400 border-red-500/20',
  },
};

const filteredTransactions = computed(() => {
  const list = transactions.value || [];
  const today = new Date().toISOString().split('T')[0];
  switch (financialFilter.value) {
    case 'pendente':
      return list.filter(
        t => t.status === 'pendente' && (!t.due_date || t.due_date >= today)
      );
    case 'pago':
      return list.filter(t => t.status === 'pago');
    case 'vencido':
      return list.filter(
        t =>
          t.status === 'vencido' ||
          (t.status === 'pendente' && t.due_date && t.due_date < today)
      );
    default:
      return list;
  }
});

// Parcelas pendentes para selecionar no modal Receber
const pendingTransactions = computed(() =>
  (transactions.value || []).filter(
    t => t.status === 'pendente' || t.status === 'vencido'
  )
);

const fetchFinancialData = async () => {
  financialLoading.value = true;
  try {
    const [summaryRes, txRes, estimatesRes] = await Promise.all([
      TransactionsAPI.getSummary(route.params.patientId),
      TransactionsAPI.get(route.params.patientId),
      FinancialEstimatesAPI.get(route.params.patientId),
    ]);
    financialSummary.value = summaryRes.data;
    if (summaryRes.data?.overall_status) {
      const s = summaryRes.data.overall_status;
      if (s === 'inadimplente') patient.value.financialStatus = 'Inadimplente';
      else patient.value.financialStatus = 'Adimplente';
    }
    transactions.value = (
      txRes.data?.transactions ||
      txRes.data?.data ||
      txRes.data ||
      []
    ).map(tx => {
      if (tx.status === 'pendente' && tx.is_overdue) {
        return { ...tx, status: 'vencido' };
      }
      return tx;
    });
    financialEstimates.value =
      estimatesRes.data?.financial_estimates ||
      estimatesRes.data?.data ||
      estimatesRes.data ||
      [];
  } catch {
    useAlert('Erro ao carregar dados financeiros.');
  } finally {
    financialLoading.value = false;
  }
};

const openPayModal = (txId = null) => {
  selectedTxId.value = txId;
  payForm.value = {
    payment_method: 'pix',
    paid_at: new Date().toISOString().split('T')[0],
    bank_account_id:
      bankAccountsForPay.value.length === 1
        ? bankAccountsForPay.value[0].id
        : '',
    notes: '',
  };
  showPayModal.value = true;
};

const confirmPayment = async () => {
  if (!selectedTxId.value) return;
  payModalLoading.value = true;
  try {
    await TransactionsAPI.pay(route.params.patientId, selectedTxId.value, {
      payment_method: payForm.value.payment_method,
      paid_at: payForm.value.paid_at,
      bank_account_id: payForm.value.bank_account_id || null,
    });
    useAlert('Pagamento registrado com sucesso!');
    showPayModal.value = false;
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao registrar pagamento.');
  } finally {
    payModalLoading.value = false;
  }
};

const payTransaction = txId => openPayModal(txId);

const openEstimateModal = () => {
  subtotalRaw.value = '';
  estimateForm.value = {
    discount_type: 'fixo',
    discount_value: 0,
    installments_count: 1,
    payment_method: 'pix',
    notes: '',
    valid_until: new Date(Date.now() + 30 * 864e5).toISOString().split('T')[0],
  };
  showEstimateModal.value = true;
};

const confirmCreateEstimate = async () => {
  const subtotalValue = parseCurrencyInput(subtotalRaw.value);
  if (!subtotalValue || subtotalValue <= 0) {
    useAlert('Informe um subtotal válido.');
    return;
  }
  estimateModalLoading.value = true;
  try {
    await FinancialEstimatesAPI.create(route.params.patientId, {
      subtotal: subtotalValue,
      discount_type: estimateForm.value.discount_type,
      discount_value:
        parseCurrencyInput(estimateForm.value.discount_value) || 0,
      installments_count:
        parseInt(estimateForm.value.installments_count, 10) || 1,
      payment_method: estimateForm.value.payment_method,
      notes: estimateForm.value.notes,
      valid_until: estimateForm.value.valid_until,
    });
    useAlert('Orçamento criado com sucesso!');
    showEstimateModal.value = false;
    activeFinancialTab.value = 'estimates';
    await fetchFinancialData();
  } catch (e) {
    const msg =
      e.response?.data?.errors?.join(', ') || 'Erro ao criar orçamento.';
    useAlert(msg);
  } finally {
    estimateModalLoading.value = false;
  }
};

const approveEstimate = async estimateId => {
  try {
    await FinancialEstimatesAPI.approve(route.params.patientId, estimateId);
    useAlert('Orçamento aprovado!');
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao aprovar orçamento.');
  }
};

const cancelEstimate = async estimateId => {
  try {
    await FinancialEstimatesAPI.cancel(route.params.patientId, estimateId);
    useAlert('Orçamento cancelado.');
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao cancelar orçamento.');
  }
};

const chargeWhatsapp = async txId => {
  try {
    const res = await TransactionsAPI.chargeWhatsapp(
      route.params.patientId,
      txId
    );
    const msg = res.data?.whatsapp_message || '';
    const phone = res.data?.phone || '';
    if (phone) {
      const url = `https://wa.me/${phone.replace(/\D/g, '')}?text=${encodeURIComponent(msg)}`;
      window.open(url, '_blank');
    } else {
      useAlert('Cobrança preparada — paciente sem telefone cadastrado.');
    }
  } catch {
    useAlert('Erro ao preparar cobrança WhatsApp.');
  }
};

const refundTransaction = async txId => {
  if (!window.confirm('Confirmar estorno desta transação?')) return;
  try {
    await TransactionsAPI.refund(route.params.patientId, txId);
    useAlert('Transação estornada com sucesso!');
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao estornar transação.');
  }
};

// ── Comprovante de Pagamento ────────────────────────────────
const showProofModal = ref(false);
const proofTxId = ref(null);
const proofUploading = ref(false);
const proofTx = computed(() =>
  transactions.value.find(t => t.id === proofTxId.value)
);

const openProofModal = txId => {
  proofTxId.value = txId;
  showProofModal.value = true;
};

const handleProofUpload = async event => {
  const file = event.target.files[0];
  if (!file) return;
  proofUploading.value = true;
  try {
    await TransactionsAPI.uploadProof(
      route.params.patientId,
      proofTxId.value,
      file
    );
    useAlert('Comprovante anexado com sucesso!');
    showProofModal.value = false;
    await fetchFinancialData();
  } catch {
    useAlert('Erro ao anexar comprovante.');
  } finally {
    proofUploading.value = false;
  }
};

const viewProof = async tx => {
  if (tx.payment_proof_url) {
    window.open(tx.payment_proof_url, '_blank');
  }
};

const showPrintModal = ref(false);
const printHtmlContent = ref('');
const printTitle = ref('');

const openPrintPreview = (html, title) => {
  printHtmlContent.value = html;
  printTitle.value = title;
  showPrintModal.value = true;
};

const printFinancial = () => {
  const p = patient.value;
  const name = p?.name || 'Paciente';
  const today = new Date().toLocaleDateString('pt-BR', { timeZone: BRT });

  const txRows = (transactions.value || [])
    .map(tx => {
      const s = txStatusConfig(tx.status);
      return `<tr>
      <td>${tx.due_date ? new Date(tx.due_date + 'T12:00:00').toLocaleDateString('pt-BR', { timeZone: BRT }) : '—'}</td>
      <td>${tx.description || '—'}</td>
      <td>${tx.installment_number || 1}/${tx.total_installments || 1}</td>
      <td style="font-weight:600">${formatCurrency(tx.amount)}</td>
      <td>${tx.payment_method || '—'}</td>
      <td><span style="padding:2px 8px;border-radius:20px;font-size:11px;background:${tx.status === 'pago' ? '#d1fae5' : tx.status === 'vencido' ? '#fee2e2' : '#f1f5f9'};color:${tx.status === 'pago' ? '#065f46' : tx.status === 'vencido' ? '#991b1b' : '#334155'}">${s.label}</span></td>
    </tr>`;
    })
    .join('');

  const estRows = (financialEstimates.value || [])
    .map(est => {
      const s = estimateStatusConfig(est.status);
      return `<tr>
      <td>#${est.id}</td>
      <td>${est.created_at ? new Date(est.created_at).toLocaleDateString('pt-BR', { timeZone: BRT }) : '—'}</td>
      <td style="font-weight:600">${formatCurrency(est.subtotal)}</td>
      <td>${est.discount_amount > 0 ? '- ' + formatCurrency(est.discount_amount) : '—'}</td>
      <td style="font-weight:600;color:#059669">${formatCurrency(est.total)}</td>
      <td>${est.installments_count}x de ${formatCurrency(est.installment_value)}</td>
      <td><span style="padding:2px 8px;border-radius:20px;font-size:11px;background:${est.status === 'aprovado' ? '#d1fae5' : est.status === 'cancelado' ? '#fee2e2' : '#f1f5f9'};color:${est.status === 'aprovado' ? '#065f46' : est.status === 'cancelado' ? '#991b1b' : '#334155'}">${s.label}</span></td>
    </tr>`;
    })
    .join('');

  const html = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Extrato Financeiro — ${name}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 13px; color: #1e293b; background: #fff; padding: 32px; }
    .header { display: flex; justify-content: space-between; align-items: flex-start; border-bottom: 2px solid #0f172a; padding-bottom: 16px; margin-bottom: 24px; }
    .clinic-name { font-size: 20px; font-weight: 700; color: #0f172a; }
    .clinic-sub { font-size: 12px; color: #64748b; margin-top: 2px; }
    .patient-name { font-size: 18px; font-weight: 600; text-align: right; }
    .patient-meta { font-size: 12px; color: #64748b; text-align: right; }
    .kpis { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }
    .kpi { border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px 16px; }
    .kpi-label { font-size: 10px; text-transform: uppercase; letter-spacing: .05em; color: #94a3b8; margin-bottom: 4px; }
    .kpi-value { font-size: 20px; font-weight: 700; }
    .kpi-value.red { color: #dc2626; }
    .kpi-value.green { color: #16a34a; }
    .kpi-value.blue { color: #2563eb; }
    h2 { font-size: 14px; font-weight: 600; color: #0f172a; margin: 20px 0 8px; text-transform: uppercase; letter-spacing: .05em; }
    table { width: 100%; border-collapse: collapse; font-size: 12px; }
    th { background: #f8fafc; text-align: left; padding: 8px 10px; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: .04em; color: #64748b; border-bottom: 1px solid #e2e8f0; }
    td { padding: 8px 10px; border-bottom: 1px solid #f1f5f9; vertical-align: middle; }
    tr:last-child td { border-bottom: none; }
    .footer { margin-top: 32px; border-top: 1px solid #e2e8f0; padding-top: 12px; font-size: 11px; color: #94a3b8; text-align: center; }
    @media print { body { padding: 16px; } }
  </style>
</head>
<body>
  <div class="header">
    <div>
      <div class="clinic-name">BeClinic</div>
      <div class="clinic-sub">Extrato Financeiro do Paciente</div>
    </div>
    <div>
      <div class="patient-name">${name}</div>
      <div class="patient-meta">Emitido em ${today}</div>
    </div>
  </div>

  <div class="kpis">
    <div class="kpi">
      <div class="kpi-label">Total Aprovado</div>
      <div class="kpi-value">${formatCurrency(financialSummary.value?.total_approved)}</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Pago / Recebido</div>
      <div class="kpi-value green">${formatCurrency(financialSummary.value?.total_paid)}</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Aberto / Devedor</div>
      <div class="kpi-value red">${formatCurrency(financialSummary.value?.total_open)}</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Crédito Disponível</div>
      <div class="kpi-value blue">${formatCurrency(financialSummary.value?.credit_balance)}</div>
    </div>
  </div>

  <h2>Transações / Extrato</h2>
  <table>
    <thead><tr><th>Vencimento</th><th>Descrição</th><th>Parcela</th><th>Valor</th><th>Método</th><th>Status</th></tr></thead>
    <tbody>${txRows || '<tr><td colspan="6" style="text-align:center;color:#94a3b8;padding:16px">Nenhuma transação</td></tr>'}</tbody>
  </table>

  <h2>Orçamentos e Planos</h2>
  <table>
    <thead><tr><th>#</th><th>Data</th><th>Subtotal</th><th>Desconto</th><th>Total</th><th>Parcelas</th><th>Status</th></tr></thead>
    <tbody>${estRows || '<tr><td colspan="7" style="text-align:center;color:#94a3b8;padding:16px">Nenhum orçamento</td></tr>'}</tbody>
  </table>

  <div class="footer">BeClinic — Documento gerado automaticamente em ${today}</div>
</body>
</html>`;

  openPrintPreview(html, 'Extrato Financeiro');
};

const printReceipt = tx => {
  const p = patient.value;
  const name = p?.name || 'Paciente';
  const paidAt = tx.paid_at
    ? new Date(tx.paid_at + 'T12:00:00').toLocaleDateString('pt-BR', {
        timeZone: BRT,
      })
    : new Date().toLocaleDateString('pt-BR', { timeZone: BRT });
  const methodLabel =
    {
      pix: 'PIX',
      cartao_credito: 'Cartão de Crédito',
      cartao_debito: 'Cartão de Débito',
      dinheiro: 'Dinheiro',
      boleto: 'Boleto',
      transferencia: 'Transferência Bancária',
      outros: 'Outros',
    }[tx.payment_method] ||
    tx.payment_method ||
    '—';
  const receiptNum = String(tx.id).padStart(6, '0');
  const today = new Date().toLocaleDateString('pt-BR', { timeZone: BRT });

  const html = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>Recibo #${receiptNum} — ${name}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Helvetica Neue', Arial, sans-serif; color: #1e293b; background: #fff; }
    .page { max-width: 600px; margin: 0 auto; padding: 48px 40px; }
    .top-bar { background: #0f172a; color: #fff; padding: 20px 40px; display: flex; justify-content: space-between; align-items: center; }
    .clinic-name { font-size: 20px; font-weight: 800; letter-spacing: -0.5px; }
    .receipt-tag { font-size: 11px; background: #f59e0b; color: #1e293b; font-weight: 700; padding: 3px 10px; border-radius: 999px; letter-spacing: .05em; }
    .receipt-id { font-size: 11px; color: #94a3b8; margin-top: 4px; }
    .hero { text-align: center; padding: 36px 0 28px; border-bottom: 1px solid #e2e8f0; }
    .amount { font-size: 48px; font-weight: 800; color: #059669; letter-spacing: -1px; }
    .amount-label { font-size: 12px; color: #94a3b8; margin-bottom: 8px; text-transform: uppercase; letter-spacing: .08em; }
    .status-badge { display: inline-block; margin-top: 12px; background: #d1fae5; color: #065f46; font-weight: 700; font-size: 12px; padding: 4px 16px; border-radius: 999px; }
    .details { padding: 28px 0; border-bottom: 1px solid #e2e8f0; }
    .row { display: flex; justify-content: space-between; padding: 8px 0; font-size: 14px; }
    .row .label { color: #64748b; }
    .row .value { font-weight: 600; text-align: right; max-width: 55%; }
    .patient-section { padding: 24px 0 8px; }
    .patient-label { font-size: 11px; text-transform: uppercase; letter-spacing: .08em; color: #94a3b8; margin-bottom: 6px; }
    .patient-name { font-size: 18px; font-weight: 700; color: #0f172a; }
    .footer { margin-top: 40px; text-align: center; font-size: 11px; color: #c0cad8; }
    .divider { border: none; border-top: 1px dashed #e2e8f0; margin: 0; }
    @media print { @page { margin: 0; } body { margin: 0; } .page { padding: 32px; max-width: 100%; } .top-bar { -webkit-print-color-adjust: exact; print-color-adjust: exact; } .amount { -webkit-print-color-adjust: exact; print-color-adjust: exact; } .status-badge { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
  </style>
</head>
<body>
  <div class="top-bar">
    <div>
      <div class="clinic-name">BeClinic</div>
      <div class="receipt-id">Recibo N.º ${receiptNum}</div>
    </div>
    <span class="receipt-tag">RECIBO</span>
  </div>

  <div class="page">
    <div class="hero">
      <div class="amount-label">Valor Pago</div>
      <div class="amount">${formatCurrency(tx.amount)}</div>
      <span class="status-badge">✓ PAGAMENTO CONFIRMADO</span>
    </div>

    <div class="patient-section">
      <div class="patient-label">Paciente</div>
      <div class="patient-name">${name}</div>
    </div>

    <div class="details">
      <div class="row"><span class="label">Descrição</span><span class="value">${tx.description || 'Pagamento'}</span></div>
      <div class="row"><span class="label">Parcela</span><span class="value">${tx.installment_number || 1} de ${tx.total_installments || 1}</span></div>
      <div class="row"><span class="label">Método de Pagamento</span><span class="value">${methodLabel}</span></div>
      <div class="row"><span class="label">Data do Pagamento</span><span class="value">${paidAt}</span></div>
      <div class="row"><span class="label">Data de Emissão</span><span class="value">${today}</span></div>
    </div>

    <div class="footer">
      <p>Este documento é um comprovante de pagamento emitido pela BeClinic.</p>
      <p style="margin-top:4px">Recibo N.º ${receiptNum} — Gerado automaticamente em ${today}</p>
    </div>
  </div>
  </div>
</body>
</html>`;

  openPrintPreview(html, `Recibo #${receiptNum}`);
};

const txStatusConfig = status =>
  TX_STATUS_CONFIG[status] || TX_STATUS_CONFIG.pendente;
const estimateStatusConfig = status =>
  ESTIMATE_STATUS_CONFIG[status] || ESTIMATE_STATUS_CONFIG.rascunho;

// ── Agenda & Timeline ────────────────────────────────────────
const appointments = ref([]);
const appointmentsLoading = ref(false);
const appointmentFilter = ref('all'); // 'all' | 'upcoming' | 'issues'
const timelineEvents = ref([]);
const timelineLoading = ref(false);
const timelineFilter = ref('all');
const timelineFilterOpen = ref(false);
const timelineSortOrder = ref('newest'); // 'newest' | 'oldest'

// Agendamento: formulário removido — novo agendamento navega para a Agenda

const APPOINTMENT_TYPE_LABELS = {
  avaliacao: 'Avaliação',
  retorno: 'Retorno',
  procedimento: 'Procedimento',
  revisao: 'Revisão',
  emergencia: 'Emergência',
};

const EVENT_TYPE_LABELS = {
  consultation: 'Consulta',
  agenda_block: 'Bloqueio',
  appointment: 'Compromisso',
};

const PRIORITY_CONFIG = {
  urgent: {
    label: 'Urgente',
    cls: 'bg-red-500/15 text-red-500 border-red-500/20',
    text: '!!!',
  },
  high: {
    label: 'Alta',
    cls: 'bg-red-500/15 text-red-500 border-red-500/20',
    text: '!!!',
  },
  medium: {
    label: 'Média',
    cls: 'bg-yellow-500/15 text-yellow-500 border-yellow-500/20',
    text: '!!',
  },
  low: {
    label: 'Baixa',
    cls: 'bg-slate-500/15 text-slate-400 border-slate-500/20',
    text: '!',
  },
};

const priorityCfg = p => PRIORITY_CONFIG[p] || PRIORITY_CONFIG.medium;

const APPOINTMENT_STATUS_CONFIG = {
  scheduled: {
    label: 'Agendado',
    color: 'green',
    icon: 'i-lucide-calendar-clock',
    badgeCls: 'bg-green-500/10 text-green-500 border border-green-500/20',
    iconCls: 'bg-green-500/10 border-2 border-green-500/20 text-green-500',
    cardCls: 'bg-slate-800/40 border border-slate-700/50',
  },
  confirmed: {
    label: 'Confirmado',
    color: 'woot',
    icon: 'i-lucide-calendar-check',
    badgeCls: 'bg-woot-500/10 text-woot-400 border border-woot-500/20',
    iconCls: 'bg-woot-500/10 border-2 border-woot-500/20 text-woot-400',
    cardCls: 'bg-slate-800/40 border border-woot-500/20',
  },
  arrived: {
    label: 'Presente',
    color: 'violet',
    icon: 'i-lucide-user-check',
    badgeCls: 'bg-violet-500/10 text-violet-400 border border-violet-500/20',
    iconCls: 'bg-violet-500/10 border-2 border-violet-500/20 text-violet-400',
    cardCls: 'bg-slate-800/40 border border-violet-500/20',
  },
  in_progress: {
    label: 'Em Atendimento',
    color: 'yellow',
    icon: 'i-lucide-stethoscope',
    badgeCls: 'bg-yellow-500/10 text-yellow-500/80 border border-yellow-500/20',
    iconCls: 'bg-yellow-500/10 border-2 border-yellow-500/20 text-yellow-400',
    cardCls: 'bg-slate-800/40 border border-yellow-500/20',
  },
  done: {
    label: 'Realizado',
    color: 'green',
    icon: 'i-lucide-check-circle-2',
    badgeCls: 'bg-green-500/10 text-green-400 border border-green-500/20',
    iconCls: 'bg-green-500/10 border-2 border-green-500/20 text-green-400',
    cardCls: 'bg-slate-800/40 border border-green-500/10',
  },
  no_show: {
    label: 'Falta',
    color: 'yellow',
    icon: 'i-lucide-user-x',
    badgeCls: 'bg-yellow-500/10 text-yellow-500 border border-yellow-500/20',
    iconCls: 'bg-yellow-500/10 border-2 border-yellow-500/20 text-yellow-500',
    cardCls: 'bg-slate-800/40 border border-yellow-500/20',
  },
  canceled: {
    label: 'Cancelado',
    color: 'red',
    icon: 'i-lucide-x-circle',
    badgeCls: 'bg-red-500/10 text-red-500 border border-red-500/20',
    iconCls: 'bg-red-500/10 border-2 border-red-500/20 text-red-500',
    cardCls: 'bg-slate-800/40 border border-slate-700/30',
  },
  rescheduled: {
    label: 'Reagendado',
    color: 'yellow',
    icon: 'i-lucide-calendar-arrow-up',
    badgeCls: 'bg-yellow-500/10 text-yellow-500/80 border border-yellow-500/20',
    iconCls: 'bg-yellow-500/10 border-2 border-yellow-500/20 text-yellow-400',
    cardCls: 'bg-slate-800/40 border border-yellow-500/20',
  },
};

const aptStatusCfg = status =>
  APPOINTMENT_STATUS_CONFIG[status] || APPOINTMENT_STATUS_CONFIG.scheduled;

// Filtered appointments based on active tab — sorted ascending (closest first)
const filteredAppointments = computed(() => {
  const list = appointments.value || [];
  let result;
  if (appointmentFilter.value === 'upcoming') {
    result = list.filter(a => a.is_upcoming);
  } else if (appointmentFilter.value === 'issues') {
    result = list.filter(a =>
      ['no_show', 'canceled', 'rescheduled'].includes(a.status)
    );
  } else {
    result = [...list];
  }
  // Ordena crescente: mais próximo aparece primeiro
  return result.slice().sort((a, b) => {
    const da = new Date(a.scheduled_at || 0).getTime();
    const db = new Date(b.scheduled_at || 0).getTime();
    return da - db;
  });
});

// ID do agendamento mais próximo (apenas ele recebe a tag PRÓXIMA)
const nextAppointmentId = computed(() => {
  const upcoming = filteredAppointments.value.filter(a => a.is_upcoming);
  return upcoming.length > 0 ? upcoming[0].id : null;
});

const aptKPIs = computed(() => {
  const list = appointments.value || [];
  return {
    total: list.length,
    done: list.filter(a => a.status === 'done').length,
    upcoming: list.filter(a => a.is_upcoming).length,
    noShows: list.filter(a => a.status === 'no_show').length,
  };
});

// Recall banner dismiss state – reads from patient API record
const recallDismissedForever = ref(false);
const recallDismissedSession = ref(false);

// Recall banner: show if any no_show without recall_sent exists AND not dismissed
const pendingRecallAppointment = computed(() => {
  if (recallDismissedForever.value || recallDismissedSession.value) return null;
  return (
    (appointments.value || []).find(
      a => a.status === 'no_show' && !a.recall_sent
    ) || null
  );
});

const dismissRecallForever = async () => {
  recallDismissedForever.value = true;
  try {
    await PatientsAPI.update(route.params.patientId, {
      recall_dismissed_at: new Date().toISOString(),
    });
  } catch (e) {
    // UI already dismissed — best effort
  }
};

const dismissRecallSession = () => {
  recallDismissedSession.value = true;
};

const issuesCount = computed(
  () =>
    (appointments.value || []).filter(a =>
      ['no_show', 'canceled', 'rescheduled'].includes(a.status)
    ).length
);

const fetchAppointments = async () => {
  try {
    appointmentsLoading.value = true;
    const { data } = await PatientAppointmentsAPI.get(route.params.patientId);
    // API returns { appointments: [...], meta: {...} }
    appointments.value =
      data?.appointments || data?.data || (Array.isArray(data) ? data : []);
  } catch (error) {
    useAlert('Erro ao carregar agenda do paciente.');
  } finally {
    appointmentsLoading.value = false;
  }
};

// Modal: Reagendar
const showRescheduleModal = ref(false);
const rescheduleLoading = ref(false);
const rescheduleTargetId = ref(null);
const rescheduleForm = ref({
  new_scheduled_at: '',
  duration_minutes: 60,
  reschedule_reason: '',
});

const openRescheduleModal = apt => {
  rescheduleTargetId.value = apt.id;
  // Pre-fill with current appointment time + 1 week as suggestion
  const d = new Date(apt.scheduled_at);
  d.setDate(d.getDate() + 7);
  const iso = d.toISOString().slice(0, 16);
  rescheduleForm.value = {
    new_scheduled_at: iso,
    duration_minutes: apt.duration_minutes || 60,
    reschedule_reason: '',
  };
  showRescheduleModal.value = true;
};

const handleReschedule = async () => {
  if (!rescheduleForm.value.new_scheduled_at) {
    useAlert('Selecione uma data e hora para o reagendamento.');
    return;
  }
  try {
    rescheduleLoading.value = true;
    await PatientAppointmentsAPI.reschedule(
      route.params.patientId,
      rescheduleTargetId.value,
      {
        new_scheduled_at: rescheduleForm.value.new_scheduled_at,
        duration_minutes: rescheduleForm.value.duration_minutes,
        reschedule_reason: rescheduleForm.value.reschedule_reason,
      }
    );
    showRescheduleModal.value = false;
    useAlert('Consulta reagendada com sucesso!');
    await fetchAppointments();
  } catch (error) {
    useAlert('Erro ao reagendar consulta.');
  } finally {
    rescheduleLoading.value = false;
  }
};

// Modal: Confirmar Falta
const showNoShowModal = ref(false);
const noShowTargetId = ref(null);
const noShowLoading = ref(false);

const openNoShowModal = apt => {
  noShowTargetId.value = apt.id;
  showNoShowModal.value = true;
};

const handleNoShow = async () => {
  try {
    noShowLoading.value = true;
    await PatientAppointmentsAPI.markNoShow(
      route.params.patientId,
      noShowTargetId.value
    );
    showNoShowModal.value = false;
    useAlert('Falta registrada com sucesso.');
    await fetchAppointments();
  } catch (error) {
    useAlert('Erro ao registrar falta.');
  } finally {
    noShowLoading.value = false;
  }
};

// Send recall (WhatsApp)
const recallLoading = ref(false);
const sendRecallWhatsApp = async aptId => {
  try {
    recallLoading.value = true;
    if (aptId) {
      // Mark the specific appointment recall
      await PatientAppointmentsAPI.sendRecall(route.params.patientId);
    } else {
      await PatientAppointmentsAPI.sendRecall(route.params.patientId);
    }
    useAlert('Lembrete de retorno enviado via WhatsApp!');
    await fetchAppointments();
  } catch (error) {
    // Fallback: open WhatsApp directly if API not configured
    const phone = patient.value?.phone_number || patient.value?.phone;
    if (phone) {
      const clean = phone.replace(/\D/g, '');
      const msg = encodeURIComponent(
        `Olá${patient.value?.name ? ` ${patient.value.name}` : ''}! Notamos que você não compareceu à sua última consulta. Gostaríamos de reagendar para um horário conveniente para você. 😊`
      );
      window.open(`https://wa.me/${clean}?text=${msg}`, '_blank');
    } else {
      useAlert('Lembrete enviado!');
    }
  } finally {
    recallLoading.value = false;
  }
};

const openRescheduleFromRecall = apt => {
  if (apt) openRescheduleModal(apt);
  else navigateToAgendaWithPatient();
};

const navigateToAgendaWithPatient = () => {
  const pid = route.params.patientId;
  const p = patient.value;
  router.push({
    path: '/app/accounts/' + route.params.accountId + '/agenda',
    query: {
      newEvent: '1',
      contactId: p?.contact_id || '',
      patientName: p?.name || '',
      patientPhone: p?.phone_number || p?.phone || '',
      patientId: pid,
    },
  });
};

const TIMELINE_TYPE_CONFIG = {
  cadastro: { icon: 'i-lucide-user-plus', color: 'indigo', label: 'Cadastro' },
  anamnesis_filled: {
    icon: 'i-lucide-clipboard-list',
    color: 'blue',
    label: 'Anamnese',
  },
  appointment_scheduled: {
    icon: 'i-lucide-calendar-plus',
    color: 'orange',
    label: 'Agendamento',
  },
  appointment_rescheduled: {
    icon: 'i-lucide-calendar-clock',
    color: 'yellow',
    label: 'Reagendamento',
  },
  appointment_done: {
    icon: 'i-lucide-calendar-check',
    color: 'emerald',
    label: 'Consulta Realizada',
  },
  appointment_no_show: {
    icon: 'i-lucide-user-x',
    color: 'red',
    label: 'Falta',
  },
  appointment_canceled: {
    icon: 'i-lucide-calendar-x',
    color: 'rose',
    label: 'Cancelamento',
  },
  clinical_note: {
    icon: 'i-lucide-stethoscope',
    color: 'cyan',
    label: 'Evolução Clínica',
  },
  session_performed: {
    icon: 'i-lucide-activity',
    color: 'teal',
    label: 'Sessão Realizada',
  },
  exam_uploaded: {
    icon: 'i-lucide-image',
    color: 'violet',
    label: 'Exame/Imagem',
  },
  document_generated: {
    icon: 'i-lucide-file-text',
    color: 'sky',
    label: 'Documento',
  },
  consent_signed: {
    icon: 'i-lucide-file-signature',
    color: 'purple',
    label: 'Consentimento',
  },
  payment: {
    icon: 'i-lucide-circle-dollar-sign',
    color: 'green',
    label: 'Pagamento',
  },
  refund: { icon: 'i-lucide-receipt', color: 'amber', label: 'Reembolso' },
  status_changed: {
    icon: 'i-lucide-refresh-cw',
    color: 'slate',
    label: 'Status Alterado',
  },
  discharge: { icon: 'i-lucide-log-out', color: 'lime', label: 'Alta Médica' },
  recall_sent: {
    icon: 'i-lucide-bell',
    color: 'yellow',
    label: 'Recall Enviado',
  },
};

const TIMELINE_COLOR_CLASSES = {
  // fundo: muito escuro com leve tint | borda: 1px sutil | ícone: tom pastel médio
  indigo: {
    style: 'background:#16183a; box-shadow:0 0 0 1px #4f52a0; color:#a5b4fc',
    badge: 'background:#1e2047; color:#a5b4fc',
  },
  blue: {
    style: 'background:#0f1f35; box-shadow:0 0 0 1px #3b6ea8; color:#93c5fd',
    badge: 'background:#132440; color:#93c5fd',
  },
  orange: {
    style: 'background:#1e120a; box-shadow:0 0 0 1px #8b5a2b; color:#fdba74',
    badge: 'background:#241508; color:#fdba74',
  },
  yellow: {
    style: 'background:#1b1506; box-shadow:0 0 0 1px #7c6516; color:#fde68a',
    badge: 'background:#201a08; color:#fde68a',
  },
  emerald: {
    style: 'background:#0a1f18; box-shadow:0 0 0 1px #276c52; color:#6ee7b7',
    badge: 'background:#0c2219; color:#6ee7b7',
  },
  red: {
    style: 'background:#1e0d0d; box-shadow:0 0 0 1px #7f2020; color:#fca5a5',
    badge: 'background:#220f0f; color:#fca5a5',
  },
  rose: {
    style: 'background:#1e0d13; box-shadow:0 0 0 1px #7f2040; color:#fda4af',
    badge: 'background:#220f16; color:#fda4af',
  },
  cyan: {
    style: 'background:#0a1e25; box-shadow:0 0 0 1px #1e6e7e; color:#67e8f9',
    badge: 'background:#0c2229; color:#67e8f9',
  },
  teal: {
    style: 'background:#0a1e1d; box-shadow:0 0 0 1px #1e6e68; color:#5eead4',
    badge: 'background:#0c2221; color:#5eead4',
  },
  violet: {
    style: 'background:#140e25; box-shadow:0 0 0 1px #5837a0; color:#c4b5fd',
    badge: 'background:#170f2a; color:#c4b5fd',
  },
  sky: {
    style: 'background:#0b1c2c; box-shadow:0 0 0 1px #1e5f8c; color:#7dd3fc',
    badge: 'background:#0d2033; color:#7dd3fc',
  },
  purple: {
    style: 'background:#180d2a; box-shadow:0 0 0 1px #6a2e9e; color:#d8b4fe',
    badge: 'background:#1b0e2f; color:#d8b4fe',
  },
  green: {
    style: 'background:#0c1e12; box-shadow:0 0 0 1px #235c34; color:#86efac',
    badge: 'background:#0e2215; color:#86efac',
  },
  amber: {
    style: 'background:#1c1106; box-shadow:0 0 0 1px #7c4e12; color:#fcd34d',
    badge: 'background:#211308; color:#fcd34d',
  },
  slate: {
    style: 'background:#141820; box-shadow:0 0 0 1px #3a4455; color:#94a3b8',
    badge: 'background:#171c25; color:#94a3b8',
  },
  lime: {
    style: 'background:#111a06; box-shadow:0 0 0 1px #4a6a14; color:#bef264',
    badge: 'background:#131e07; color:#bef264',
  },
};

const timelineEventConfig = eventType =>
  TIMELINE_TYPE_CONFIG[eventType] ?? {
    icon: 'i-lucide-activity',
    color: 'slate',
    label: eventType,
  };
const timelineIconStyle = eventType =>
  TIMELINE_COLOR_CLASSES[timelineEventConfig(eventType).color]?.style ??
  TIMELINE_COLOR_CLASSES.slate.style;
const timelineBadgeStyle = eventType =>
  TIMELINE_COLOR_CLASSES[timelineEventConfig(eventType).color]?.badge ??
  TIMELINE_COLOR_CLASSES.slate.badge;

// CSS-class-based helpers for the new tl-* design system
const tlIconCls = eventType =>
  `tl-icon--${timelineEventConfig(eventType).color}`;
const tlBadgeCls = eventType =>
  `tl-badge--${timelineEventConfig(eventType).color}`;

const filteredTimelineEvents = computed(() => {
  let events =
    timelineFilter.value === 'all'
      ? timelineEvents.value
      : timelineEvents.value.filter(e => {
          if (timelineFilter.value === 'clinical')
            return [
              'clinical_note',
              'anamnesis_filled',
              'session_performed',
            ].includes(e.event_type);
          if (timelineFilter.value === 'appointments')
            return e.event_type.startsWith('appointment');
          if (timelineFilter.value === 'financial')
            return ['payment', 'refund'].includes(e.event_type);
          if (timelineFilter.value === 'documents')
            return [
              'document_generated',
              'consent_signed',
              'exam_uploaded',
            ].includes(e.event_type);
          return true;
        });
  return [...events].sort((a, b) => {
    const da = new Date(a.occurred_at || 0);
    const db = new Date(b.occurred_at || 0);
    return timelineSortOrder.value === 'oldest' ? da - db : db - da;
  });
});

const groupedTimelineEvents = computed(() => {
  const groups = {};
  filteredTimelineEvents.value.forEach(event => {
    const date = event.occurred_at
      ? new Date(event.occurred_at).toLocaleDateString('pt-BR', {
          year: 'numeric',
          month: 'long',
          day: 'numeric',
          timeZone: BRT,
        })
      : 'Sem data';
    if (!groups[date]) groups[date] = [];
    groups[date].push(event);
  });
  return Object.entries(groups).map(([date, events]) => ({ date, events }));
});

const fetchTimeline = async () => {
  try {
    timelineLoading.value = true;
    const response = await PatientTimelineAPI.get(route.params.patientId);
    timelineEvents.value = Array.isArray(response.data?.events)
      ? response.data.events
      : [];
  } catch {
    useAlert('Erro ao carregar a timeline do paciente.');
  } finally {
    timelineLoading.value = false;
  }
};

const fetchAgendaServices = async () => {
  try {
    const { data } = await AgendaServicesAPI.get();
    agendaServices.value = data;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Erro ao buscar serviços:', error);
  }
};

// ── Audit Log actions ────────────────────────────────────────
const fetchAuditLogs = async () => {
  try {
    isAuditLoading.value = true;
    const params = {
      page: auditFilters.value.page,
      per_page: 15,
    };
    if (auditFilters.value.action_type)
      params.action_type = auditFilters.value.action_type;
    if (auditFilters.value.actor_id)
      params.actor_id = auditFilters.value.actor_id;
    if (auditFilters.value.start_date)
      params.start_date = auditFilters.value.start_date;
    if (auditFilters.value.end_date)
      params.end_date = auditFilters.value.end_date;

    const response = await AuditLogsAPI.get(route.params.patientId, params);
    auditLogs.value = response.data?.audit_logs || [];
    auditMeta.value = response.data?.meta || {
      total_count: 0,
      current_page: 1,
      total_pages: 1,
    };
  } catch (error) {
    useAlert('Erro ao carregar logs de auditoria.');
  } finally {
    isAuditLoading.value = false;
  }
};

const applyAuditFilters = () => {
  auditFilters.value.page = 1;
  fetchAuditLogs();
};

const clearAuditFilters = () => {
  auditFilters.value = {
    action_type: '',
    actor_id: '',
    start_date: '',
    end_date: '',
    page: 1,
  };
  fetchAuditLogs();
};

const auditPagePrev = () => {
  if (auditFilters.value.page > 1) {
    auditFilters.value.page -= 1;
    fetchAuditLogs();
  }
};

const auditPageNext = () => {
  if (auditFilters.value.page < auditMeta.value.total_pages) {
    auditFilters.value.page += 1;
    fetchAuditLogs();
  }
};

const exportPdf = async () => {
  try {
    isExportingPdf.value = true;
    const patientId = route.params.patientId;
    const response = await AuditLogsAPI.export(patientId);
    const blob = new Blob([response.data], { type: 'application/pdf' });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    const name = patient.value.name?.replace(/\s+/g, '_') || 'paciente';
    link.href = url;
    link.setAttribute('download', `prontuario_${name}_${patientId}.pdf`);
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(url);
    useAlert('Prontuário exportado com sucesso!');
  } catch (error) {
    useAlert('Erro ao exportar o prontuário. Verifique suas permissões.');
  } finally {
    isExportingPdf.value = false;
  }
};

const formatAuditAction = action => {
  const map = {
    view: {
      label: 'VISUALIZAÇÃO',
      color: 'bg-slate-700/50 text-slate-300 border-slate-600/50',
      icon: 'i-lucide-eye',
    },
    create: {
      label: 'CRIAÇÃO',
      color: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
      icon: 'i-lucide-plus',
    },
    update: {
      label: 'EDIÇÃO',
      color: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
      icon: 'i-lucide-edit-2',
    },
    delete: {
      label: 'EXCLUSÃO',
      color: 'bg-red-500/10 text-red-400 border-red-500/20',
      icon: 'i-lucide-trash-2',
    },
    sign: {
      label: 'ASSINATURA',
      color: 'bg-violet-500/10 text-violet-400 border-violet-500/20',
      icon: 'i-lucide-pen-tool',
    },
    export: {
      label: 'EXPORTAÇÃO',
      color: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
      icon: 'i-lucide-download',
    },
    finalize: {
      label: 'FINALIZAÇÃO',
      color: 'bg-indigo-500/10 text-indigo-400 border-indigo-500/20',
      icon: 'i-lucide-check-circle',
    },
    approve: {
      label: 'APROVAÇÃO',
      color: 'bg-teal-500/10 text-teal-400 border-teal-500/20',
      icon: 'i-lucide-thumbs-up',
    },
    pay: {
      label: 'PAGAMENTO',
      color: 'bg-green-500/10 text-green-400 border-green-500/20',
      icon: 'i-lucide-circle-dollar-sign',
    },
    print: {
      label: 'IMPRESSÃO',
      color: 'bg-cyan-500/10 text-cyan-400 border-cyan-500/20',
      icon: 'i-lucide-printer',
    },
  };
  return (
    map[action] || {
      label: (action || 'AÇÃO').toUpperCase(),
      color: 'bg-slate-700/50 text-slate-300 border-slate-600/50',
      icon: 'i-lucide-activity',
    }
  );
};

const generateDetailedAuditText = log => {
  const actor = log.actor_name ? `O usuário ${log.actor_name}` : 'O sistema';

  const resourceNames = {
    Anamnesis: 'Anamnese',
    TreatmentPlan: 'Plano de Tratamento',
    TreatmentItem: 'Procedimento',
    ClinicalNote: 'Evolução/Nota Clínica',
    FinancialEstimate: 'Orçamento',
    Transaction: 'Transação Financeira',
    Patient: 'Cadastro do Paciente',
    ExamMedia: 'Exame/Mídia',
    Document: 'Documento',
    ConsentRecord: 'Consentimento',
    SessionLog: 'Sessão de Procedimento',
    Recall: 'Recall',
    CriticalAlert: 'Alerta Crítico',
  };

  const resourceName =
    resourceNames[log.resource_type] || log.resource_type || 'Prontuário';

  switch (log.action) {
    case 'view':
      return `${actor} acessou e visualizou os dados de ${resourceName}.`;
    case 'create':
      return `${actor} criou um novo registro em ${resourceName}.`;
    case 'update':
      return `${actor} editou e alterou informações em ${resourceName}.`;
    case 'delete':
      return `${actor} excluiu o registro de ${resourceName}.`;
    case 'sign':
      return `${actor} assinou o ${resourceName}.`;
    case 'finalize':
      return `${actor} assinou e finalizou o registro de ${resourceName}. O documento tornou-se imutável.`;
    case 'approve':
      return `${actor} aprovou o ${resourceName}.`;
    case 'export':
      return `${actor} exportou o arquivo PDF de ${resourceName}.`;
    case 'pay':
      return `${actor} registrou pagamento em ${resourceName}.`;
    case 'print':
      return `${actor} emitiu impressão/receita para ${resourceName}.`;
    default:
      return `${actor} executou a ação: ${log.action} em ${resourceName}.`;
  }
};

const formatAuditDateTime = isoStr => {
  if (!isoStr) return '—';
  const d = new Date(isoStr);
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: BRT,
  });
};

const handleStatusChange = async event => {
  const newStatus = event.target.value;
  const oldStatus = patient.value.patient_status;
  try {
    patient.value.patient_status = newStatus; // optimistic update
    await PatientsAPI.updateStatus(route.params.patientId, newStatus);
  } catch (error) {
    // revert on error
    patient.value.patient_status = oldStatus;
  }
};

// --- AVATAR E MÉTODOS DE CÂMERA ---

const triggerAvatarUpload = () => {
  avatarInputRef.value?.click();
};

const processImageToWebP = (fileOrBlob, targetSize = 300) => {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(fileOrBlob);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      const canvas = document.createElement('canvas');
      const size = Math.min(img.width, img.height);
      const startX = (img.width - size) / 2;
      const startY = (img.height - size) / 2;

      canvas.width = targetSize;
      canvas.height = targetSize;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(
        img,
        startX,
        startY,
        size,
        size,
        0,
        0,
        targetSize,
        targetSize
      );

      canvas.toBlob(
        blob => {
          resolve(
            new File([blob], `avatar_${Date.now()}.webp`, {
              type: 'image/webp',
            })
          );
        },
        'image/webp',
        0.8
      );
    };
    img.onerror = reject;
    img.src = url;
  });
};

const handleAvatarUpload = async event => {
  const file = event.target.files[0];
  if (!file) return;

  try {
    isLoading.value = true;
    const processedFile = await processImageToWebP(file, 300);
    const { data } = await PatientsAPI.updateAvatar(
      route.params.patientId,
      processedFile
    );
    patient.value.avatar_url =
      data.payload?.avatar_url || data.avatar_url || '';
    useAlert('Foto atualizada com sucesso!');
  } catch (error) {
    useAlert('Erro ao atualizar foto.');
  } finally {
    isLoading.value = false;
    if (avatarInputRef.value) avatarInputRef.value.value = '';
  }
};

const startCamera = async () => {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user' },
    });
    cameraStream.value = stream;
    if (videoElement.value) {
      videoElement.value.srcObject = stream;
      videoElement.value.play().catch(
        (
          e // eslint-disable-next-line no-console
        ) => console.error('Error playing video:', e)
      );
    }
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('Error accessing camera:', err);
    cameraError.value = true;
  }
};

const stopCamera = () => {
  if (cameraStream.value) {
    cameraStream.value.getTracks().forEach(track => track.stop());
    cameraStream.value = null;
  }
};

const openCameraModal = async () => {
  showCameraModal.value = true;
  cameraError.value = false;
  capturedPhoto.value = null;
  await nextTick();
  startCamera();
};

const closeCameraModal = () => {
  stopCamera();
  showCameraModal.value = false;
  capturedPhoto.value = null;
};

const capturePhoto = () => {
  if (!videoElement.value || !canvasElement.value) return;
  const video = videoElement.value;
  const canvas = canvasElement.value;

  const size = Math.min(video.videoWidth, video.videoHeight);
  const startX = (video.videoWidth - size) / 2;
  const startY = (video.videoHeight - size) / 2;

  const targetSize = 300;
  canvas.width = targetSize;
  canvas.height = targetSize;
  const ctx = canvas.getContext('2d');

  // A classe .cam-video já espelha o preview para o usuário.
  // Ao desenhar o vídeo original aqui e mostrá-lo em uma img sem scaleX(-1),
  // o usuário terá a foto exata (espelhada/selfie) que acabou de ver.

  ctx.drawImage(
    video,
    startX,
    startY,
    size,
    size,
    0,
    0,
    targetSize,
    targetSize
  );
  capturedPhoto.value = canvas.toDataURL('image/webp', 0.8);
};

const retakePhoto = () => {
  capturedPhoto.value = null;
};

const useCapturedPhoto = async () => {
  if (!capturedPhoto.value) return;

  try {
    isLoading.value = true;

    // Convert base64 to Blob
    const res = await fetch(capturedPhoto.value);
    const blob = await res.blob();
    const file = new File([blob], `avatar_${Date.now()}.webp`, {
      type: 'image/webp',
    });

    const { data } = await PatientsAPI.updateAvatar(
      route.params.patientId,
      file
    );
    patient.value.avatar_url =
      data.payload?.avatar_url || data.avatar_url || '';

    useAlert('Foto de perfil atualizada!');
    closeCameraModal();
  } catch (error) {
    useAlert('Erro ao salvar foto.');
  } finally {
    isLoading.value = false;
  }
};

const editFirstName = ref('');
const editLastName = ref('');

// Seções colapsáveis do cadastro — todas abertas por padrão
const regSections = ref({
  personal: true,
  contact: true,
  address: false,
  admin: false,
});

const toggleRegSection = section => {
  regSections.value[section] = !regSections.value[section];
};

const registrationCompleteness = computed(() => {
  if (!patient.value) return 0;
  const p = patient.value;
  const fields = [
    p.name,
    p.birthdate,
    p.sex,
    p.cpf,
    p.phone,
    p.email,
    p.address?.zip_code,
    p.address?.city,
    p.address?.state,
    p.emergency_contact?.name,
    p.emergency_contact?.phone,
  ];
  const filled = fields.filter(Boolean).length;
  return Math.round((filled / fields.length) * 100);
});

const saveRegistration = async () => {
  try {
    isLoading.value = true;
    // Join first + last name before saving
    patient.value.name = `${editFirstName.value} ${editLastName.value}`.trim();
    const payload = {
      name: patient.value.name,
      cpf: patient.value.cpf
        ? String(patient.value.cpf).replace(/\D/g, '')
        : '',
      rg: patient.value.rg
        ? String(patient.value.rg)
            .replace(/[^a-zA-Z0-9]/g, '')
            .toUpperCase()
        : '',
      birthdate: patient.value.birthdate,
      sex: patient.value.sex,
      marital_status: patient.value.marital_status,
      phone: patient.value.phone
        ? '+55' +
          String(patient.value.phone).replace(/\D/g, '').replace(/^55/, '')
        : '',
      email: patient.value.email,
      address: patient.value.address,
      emergency_contact: patient.value.emergency_contact,
      insurance: patient.value.insurance,
      communication_opt_ins: patient.value.communication_opt_ins,
      lgpd_consent: patient.value.lgpd_consent,
      contact_id: patient.value.contact_id,
    };
    await PatientsAPI.update(route.params.patientId, payload);
    await fetchPatientSummary(); // Refetches state to trigger Age calculation
    useAlert('Cadastro atualizado com sucesso!');
    fetchChangeHistory(); // atualiza historico se a aba estiver aberta
  } catch (error) {
    useAlert('Erro ao atualizar cadastro.');
  } finally {
    isLoading.value = false;
  }
};

const handleCpfInput = event => {
  let value = event.target.value.replace(/\D/g, '');
  if (value.length > 11) value = value.slice(0, 11);
  if (value.length > 9) {
    value = value.replace(/(\d{3})(\d{3})(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
  } else if (value.length > 6) {
    value = value.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
  } else if (value.length > 3) {
    value = value.replace(/(\d{3})(\d{1,3})/, '$1.$2');
  }
  patient.value.cpf = value;
  event.target.value = value;
};

const handleRgInput = event => {
  let value = event.target.value.replace(/[^a-zA-Z0-9]/g, '');
  if (value.length > 9) value = value.slice(0, 9);

  if (value.length > 8) {
    value = value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3-$4'
    );
  } else if (value.length > 5) {
    value = value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3'
    );
  } else if (value.length > 2) {
    value = value.replace(/^([a-zA-Z0-9]{2})([a-zA-Z0-9]{1,})/, '$1.$2');
  }

  value = value.toUpperCase();
  patient.value.rg = value;
  event.target.value = value;
};

// ── Busca de contato por telefone (aba Cadastro) ─────────────────────────────
const phoneContactResults = ref([]);
const phoneContactSearching = ref(false);
const phoneContactDropdown = ref(false);
const phoneContactSkipSearch = ref(false);
let phoneContactTimeout = null;

const handlePhoneInput = event => {
  let value = event.target.value.replace(/\D/g, '');
  if (value.startsWith('55')) value = value.slice(2);
  if (value.length > 11) value = value.slice(0, 11);

  if (value.length > 10) {
    value = value.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  } else if (value.length > 6) {
    value = value.replace(/(\d{2})(\d{4,5})(\d{0,4})/, '($1) $2-$3');
  } else if (value.length > 2) {
    value = value.replace(/(\d{2})(\d{0,5})/, '($1) $2');
  } else if (value.length > 0) {
    value = value.replace(/(\d{0,2})/, '($1');
  }

  if (value) {
    patient.value.phone = '+55' + value.replace(/\D/g, '');
  } else {
    patient.value.phone = '';
  }

  // For visual binding of the input itself
  event.target.value = value;

  // Busca de contatos pelo número digitado
  if (phoneContactSkipSearch.value) {
    phoneContactSkipSearch.value = false;
    return;
  }
  clearTimeout(phoneContactTimeout);
  const rawDigits = value.replace(/\D/g, '');
  if (!rawDigits || rawDigits.length < 2) {
    phoneContactResults.value = [];
    phoneContactDropdown.value = false;
    return;
  }
  phoneContactDropdown.value = true;
  phoneContactSearching.value = true;
  phoneContactTimeout = setTimeout(async () => {
    try {
      const resp = await ContactAPI.search(rawDigits);
      phoneContactResults.value = resp.data?.payload || [];
    } catch {
      phoneContactResults.value = [];
    } finally {
      phoneContactSearching.value = false;
    }
  }, 400);
};

const selectPhoneContact = contact => {
  phoneContactSkipSearch.value = true;
  patient.value.contact_id = contact.id;
  let digits = String(contact.phone_number || '').replace(/\D/g, '');
  if (digits.startsWith('55')) digits = digits.slice(2);
  patient.value.phone = '+55' + digits;
  if (contact.email && !patient.value.email)
    patient.value.email = contact.email;
  phoneContactDropdown.value = false;
  phoneContactResults.value = [];
};

const phoneContactColor = name => {
  const colors = [
    '#6366f1',
    '#8b5cf6',
    '#ec4899',
    '#f43f5e',
    '#f97316',
    '#22c55e',
    '#14b8a6',
    '#3b82f6',
  ];
  if (!name) return colors[0];
  let h = 0;
  for (let i = 0; i < name.length; i += 1)
    h = name.charCodeAt(i) + (h * 32 - h);
  return colors[Math.abs(h) % colors.length];
};

const handleAlternativePhoneInput = event => {
  let value = event.target.value.replace(/\D/g, '');
  if (value.startsWith('55')) value = value.slice(2);
  if (value.length > 11) value = value.slice(0, 11);

  if (value.length > 10) {
    value = value.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  } else if (value.length > 6) {
    value = value.replace(/(\d{2})(\d{4,5})(\d{0,4})/, '($1) $2-$3');
  } else if (value.length > 2) {
    value = value.replace(/(\d{2})(\d{0,5})/, '($1) $2');
  } else if (value.length > 0) {
    value = value.replace(/(\d{0,2})/, '($1');
  }

  if (!patient.value.emergency_contact) {
    patient.value.emergency_contact = {};
  }

  if (value) {
    patient.value.emergency_contact.phone = '+55' + value.replace(/\D/g, '');
  } else {
    patient.value.emergency_contact.phone = '';
  }

  event.target.value = value;
};

// Formatter to render DB phone on screen securely
const formatPhoneDisplay = phoneStr => {
  if (!phoneStr) return '';
  let val = String(phoneStr).replace(/\D/g, '');
  if (val.startsWith('55')) val = val.slice(2);
  if (val.length === 11) {
    return val.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  }
  if (val.length === 10) {
    return val.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
  }
  return phoneStr;
};

const formatCpfDisplay = cpfStr => {
  if (!cpfStr) return '';
  let value = String(cpfStr).replace(/\D/g, '');
  if (value.length > 11) value = value.slice(0, 11);
  if (value.length > 9) {
    return value.replace(/(\d{3})(\d{3})(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
  }
  if (value.length > 6) {
    return value.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
  }
  if (value.length > 3) {
    return value.replace(/(\d{3})(\d{1,3})/, '$1.$2');
  }
  return value;
};

const formatRgDisplay = rgStr => {
  if (!rgStr) return '';
  let value = String(rgStr)
    .replace(/[^a-zA-Z0-9]/g, '')
    .toUpperCase();
  if (value.length > 9) value = value.slice(0, 9);
  if (value.length > 8) {
    return value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3-$4'
    );
  }
  if (value.length > 5) {
    return value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3'
    );
  }
  if (value.length > 2) {
    return value.replace(/^([a-zA-Z0-9]{2})([a-zA-Z0-9]{1,})/, '$1.$2');
  }
  return value;
};

const searchCep = async () => {
  const cep = patient.value.address?.zip_code?.replace(/\D/g, '');
  if (cep && cep.length === 8) {
    try {
      const resp = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
      const data = await resp.json();
      if (!data.erro) {
        if (!patient.value.address) patient.value.address = {};
        patient.value.address.street = data.logradouro;
        patient.value.address.neighborhood = data.bairro;
        patient.value.address.city = data.localidade;
        patient.value.address.state = data.uf;
      }
    } catch (e) {
      // do nothing or silent fallback
    }
  }
};

// --- AVATAR E CÂMERA ---
// variables moved to top block

// ── General Tab Computeds ────────────────────────────────────
const computedClinicalTags = computed(() => {
  const tags = [];
  // Critical alerts (already objects with .title/.message from API)
  (patient.value.critical_alerts || []).forEach(alert => {
    tags.push({
      type: 'danger',
      icon: 'i-lucide-triangle-alert',
      label: alert.title || alert.message,
    });
  });
  // Anamnesis-derived tags (all these arrays are objects {name} or strings - handle both)
  if (currentAnamnesis.value?.id) {
    const getString = v =>
      typeof v === 'object' && v !== null
        ? v.name || JSON.stringify(v)
        : String(v);
    (currentAnamnesis.value.allergies || []).forEach(a => {
      tags.push({
        type: 'warning',
        icon: 'i-lucide-zap',
        label: `Alergia: ${getString(a)}`,
      });
    });
    (currentAnamnesis.value.contraindications || []).forEach(c => {
      tags.push({ type: 'danger', icon: 'i-lucide-ban', label: getString(c) });
    });
    const mh = currentAnamnesis.value.medical_history || {};
    if (mh.diabetes)
      tags.push({
        type: 'warning',
        icon: 'i-lucide-activity',
        label: 'Diabético(a)',
      });
    if (mh.hypertension)
      tags.push({
        type: 'warning',
        icon: 'i-lucide-heart-pulse',
        label: 'Hipertenso(a)',
      });
    if (mh.bleeding_disorder)
      tags.push({
        type: 'danger',
        icon: 'i-lucide-droplets',
        label: 'Distúrbio de Coagulação',
      });
    if (mh.cardiac_problems)
      tags.push({
        type: 'danger',
        icon: 'i-lucide-heart-crack',
        label: 'Cardiopatia',
      });
    if (mh.pregnancy)
      tags.push({ type: 'warning', icon: 'i-lucide-baby', label: 'Grávida' });
    if (mh.has_implants)
      tags.push({ type: 'info', icon: 'i-lucide-cpu', label: 'Implante' });
    (currentAnamnesis.value.current_medications || [])
      .slice(0, 3)
      .forEach(m => {
        tags.push({
          type: 'info',
          icon: 'i-lucide-pill',
          label: `Med: ${getString(m)}`,
        });
      });
  }
  return tags;
});

const activePlanSummary = computed(() => {
  if (!treatmentPlans.value?.length) return null;
  const found = treatmentPlans.value.find(
    p => p.status === 'in_progress' || p.status === 'approved'
  );
  return found || treatmentPlans.value[0] || null;
});

const responsibleProfName = computed(() => {
  const profId = patient.value.responsible_professional_id;
  if (profId) {
    const agents = store.getters['agents/getAgents'] || [];
    const agent = agents.find(a => a.id === profId);
    if (agent) return agent.name;
  }
  return currentUser.value?.name || '—';
});

const lastAppointmentFormatted = computed(() => {
  const appt = patient.value.last_appointment;
  if (!appt?.start_time) return null;
  return {
    date: new Date(appt.start_time).toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      timeZone: BRT,
    }),
    time: new Date(appt.start_time).toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: BRT,
    }),
    title: appt.title || 'Consulta',
  };
});

const nextAppointmentFormatted = computed(() => {
  const appt = patient.value.next_appointment;
  if (!appt?.start_time) return null;
  return {
    date: new Date(appt.start_time).toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      timeZone: BRT,
    }),
    time: new Date(appt.start_time).toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: BRT,
    }),
    title: appt.title || 'Consulta',
  };
});

onMounted(() => {
  fetchPatientSummary();
  fetchChangeHistory();
  fetchAgendaServices();
  loadFolderData(route.params.patientId);
  // Pre-load critical data for the General tab
  fetchAnamneses();
  fetchTreatmentPlans();
  store.dispatch('agents/get');
  loadBankAccountsForPay();

  // Abre a aba indicada pelo query param ao voltar da Agenda
  if (route.query.tab) {
    activeTab.value = route.query.tab;
  }

  // Garante persistência de pastas/locks mesmo se o usuário fechar a aba
  // antes do debounce de saveFolderData expirar.
  window.addEventListener('beforeunload', handleFolderBeforeUnload);
});

onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', handleFolderBeforeUnload);
  // flush síncrono ao desmontar o componente (navegação SPA para outra rota)
  if (route.params.patientId) flushFolderData(route.params.patientId);
});

watch(activeTab, newVal => {
  // persiste a aba ativa na URL para sobreviver a F5
  if (route.query.tab !== newVal) {
    router.replace({ query: { ...route.query, tab: newVal } }).catch(() => {});
  }
  if (newVal === 'audit') {
    fetchAuditLogs();
  } else if (newVal === 'anamnesis') {
    fetchAnamneses();
  } else if (newVal === 'exams') {
    fetchExamMedias();
  } else if (newVal === 'documents') {
    fetchDocuments();
  } else if (newVal === 'consents') {
    fetchConsents();
  } else if (newVal === 'treatment_plan') {
    fetchTreatmentPlans();
  } else if (newVal === 'procedures') {
    fetchSessionLogs();
  } else if (newVal === 'financial') {
    fetchFinancialData();
  } else if (newVal === 'timeline') {
    fetchTimeline();
  } else if (newVal === 'evolution') {
    fetchClinicalNotes();
  } else if (newVal === 'schedule') {
    fetchAppointments();
  }
});

watch(
  () => route.params.patientId,
  (newId, oldId) => {
    if (!newId || newId === oldId) return;
    anamneses.value = [];
    applyAnamnesisState(null);
    allergyInput.value = '';
    medicationInput.value = '';
    if (activeTab.value === 'anamnesis') fetchAnamneses();
  }
);

watch(
  () => patient.value.address?.zip_code,
  newVal => {
    if (newVal) {
      let value = String(newVal).replace(/\D/g, '');
      if (value.length > 8) value = value.slice(0, 8);

      let formatted = value;
      if (value.length > 5) {
        formatted = value.replace(/(\d{5})(\d{1,3})/, '$1-$2');
      }

      if (newVal !== formatted) {
        if (!patient.value.address) patient.value.address = {};
        patient.value.address.zip_code = formatted;
        return; // will trigger watcher again
      }

      if (value.length === 8) {
        searchCep();
      }
    }
  }
);

// All tabs — filtered by RBAC permissions before rendering
const allTabs = [
  { id: 'general', label: 'Geral', icon: 'i-lucide-layout-dashboard' },
  { id: 'registration', label: 'Cadastro', icon: 'i-lucide-user' },
  { id: 'anamnesis', label: 'Anamnese', icon: 'i-lucide-clipboard-plus' },
  { id: 'evolution', label: 'Evolução', icon: 'i-lucide-trending-up' },
  {
    id: 'treatment_plan',
    label: 'Plano de Tratamento',
    icon: 'i-lucide-target',
  },
  {
    id: 'procedures',
    label: 'Procedimentos',
    icon: 'i-lucide-activity',
  },
  { id: 'exams', label: 'Exames e Imagens', icon: 'i-lucide-file-image' },
  { id: 'documents', label: 'Documentos', icon: 'i-lucide-file-text' },
  { id: 'consents', label: 'Consentimentos', icon: 'i-lucide-pen-tool' },
  {
    id: 'financial',
    label: 'Financeiro',
    icon: 'i-lucide-dollar-sign',
    permission: { module: 'financial', action: 'view_transactions' },
  },
  { id: 'schedule', label: 'Agenda e Histórico', icon: 'i-lucide-calendar' },
  { id: 'timeline', label: 'Timeline', icon: 'i-lucide-git-commit' },
  {
    id: 'audit',
    label: 'Auditoria',
    icon: 'i-lucide-shield-alert',
    permission: { module: 'patients', action: 'view_audit' },
  },
];

// Tabs visíveis para o usuário atual com base em permissões RBAC
const tabs = computed(() =>
  allTabs.filter(tab => {
    if (!tab.permission) return true;
    return can(tab.permission.module, tab.permission.action);
  })
);

const getInitials = name => {
  if (!name) return '';
  return name.charAt(0).toUpperCase();
};

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return new Date(dateStr).toLocaleDateString('pt-BR', { timeZone: BRT });
};

const formatSex = sex => {
  if (!sex) return '';
  const lower = sex.toLowerCase();
  if (lower === 'masculino') return 'Masculino';
  if (lower === 'feminino') return 'Feminino';
  return sex;
};

const hasValidSex = sex => {
  if (!sex) return false;
  const s = String(sex).toLowerCase().trim();
  return ![
    '',
    'não informado',
    'nao_informado',
    'não_informado',
    'null',
  ].includes(s);
};

const formatInsuranceStr = ins => {
  if (!ins) return null;
  let parsed = ins;
  if (typeof parsed === 'string') {
    if (
      parsed === '—' ||
      parsed === '{}' ||
      parsed === 'null' ||
      parsed.includes('"name":""') ||
      parsed.includes('"name": ""')
    ) {
      return null;
    }
    try {
      parsed = JSON.parse(parsed);
    } catch (e) {
      return parsed;
    }
  }
  if (parsed && typeof parsed === 'object') {
    if (!parsed.name) return null;
    return `${parsed.name}${parsed.plan ? ' - ' + parsed.plan : ''}`;
  }
  return String(parsed);
};

// ── Header Global Shortcuts ──────────────────────────────────
const handleHeaderSchedule = () => {
  router.push({
    name: 'agenda_dashboard_index',
    params: { accountId: route.params.accountId },
    query: {
      newEvent: '1',
      contactId: patient.value.contact_id || '',
      patientName: patient.value.name || '',
      patientPhone: patient.value.phone || '',
    },
  });
};

const handleHeaderCharge = () => {
  activeTab.value = 'financial';
};

const handleHeaderStartService = async () => {
  if (!patient.value.contact_id) {
    router.push({
      name: 'home',
      params: { accountId: route.params.accountId },
    });
    return;
  }
  try {
    const response = await ContactAPI.getConversations(
      patient.value.contact_id
    );
    const conversations = response.data?.payload || [];
    if (conversations.length > 0) {
      const sorted = [...conversations].sort((a, b) => b.id - a.id);
      router.push({
        name: 'inbox_conversation',
        params: {
          accountId: route.params.accountId,
          conversation_id: sorted[0].id,
        },
      });
    } else {
      router.push({
        name: 'home',
        params: { accountId: route.params.accountId },
      });
    }
  } catch (e) {
    router.push({
      name: 'home',
      params: { accountId: route.params.accountId },
    });
  }
};
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="record-container px-4 md:px-6 lg:px-8" :class="{ 'is-archived': patient.deleted_at }">
    <!-- Header com Voltar -->
    <div class="header-nav flex flex-row justify-between w-full gap-2 md:gap-4 items-center">
      <button class="btn-back !px-3 md:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 rounded-md shrink-0" @click="goBack" title="Voltar para pacientes">
        <i class="i-lucide-arrow-left" />
        <span class="hidden md:inline">Voltar para pacientes</span>
      </button>
      <div class="header-actions flex flex-row gap-1 sm:gap-2 w-auto overflow-x-auto pb-1 sm:pb-0 items-center">
        <button
          class="hdr-btn hdr-btn--secondary !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="handleHeaderSchedule"
          title="Agendar"
        >
          <i class="i-lucide-calendar-plus w-4 h-4 md:mr-1" />
          <span class="hidden lg:inline">Agendar</span>
        </button>
        <button
          class="hdr-btn hdr-btn--secondary !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="activeTab = 'exams'"
          title="Anexar arquivo"
        >
          <i class="i-lucide-paperclip w-4 h-4 md:mr-1" />
          <span class="hidden lg:inline">Anexar arquivo</span>
        </button>
        <button
          class="hdr-btn hdr-btn--secondary !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="activeTab = 'documents'"
          title="Gerar documento"
        >
          <i class="i-lucide-file-text w-4 h-4 md:mr-1" />
          <span class="hidden lg:inline">Gerar documento</span>
        </button>
        <div class="hdr-divider hidden sm:block shrink-0" />
        <button 
          class="hdr-btn hdr-btn--charge !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0" 
          @click="handleHeaderCharge"
          title="Cobrar"
        >
          <i class="i-lucide-dollar-sign w-4 h-4 md:mr-1" />
          <span class="hidden lg:inline">Cobrar</span>
        </button>
        <button
          class="hdr-btn hdr-btn--primary !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="handleHeaderStartService"
          title="Iniciar atendimento"
        >
          <i class="i-lucide-play w-3.5 h-3.5 md:mr-1" />
          <span class="hidden md:inline">Iniciar atendimento</span>
        </button>
      </div>
    </div>

    <!-- Banner: Paciente Arquivado -->
    <div v-if="patient.deleted_at" class="archived-banner">
      <div class="archived-banner-left">
        <i class="i-lucide-archive w-4 h-4" />
        <div>
          <p class="archived-banner-title">Paciente arquivado</p>
          <p class="archived-banner-sub">
            Arquivado em
            {{
              new Date(patient.deleted_at).toLocaleDateString('pt-BR', {
                timeZone: 'America/Sao_Paulo',
              })
            }}
            — apenas leitura
          </p>
        </div>
      </div>
      <button
        class="archived-banner-btn"
        title="Restaurar paciente"
        @click="
          () =>
            PatientsAPI.restore(patient.id).then(() => {
              patient.deleted_at = null;
              useAlert('Paciente restaurado com sucesso!');
            })
        "
      >
        <i class="i-lucide-archive-restore w-4 h-4" />
        Restaurar paciente
      </button>
    </div>

    <!-- Perfil do Paciente em Banner -->
    <div class="profile-banner">
      <!-- Esquerda: avatar + identidade -->
      <div class="profile-banner-left">
        <!-- Avatar com badge de status sobreposto -->
        <div class="pb-avatar-wrap">
          <img
            v-if="patient.avatar_url"
            :src="patient.avatar_url"
            alt="Avatar"
            class="pb-avatar-img"
          />
          <div v-else class="pb-avatar-placeholder">
            {{ getInitials(patient.name) }}
          </div>
          <!-- Status badge no canto inferior direito do avatar -->
          <span
            class="pb-status-dot"
            :class="'pb-dot-' + (patient.patient_status || 'novo')"
            :title="
              {
                novo: 'Novo',
                ativo: 'Ativo',
                inativo: 'Inativo',
                faltoso: 'Faltoso',
                alta: 'Alta',
                arquivado: 'Arquivado',
              }[patient.patient_status] || patient.patient_status
            "
          />
        </div>

        <!-- Identidade: nome + dados -->
        <div class="pb-identity">
          <div class="pb-name-row">
            <h2 class="pb-name">{{ patient.name }}</h2>
            <!-- Botão de alerta crítico (se houver) -->
            <div
              v-if="
                patient.critical_alerts && patient.critical_alerts.length > 0
              "
              class="critical-alert-container"
            >
              <button
                class="btn-critical-alert enhanced"
                title="Atenção Clínica"
                @click.stop="showCriticalAlert = !showCriticalAlert"
              >
                <i class="i-lucide-alert-circle" />
              </button>
              <div v-if="showCriticalAlert" class="critical-popup">
                <div class="popup-header">
                  <i class="i-lucide-alert-triangle" />
                  <span>Atenção Clínica</span>
                  <button
                    class="btn-close-popup"
                    @click="showCriticalAlert = false"
                  >
                    <i class="i-lucide-x" />
                  </button>
                </div>
                <div class="popup-body critical-popup-body">
                  <div
                    v-for="alert in patient.critical_alerts"
                    :key="alert.id"
                    class="alert-item"
                  >
                    <strong>{{ alert.severity }}:</strong> {{ alert.message }}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Linha de dados demográficos + status pill -->
          <div class="pb-meta-row">
            <span
v-if="patient.age" class="pb-meta-text"
              >{{ patient.age }} anos</span
            >
            <span
              v-if="patient.age && hasValidSex(patient.sex)"
              class="pb-meta-sep"
              >•</span
            >
            <span v-if="hasValidSex(patient.sex)" class="pb-meta-text">{{
              formatSex(patient.sex)
            }}</span>
            <span class="pb-meta-sep">·</span>
            <span
              class="pb-status-pill"
              :class="'pb-pill-' + (patient.patient_status || 'novo')"
            >
              {{
                {
                  novo: 'Novo',
                  ativo: 'Ativo',
                  inativo: 'Inativo',
                  faltoso: 'Faltoso',
                  alta: 'Alta',
                  arquivado: 'Arquivado',
                }[patient.patient_status] || patient.patient_status
              }}
            </span>
          </div>

          <!-- Chips de informações -->
          <div class="pb-chips">
            <div v-if="patient.birthdate" class="pb-chip">
              <i class="i-lucide-cake w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ formatDate(patient.birthdate) }}</span>
            </div>
            <div v-if="patient.phone" class="pb-chip">
              <i class="i-lucide-smartphone w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ patient.phone }}</span>
            </div>
            <div v-if="patient.email" class="pb-chip hide-mobile">
              <i class="i-lucide-mail w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ patient.email }}</span>
            </div>
            <div v-if="patient.cpf" class="pb-chip hide-mobile">
              <i class="i-lucide-credit-card w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ formatCpfDisplay(patient.cpf) }}</span>
            </div>
            <div v-if="formatInsuranceStr(patient.insurance)" class="pb-chip">
              <i class="i-lucide-shield-plus w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ formatInsuranceStr(patient.insurance) }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Direita: badge financeiro -->
      <div class="pb-right">
        <div
          class="pb-finance-badge"
          :class="'pb-finance-' + patient.financialStatus?.toLowerCase()"
        >
          <i class="i-lucide-wallet w-4 h-4" />
          <span>{{ patient.financialStatus }}</span>
        </div>
      </div>
    </div>

    <!-- Layout Base: Abas na Esquerda e Conteúdo na Direita -->
    <div class="record-layout grid grid-cols-1 lg:grid-cols-[240px_1fr] gap-4 lg:gap-6 items-stretch">
      <!-- Overlay para Mobile Sidebar -->
      <div
        v-if="isSidebarOpen"
        class="fixed inset-0 bg-slate-900/60 backdrop-blur-[2px] z-40 lg:hidden transition-opacity"
        @click="isSidebarOpen = false"
      />

      <!-- Coluna Fixa Esquerda: Navegação Vertical (Menu do Prontuário) -->
      <div 
        class="menu-sidebar bg-n-background border border-n-strong max-lg:!fixed max-lg:!top-0 max-lg:!left-0 max-lg:!bottom-0 max-lg:!h-[100dvh] max-lg:!w-[280px] max-lg:!max-w-[85vw] max-lg:z-50 transition-transform duration-300 transform lg:!translate-x-0 overflow-y-auto"
        :class="[isSidebarOpen ? 'translate-x-0 !shadow-2xl' : '-translate-x-full', 'flex flex-col']"
      >
        <!-- Mobile menu title (optional) -->
        <div class="lg:hidden flex items-center justify-between p-4 mb-2 border-b border-white/10">
          <span class="font-semibold text-slate-200">Prontuário</span>
          <button class="text-slate-400 hover:text-white" @click="isSidebarOpen = false">
            <i class="i-lucide-x w-5 h-5" />
          </button>
        </div>

        <nav class="vertical-tabs-nav">
          <button
            v-for="tab in tabs"
            :key="tab.id"
            class="vertical-tab-btn"
            :class="{ active: activeTab === tab.id }"
            @click="activeTab = tab.id; isSidebarOpen = false"
          >
            <i :class="tab.icon" />
            <span>{{ tab.label }}</span>
          </button>
        </nav>
      </div>

      <!-- Área Direita Principal: Conteúdo Dinâmico Baseada na Aba -->
      <div class="main-content">
        <div class="tab-content-area">
          <!-- ABA: GERAL -->
          <div v-if="activeTab === 'general'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Visão Geral
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Painel clínico rápido — informações essenciais antes do
                  atendimento.
                </p>
              </div>
              <button
                class="geral-header-btn"
                @click="activeTab = 'registration'"
              >
                <i class="i-lucide-edit-3 w-4 h-4" />
                Editar Ficha
              </button>
            </div>

            <!-- Banner: Alertas Críticos -->
            <div
              v-if="
                patient.critical_alerts && patient.critical_alerts.length > 0
              "
              class="geral-alert-banner mb-4"
            >
              <div class="geral-alert-icon">
                <i class="i-lucide-siren w-4 h-4" />
              </div>
              <div class="geral-alert-body">
                <span class="geral-alert-title">Alertas Críticos</span>
                <span class="geral-alert-text">
                  <span v-for="(a, i) in patient.critical_alerts" :key="i">
                    {{ a.title || a.message
                    }}<span v-if="i < patient.critical_alerts.length - 1">
                      ·
                    </span>
                  </span>
                </span>
              </div>
            </div>

            <!-- Nota Fixada -->
            <div v-if="patient.pinned_note" class="geral-pinned-note mb-4">
              <i class="i-lucide-pin w-4 h-4 text-amber-400 flex-shrink-0" />
              <span class="text-sm text-slate-300">{{
                patient.pinned_note
              }}</span>
            </div>

            <!-- Grid principal -->
            <div class="reg-form-grid flex flex-col gap-4">
              <!-- ── Tags Clínicas ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-purple">
                      <i class="i-lucide-tag w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title">Tags Clínicas</span>
                      <span class="reg-section-subtitle"
                        >Geradas automaticamente pela anamnese</span
                      >
                    </div>
                  </div>
                  <button
                    class="geral-action-btn"
                    @click="activeTab = 'anamnesis'"
                  >
                    <i class="i-lucide-clipboard-plus w-3.5 h-3.5" />
                    Ver Anamnese
                  </button>
                </div>
                <div class="reg-section-body">
                  <div
                    v-if="computedClinicalTags.length > 0"
                    class="geral-tags-row"
                  >
                    <div
                      v-for="(tag, index) in computedClinicalTags"
                      :key="index"
                      class="clinical-tag"
                      :class="'tag-' + tag.type"
                    >
                      <i :class="tag.icon" />
                      <span>{{ tag.label }}</span>
                    </div>
                  </div>
                  <p v-else class="text-sm text-slate-500">
                    Nenhuma tag clínica. Preencha a anamnese para gerar
                    automaticamente.
                  </p>
                </div>
              </div>

              <!-- ── Grid de 2 colunas: Tratamento + Dados da Conta ── -->
              <div class="reg-field-grid-2">
                <!-- Tratamento Ativo -->
                <div class="reg-section">
                  <div class="reg-section-toggle" style="cursor: default">
                    <div class="reg-section-toggle-left">
                      <div class="reg-section-icon reg-icon-blue">
                        <i class="i-lucide-stethoscope w-4 h-4" />
                      </div>
                      <div>
                        <span class="reg-section-title">Tratamento Ativo</span>
                        <span class="reg-section-subtitle"
                          >Plano e profissional responsável</span
                        >
                      </div>
                    </div>
                    <button
                      class="geral-action-btn"
                      @click="activeTab = 'treatment_plan'"
                    >
                      <i class="i-lucide-arrow-right w-3.5 h-3.5" />
                      Ver Planos
                    </button>
                  </div>
                  <div class="reg-section-body">
                    <div v-if="activePlanSummary">
                      <p class="geral-plan-title">
                        {{ activePlanSummary.title || 'Plano sem título' }}
                      </p>
                      <div class="flex items-center gap-2 mt-2">
                        <span
                          class="status-badge"
                          :class="
                            activePlanSummary.status === 'in_progress'
                              ? 'badge-blue'
                              : 'badge-green'
                          "
                        >
                          {{
                            activePlanSummary.status === 'in_progress'
                              ? 'Em andamento'
                              : activePlanSummary.status === 'approved'
                                ? 'Aprovado'
                                : activePlanSummary.status
                          }}
                        </span>
                        <span
                          v-if="activePlanSummary.estimated_duration"
                          class="text-slate-500 text-xs"
                        >
                          {{ activePlanSummary.estimated_duration }}
                        </span>
                      </div>
                      <p
                        v-if="activePlanSummary.description"
                        class="text-slate-400 text-xs mt-2 line-clamp-2"
                      >
                        {{ activePlanSummary.description }}
                      </p>
                    </div>
                    <p v-else class="text-sm text-slate-500">
                      Nenhum plano ativo.
                    </p>

                    <div class="geral-divider" />

                    <div class="geral-prof-row">
                      <div class="geral-prof-avatar">
                        <i class="i-lucide-user-check w-3.5 h-3.5" />
                      </div>
                      <div>
                        <span class="text-xs text-slate-500"
                          >Profissional Responsável</span
                        >
                        <p class="text-sm text-slate-200 font-medium mt-0.5">
                          {{ responsibleProfName }}
                        </p>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Dados da Conta -->
                <div class="reg-section">
                  <div class="reg-section-toggle" style="cursor: default">
                    <div class="reg-section-toggle-left">
                      <div class="reg-section-icon reg-icon-amber">
                        <i class="i-lucide-settings-2 w-4 h-4" />
                      </div>
                      <div>
                        <span class="reg-section-title">Dados da Conta</span>
                        <span class="reg-section-subtitle"
                          >Status, unidade e origem</span
                        >
                      </div>
                    </div>
                  </div>
                  <div class="reg-section-body">
                    <div class="form-group">
                      <label class="form-label">Status do Paciente</label>
                      <select
                        v-model="patient.patient_status"
                        class="form-input"
                        @change="handleStatusChange($event)"
                      >
                        <option value="novo">Novo</option>
                        <option value="ativo">Ativo</option>
                        <option value="inativo">Inativo</option>
                        <option value="faltoso">Faltoso</option>
                        <option value="alta">Alta</option>
                        <option value="arquivado">Arquivado</option>
                      </select>
                    </div>
                    <div class="geral-meta-row">
                      <div class="geral-meta-item">
                        <span class="geral-meta-label text-slate-500">Unidade / Clínica</span>
                        <span class="geral-meta-value text-slate-900 dark:text-slate-100">{{
                          patient.unit || '—'
                        }}</span>
                      </div>
                      <div class="geral-meta-item mt-4">
                        <span class="geral-meta-label text-slate-500">Origem (Lead)</span>
                        <span class="geral-meta-value text-slate-900 dark:text-slate-100">{{
                          patient.origin || '—'
                        }}</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- ── Jornada de Consultas ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-green">
                      <i class="i-lucide-calendar-days w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Jornada de Consultas</span
                      >
                      <span class="reg-section-subtitle"
                        >Última e próxima consulta agendada</span
                      >
                    </div>
                  </div>
                  <button
                    class="geral-header-btn"
                    @click="handleHeaderSchedule"
                  >
                    <i class="i-lucide-calendar-plus w-3.5 h-3.5" />
                    Agendar Consulta
                  </button>
                </div>
                <div class="reg-section-body">
                  <div class="reg-field-grid-2">
                    <!-- Última Consulta -->
                    <div class="geral-visit-card bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl shadow-sm p-4 md:p-6">
                      <div class="geral-visit-icon geral-visit-icon--past bg-slate-100 dark:bg-slate-700 text-slate-500 dark:text-slate-400">
                        <i class="i-lucide-history w-4 h-4" />
                      </div>
                      <div class="geral-visit-info">
                        <span class="geral-visit-label text-slate-500">Última Consulta</span>
                        <template v-if="lastAppointmentFormatted">
                          <span class="geral-visit-date text-slate-900 dark:text-slate-100">{{
                            lastAppointmentFormatted.date
                          }}</span>
                          <span class="geral-visit-time">{{
                            lastAppointmentFormatted.time
                          }}</span>
                        </template>
                        <span
v-else class="geral-visit-empty"
                          >Nenhuma consulta registrada</span
                        >
                      </div>
                    </div>

                    <!-- Próxima Consulta -->
                    <div class="geral-visit-card geral-visit-card--next bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl shadow-sm p-4 md:p-6">
                      <div class="geral-visit-icon geral-visit-icon--next bg-emerald-100 dark:bg-emerald-900 text-emerald-600 dark:text-emerald-400">
                        <i class="i-lucide-calendar-clock w-4 h-4" />
                      </div>
                      <div class="geral-visit-info">
                        <span class="geral-visit-label text-slate-500">Próxima Consulta</span>
                        <template v-if="nextAppointmentFormatted">
                          <span
                            class="geral-visit-date geral-visit-date--highlight text-emerald-600 dark:text-emerald-400"
                            >{{ nextAppointmentFormatted.date }}</span
                          >
                          <span class="geral-visit-time">{{
                            nextAppointmentFormatted.time
                          }}</span>
                        </template>
                        <span
v-else class="geral-visit-empty"
                          >Nenhum agendamento futuro</span
                        >
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- ABA: CADASTRO -->
          <div
            v-else-if="activeTab === 'registration'"
            class="tab-pane fade-in"
          >
            <!-- Header do Cadastro Progressivo -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Ficha Cadastral
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Preenchimento progressivo — salve quando quiser.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <span class="text-xs text-slate-500"
                  >Última alteração: {{ formatDate(patient.updated_at) }}</span
                >
                <button
                  class="btn-primary flex items-center gap-2"
                  @click="saveRegistration"
                >
                  <i class="i-lucide-save w-4 h-4" />
                  Salvar
                </button>
              </div>
            </div>

            <!-- Form layout -->
            <div class="reg-form-grid">
              <!-- ── SEÇÃO 1: DADOS PESSOAIS ── -->
              <div class="reg-section">
                <button
                  class="reg-section-toggle"
                  @click="toggleRegSection('personal')"
                >
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-blue">
                      <i class="i-lucide-user w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title">Dados Pessoais</span>
                      <span class="reg-section-subtitle"
                        >Nome, nascimento, documento</span
                      >
                    </div>
                  </div>
                  <i
                    class="i-lucide-chevron-down w-4 h-4 reg-chevron"
                    :class="{ 'reg-chevron-open': regSections.personal }"
                  />
                </button>

                <div v-if="regSections.personal" class="reg-section-body">
                  <!-- Avatar Upload -->
                  <div class="reg-avatar-row">
                    <div
                      class="reg-avatar-wrapper"
                      @click="triggerAvatarUpload"
                    >
                      <img
                        v-if="patient.avatar_url"
                        :src="patient.avatar_url"
                        class="reg-avatar-img"
                        alt="Avatar do paciente"
                      />
                      <div v-else class="reg-avatar-placeholder">
                        {{ getInitials(patient.name) }}
                      </div>
                      <div class="reg-avatar-overlay">
                        <i class="i-lucide-camera w-5 h-5" />
                      </div>
                    </div>
                    <div class="reg-avatar-info">
                      <p class="text-sm font-medium text-slate-200">
                        Foto de Perfil
                      </p>
                      <p class="text-xs text-slate-500 mt-0.5">
                        JPG ou PNG · máx. 15MB
                      </p>
                      <div class="flex gap-2 mt-3">
                        <button
                          class="btn-secondary btn-xs flex items-center gap-1.5"
                          @click.stop="openCameraModal"
                        >
                          <i class="i-lucide-camera w-3.5 h-3.5" /> Câmera
                        </button>
                        <button
                          class="btn-secondary btn-xs flex items-center gap-1.5"
                          @click.stop="triggerAvatarUpload"
                        >
                          <i class="i-lucide-upload w-3.5 h-3.5" /> Upload
                        </button>
                      </div>
                      <input
                        ref="avatarInputRef"
                        type="file"
                        class="hidden"
                        accept="image/jpeg, image/png, image/gif"
                        @change="handleAvatarUpload"
                      />
                    </div>
                  </div>

                  <div class="reg-divider" />

                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label
                        >Primeiro Nome
                        <span class="reg-required">*</span></label
                      >
                      <input
                        v-model="editFirstName"
                        type="text"
                        class="form-input"
                        placeholder="Gabriel"
                      />
                    </div>
                    <div class="form-group">
                      <label>Sobrenome</label>
                      <input
                        v-model="editLastName"
                        type="text"
                        class="form-input"
                        placeholder="Fernandes"
                      />
                    </div>
                    <div class="form-group">
                      <label>Nome Social</label>
                      <input
                        type="text"
                        class="form-input"
                        placeholder="Opcional"
                      />
                    </div>
                  </div>

                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label
                        >Data de Nascimento
                        <span class="reg-required">*</span></label
                      >
                      <input
                        v-model="patient.birthdate"
                        type="date"
                        class="form-input"
                        :max="new Date().toISOString().split('T')[0]"
                        min="1900-01-01"
                      />
                    </div>
                    <div class="form-group">
                      <label>Sexo <span class="reg-required">*</span></label>
                      <select v-model="patient.sex" class="form-input">
                        <option value="feminino">Feminino</option>
                        <option value="masculino">Masculino</option>
                        <option value="outro">Outro</option>
                        <option value="nao_informado">Não Informado</option>
                      </select>
                    </div>
                    <div class="form-group">
                      <label>Estado Civil</label>
                      <select
                        v-model="patient.marital_status"
                        class="form-input"
                      >
                        <option value="solteiro">Solteiro(a)</option>
                        <option value="casado">Casado(a)</option>
                        <option value="divorciado">Divorciado(a)</option>
                        <option value="viuvo">Viúvo(a)</option>
                      </select>
                    </div>
                  </div>

                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label>CPF <span class="reg-required">*</span></label>
                      <input
                        :value="formatCpfDisplay(patient.cpf)"
                        type="text"
                        class="form-input"
                        placeholder="000.000.000-00"
                        @input="handleCpfInput"
                      />
                    </div>
                    <div class="form-group">
                      <label>RG</label>
                      <input
                        v-model="patient.rg"
                        type="text"
                        class="form-input"
                        placeholder="Ex: 1234567"
                        maxlength="20"
                      />
                    </div>
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 2: CONTATO ── -->
              <div class="reg-section">
                <button
                  class="reg-section-toggle"
                  @click="toggleRegSection('contact')"
                >
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-green">
                      <i class="i-lucide-phone w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Contato e Comunicação</span
                      >
                      <span class="reg-section-subtitle"
                        >Telefone, e-mail, preferências</span
                      >
                    </div>
                  </div>
                  <i
                    class="i-lucide-chevron-down w-4 h-4 reg-chevron"
                    :class="{ 'reg-chevron-open': regSections.contact }"
                  />
                </button>

                <div v-if="regSections.contact" class="reg-section-body">
                  <div class="reg-field-grid-2">
                    <div class="form-group reg-field-relative">
                      <label>
                        Telefone Principal
                        <span class="reg-badge-wpp"
                          ><i class="i-lucide-message-circle w-3 h-3" />
                          WhatsApp</span
                        >
                        <span class="reg-required">*</span>
                      </label>
                      <input
                        type="text"
                        class="form-input"
                        placeholder="(00) 00000-0000"
                        :value="formatPhoneDisplay(patient.phone)"
                        autocomplete="off"
                        @focus="
                          phoneContactDropdown = phoneContactResults.length > 0
                        "
                        @blur="
                          setTimeout(() => {
                            phoneContactDropdown = false;
                          }, 200)
                        "
                        @input="handlePhoneInput"
                      />
                      <!-- Dropdown de sugestão de contato -->
                      <div
                        v-if="
                          phoneContactDropdown &&
                          (phoneContactSearching ||
                            phoneContactResults.length > 0)
                        "
                        class="reg-contact-dropdown"
                      >
                        <div
                          v-if="phoneContactSearching"
                          class="reg-dropdown-loading"
                        >
                          Buscando...
                        </div>
                        <ul v-else class="reg-dropdown-list">
                          <li
                            v-for="contact in phoneContactResults"
                            :key="contact.id"
                            class="reg-dropdown-item"
                            @mousedown.prevent="selectPhoneContact(contact)"
                          >
                            <span
                              v-if="contact.avatar_url"
                              class="reg-item-avatar reg-item-avatar--img"
                            >
                              <img
                                :src="contact.avatar_url"
                                :alt="contact.name"
                              />
                            </span>
                            <span
                              v-else
                              class="reg-item-avatar"
                              :style="{
                                background: phoneContactColor(contact.name),
                              }"
                            >
                              {{ (contact.name || '?')[0].toUpperCase() }}
                            </span>
                            <div class="reg-item-info">
                              <span class="reg-item-name">{{
                                contact.name || 'Sem nome'
                              }}</span>
                              <span class="reg-item-phone">{{
                                contact.phone_number
                              }}</span>
                            </div>
                          </li>
                        </ul>
                      </div>
                    </div>
                    <div class="form-group">
                      <label>Telefone Alternativo</label>
                      <input
                        :value="
                          formatPhoneDisplay(patient.emergency_contact?.phone)
                        "
                        type="text"
                        class="form-input"
                        placeholder="(11) 00000-0000"
                        @input="handleAlternativePhoneInput"
                      />
                    </div>
                  </div>

                  <div class="form-group">
                    <label>E-mail</label>
                    <input
                      v-model="patient.email"
                      type="email"
                      class="form-input"
                      placeholder="paciente@email.com"
                    />
                  </div>

                  <div class="reg-divider" />

                  <p class="reg-subsection-label">Preferências de contato</p>
                  <div class="reg-opt-in-grid">
                    <label class="reg-opt-in-card">
                      <div class="reg-opt-in-info">
                        <i
                          class="i-lucide-message-circle w-4 h-4 text-green-400"
                        />
                        <div>
                          <p class="text-sm font-medium text-slate-200">
                            WhatsApp
                          </p>
                          <p class="text-xs text-slate-500">
                            Lembretes e confirmações
                          </p>
                        </div>
                      </div>
                      <div
                        class="reg-toggle"
                        :class="{
                          'reg-toggle-on':
                            patient.communication_opt_ins.whatsapp,
                        }"
                        @click="
                          patient.communication_opt_ins.whatsapp =
                            !patient.communication_opt_ins.whatsapp
                        "
                      >
                        <div class="reg-toggle-thumb" />
                      </div>
                    </label>
                    <label class="reg-opt-in-card">
                      <div class="reg-opt-in-info">
                        <i class="i-lucide-mail w-4 h-4 text-blue-400" />
                        <div>
                          <p class="text-sm font-medium text-slate-200">
                            E-mail
                          </p>
                          <p class="text-xs text-slate-500">
                            Comprovantes e comunicados
                          </p>
                        </div>
                      </div>
                      <div
                        class="reg-toggle"
                        :class="{
                          'reg-toggle-on': patient.communication_opt_ins.email,
                        }"
                        @click="
                          patient.communication_opt_ins.email =
                            !patient.communication_opt_ins.email
                        "
                      >
                        <div class="reg-toggle-thumb" />
                      </div>
                    </label>
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 3: ENDEREÇO ── -->
              <div class="reg-section">
                <button
                  class="reg-section-toggle"
                  @click="toggleRegSection('address')"
                >
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-amber">
                      <i class="i-lucide-map-pin w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title">Endereço</span>
                      <span class="reg-section-subtitle"
                        >CEP, rua, cidade, estado</span
                      >
                    </div>
                  </div>
                  <i
                    class="i-lucide-chevron-down w-4 h-4 reg-chevron"
                    :class="{ 'reg-chevron-open': regSections.address }"
                  />
                </button>

                <div v-if="regSections.address" class="reg-section-body">
                  <div class="reg-field-grid-cep">
                    <div class="form-group">
                      <label>CEP</label>
                      <div class="input-with-action">
                        <input
                          v-model="patient.address.zip_code"
                          type="text"
                          class="form-input"
                          placeholder="00000-000"
                        />
                        <button
                          class="btn-icon-inside"
                          @click.prevent="searchCep"
                        >
                          <i class="i-lucide-search w-4 h-4" />
                        </button>
                      </div>
                    </div>
                    <div class="form-group">
                      <label>Rua / Avenida</label>
                      <input
                        v-model="patient.address.street"
                        type="text"
                        class="form-input"
                      />
                    </div>
                  </div>

                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label>Número</label>
                      <input
                        v-model="patient.address.number"
                        type="text"
                        class="form-input"
                      />
                    </div>
                    <div class="form-group">
                      <label>Complemento</label>
                      <input
                        v-model="patient.address.complement"
                        type="text"
                        class="form-input"
                        placeholder="Apto, bloco..."
                      />
                    </div>
                    <div class="form-group">
                      <label>Bairro</label>
                      <input
                        v-model="patient.address.neighborhood"
                        type="text"
                        class="form-input"
                      />
                    </div>
                  </div>

                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label>Cidade</label>
                      <input
                        v-model="patient.address.city"
                        type="text"
                        class="form-input"
                      />
                    </div>
                    <div class="form-group">
                      <label>Estado (UF)</label>
                      <select
                        v-model="patient.address.state"
                        class="form-input"
                      >
                        <option value="AC">AC</option>
                        <option value="AL">AL</option>
                        <option value="AM">AM</option>
                        <option value="AP">AP</option>
                        <option value="BA">BA</option>
                        <option value="CE">CE</option>
                        <option value="DF">DF</option>
                        <option value="ES">ES</option>
                        <option value="GO">GO</option>
                        <option value="MA">MA</option>
                        <option value="MG">MG</option>
                        <option value="MS">MS</option>
                        <option value="MT">MT</option>
                        <option value="PA">PA</option>
                        <option value="PB">PB</option>
                        <option value="PE">PE</option>
                        <option value="PI">PI</option>
                        <option value="PR">PR</option>
                        <option value="RJ">RJ</option>
                        <option value="RN">RN</option>
                        <option value="RO">RO</option>
                        <option value="RR">RR</option>
                        <option value="RS">RS</option>
                        <option value="SC">SC</option>
                        <option value="SE">SE</option>
                        <option value="SP">SP</option>
                        <option value="TO">TO</option>
                      </select>
                    </div>
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 4: ADMINISTRATIVO ── -->
              <div class="reg-section">
                <button
                  class="reg-section-toggle"
                  @click="toggleRegSection('admin')"
                >
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-purple">
                      <i class="i-lucide-briefcase w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Administrativo e Convênio</span
                      >
                      <span class="reg-section-subtitle"
                        >Plano de saúde, emergência, LGPD</span
                      >
                    </div>
                  </div>
                  <i
                    class="i-lucide-chevron-down w-4 h-4 reg-chevron"
                    :class="{ 'reg-chevron-open': regSections.admin }"
                  />
                </button>

                <div v-if="regSections.admin" class="reg-section-body">
                  <p class="reg-subsection-label">Plano de Saúde / Convênio</p>
                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label>Convênio</label>
                      <select
                        v-model="patient.insurance.name"
                        class="form-input"
                      >
                        <option value="Particular">Particular</option>
                        <option value="Bradesco Saúde">Bradesco Saúde</option>
                        <option value="SulAmérica">SulAmérica</option>
                        <option value="Amil">Amil</option>
                        <option value="Unimed">Unimed</option>
                        <option value="Porto Seguro">Porto Seguro</option>
                      </select>
                    </div>
                    <div class="form-group">
                      <label>Nº da Carteirinha</label>
                      <input
                        v-model="patient.insurance.number"
                        type="text"
                        class="form-input"
                        placeholder="000.000.000"
                      />
                    </div>
                  </div>
                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label>Plano</label>
                      <input
                        v-model="patient.insurance.plan"
                        type="text"
                        class="form-input"
                        placeholder="Ex: Executivo Plus"
                      />
                    </div>
                    <div class="form-group">
                      <label>Validade da Carteirinha</label>
                      <input
                        v-model="patient.insurance.valid_until"
                        type="date"
                        class="form-input"
                        min="1900-01-01"
                        max="2100-12-31"
                      />
                    </div>
                  </div>

                  <div class="reg-divider" />

                  <p class="reg-subsection-label">Contato de Emergência</p>
                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label>Nome</label>
                      <input
                        v-model="patient.emergency_contact.name"
                        type="text"
                        class="form-input"
                      />
                    </div>
                    <div class="form-group">
                      <label>Telefone</label>
                      <input
                        v-model="patient.emergency_contact.phone"
                        type="text"
                        class="form-input"
                      />
                    </div>
                    <div class="form-group">
                      <label>Grau de Parentesco</label>
                      <input
                        v-model="patient.emergency_contact.relationship"
                        type="text"
                        class="form-input"
                        placeholder="Ex: Cônjuge"
                      />
                    </div>
                  </div>

                  <div class="reg-divider" />

                  <p class="reg-subsection-label">LGPD e Consentimentos</p>
                  <div class="reg-opt-in-grid">
                    <label class="reg-opt-in-card">
                      <div class="reg-opt-in-info">
                        <i
                          class="i-lucide-shield-check w-4 h-4 text-blue-400"
                        />
                        <div>
                          <p class="text-sm font-medium text-slate-200">
                            Termo LGPD
                          </p>
                          <p class="text-xs text-slate-500">
                            Armazenamento de dados médicos
                          </p>
                        </div>
                      </div>
                      <div
                        class="reg-toggle"
                        :class="{
                          'reg-toggle-on': patient.lgpd_consent.accepted,
                        }"
                        @click="
                          patient.lgpd_consent.accepted =
                            !patient.lgpd_consent.accepted
                        "
                      >
                        <div class="reg-toggle-thumb" />
                      </div>
                    </label>
                    <label class="reg-opt-in-card">
                      <div class="reg-opt-in-info">
                        <i class="i-lucide-image w-4 h-4 text-purple-400" />
                        <div>
                          <p class="text-sm font-medium text-slate-200">
                            Uso de Imagem
                          </p>
                          <p class="text-xs text-slate-500">
                            Marketing e redes sociais
                          </p>
                        </div>
                      </div>
                      <div
                        class="reg-toggle"
                        :class="{
                          'reg-toggle-on':
                            patient.lgpd_consent.image_use_accepted,
                        }"
                        @click="
                          patient.lgpd_consent.image_use_accepted =
                            !patient.lgpd_consent.image_use_accepted
                        "
                      >
                        <div class="reg-toggle-thumb" />
                      </div>
                    </label>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- ABA: ANAMNESE -->

          <div v-else-if="activeTab === 'anamnesis'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Questionário Clínico
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Histórico de saúde, queixa principal, alergias e restrições.
                  <span
                    v-if="currentAnamnesis.status === 'finalized'"
                    class="ml-2 inline-flex items-center gap-1 text-amber-400 text-xs bg-amber-500/10 px-2 py-0.5 rounded-full border border-amber-500/20"
                  >
                    <i class="i-lucide-lock w-3 h-3" /> Somente leitura
                    (Assinada)
                  </span>
                </p>
              </div>
              <div class="flex items-center gap-3">
                <span
                  v-if="currentAnamnesis.updated_at"
                  class="text-xs text-slate-500"
                >
                  Última alteração:
                  {{ formatDate(currentAnamnesis.updated_at) }}
                </span>

                <a
                  v-if="currentAnamnesis.pdf_url"
                  :href="currentAnamnesis.pdf_url"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="geral-header-btn"
                >
                  <i class="i-lucide-file-text" /> Visualizar PDF
                </a>

                <button
                  v-if="currentAnamnesis.status === 'finalized'"
                  class="geral-header-btn"
                  @click="startNewAnamnesis"
                >
                  <i class="i-lucide-plus" /> Nova Anamnese
                </button>

                <button
                  v-else
                  class="geral-header-btn"
                  :disabled="isSavingAnamnesis"
                  @click="saveAnamnesis(false)"
                >
                  <i class="i-lucide-save" /> Salvar Rascunho
                </button>

                <button
                  v-if="currentAnamnesis.status !== 'finalized'"
                  class="btn-primary flex items-center gap-2"
                  :disabled="isSavingAnamnesis"
                  @click="saveAnamnesis(true)"
                >
                  <i class="i-lucide-lock" /> Assinar e Finalizar
                </button>
              </div>
            </div>

            <!-- Seções da Anamnese -->
            <div class="reg-form-grid">
              <!-- ── SEÇÃO 1: MOTIVO DA CONSULTA ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-cyan">
                      <i class="i-lucide-stethoscope w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title">Motivo da Consulta</span>
                      <span class="reg-section-subtitle"
                        >Especialidade, queixa principal e objetivo</span
                      >
                    </div>
                  </div>
                </div>
                <div class="reg-section-body">
                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label class="form-label"
                        >Especialidade / Foco Principal</label
                      >
                      <select
                        v-model="currentAnamnesis.specialty"
                        class="form-input"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      >
                        <option value="Odontologia Geral">
                          Odontologia Geral
                        </option>
                        <option value="Estética Facial">Estética Facial</option>
                        <option value="Dermatologia">Dermatologia</option>
                        <option value="Avaliação Clínica">
                          Avaliação Clínica
                        </option>
                      </select>
                    </div>
                  </div>
                  <div class="form-group">
                    <label class="form-label">
                      Queixa Principal
                      <span class="reg-required">*</span>
                    </label>
                    <textarea
                      v-model="currentAnamnesis.chief_complaint"
                      class="form-input form-textarea"
                      rows="3"
                      placeholder="Descreva com as palavras do paciente o que o trouxe à clínica..."
                      :disabled="currentAnamnesis.status === 'finalized'"
                    />
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 2: HISTÓRICO DE SAÚDE ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-blue">
                      <i class="i-lucide-activity w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title">Histórico de Saúde</span>
                      <span class="reg-section-subtitle"
                        >Doenças preexistentes e condições sistêmicas</span
                      >
                    </div>
                  </div>
                </div>
                <div class="reg-section-body">
                  <div class="anm-check-grid">
                    <label class="check-item">
                      <input
                        v-model="currentAnamnesis.medical_history.hypertension"
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label"
                        >Hipertensão ou problemas cardiovasculares</span
                      >
                    </label>
                    <label class="check-item">
                      <input
                        v-model="currentAnamnesis.medical_history.pregnant"
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label">Gestante / Lactante</span>
                    </label>
                    <label class="check-item">
                      <input
                        v-model="currentAnamnesis.medical_history.diabetes"
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label">Diabetes</span>
                    </label>
                    <label class="check-item">
                      <input
                        v-model="currentAnamnesis.medical_history.oncology"
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label"
                        >Tratamento oncológico (Atual ou prévio)</span
                      >
                    </label>
                    <label class="check-item">
                      <input
                        v-model="
                          currentAnamnesis.medical_history.bleeding_disorder
                        "
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label"
                        >Distúrbios de coagulação / hemorragia</span
                      >
                    </label>
                    <label class="check-item">
                      <input
                        v-model="currentAnamnesis.medical_history.hepatitis"
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label"
                        >Hepatite / Doenças hepáticas</span
                      >
                    </label>
                  </div>
                  <div class="form-group">
                    <label class="form-label"
                      >Outras Doenças ou Condições</label
                    >
                    <input
                      v-model="currentAnamnesis.medical_history.other"
                      type="text"
                      class="form-input"
                      placeholder="Especifique detalhadamente se houver..."
                      :disabled="currentAnamnesis.status === 'finalized'"
                    />
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 3: ALERGIAS E MEDICAMENTOS ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-red">
                      <i class="i-lucide-pill w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Alergias e Medicamentos</span
                      >
                      <span class="reg-section-subtitle"
                        >Alergias conhecidas e uso contínuo</span
                      >
                    </div>
                  </div>
                </div>
                <div class="reg-section-body">
                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label class="form-label anm-label-danger">
                        <i class="i-lucide-triangle-alert w-3.5 h-3.5" />
                        Alergias Conhecidas
                        <span class="reg-required">*</span>
                      </label>
                      <input
                        v-model="allergyInput"
                        type="text"
                        class="form-input anm-input-danger"
                        @blur="flushAllergyInput"
                        placeholder="Ex: Dipirona, Iodo — separadas por vírgula"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div
                        v-if="currentAnamnesis.allergies?.length"
                        class="anm-tags-row"
                      >
                        <span
                          v-for="(alg, idx) in currentAnamnesis.allergies"
                          :key="idx"
                          class="anm-tag anm-tag--red"
                        >
                          {{ alg.name }}
                          <button
                            v-if="currentAnamnesis.status !== 'finalized'"
                            type="button"
                            class="anm-tag-remove"
                            :aria-label="`Remover ${alg.name}`"
                            @click="removeAllergy(idx)"
                          >
                            <i class="i-lucide-x w-3 h-3" />
                          </button>
                        </span>
                      </div>
                    </div>
                    <div class="form-group">
                      <label class="form-label"
                        >Medicamentos de Uso Contínuo</label
                      >
                      <input
                        v-model="medicationInput"
                        type="text"
                        class="form-input"
                        placeholder="Ex: Losartana 50mg, AAS..."
                        :disabled="currentAnamnesis.status === 'finalized'"
                        @blur="flushMedicationInput"
                      />
                      <div
                        v-if="currentAnamnesis.current_medications?.length"
                        class="anm-tags-row"
                      >
                        <span
                          v-for="(
                            med, idx
                          ) in currentAnamnesis.current_medications"
                          :key="idx"
                          class="anm-tag anm-tag--blue"
                        >
                          {{ med.name }}
                          <button
                            v-if="currentAnamnesis.status !== 'finalized'"
                            type="button"
                            class="anm-tag-remove"
                            :aria-label="`Remover ${med.name}`"
                            @click="removeMedication(idx)"
                          >
                            <i class="i-lucide-x w-3 h-3" />
                          </button>
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 4: HISTÓRICO CIRÚRGICO ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-orange">
                      <i class="i-lucide-scissors w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Histórico Cirúrgico e Implantes</span
                      >
                      <span class="reg-section-subtitle"
                        >Cirurgias recentes, implantes e reações a
                        anestesia</span
                      >
                    </div>
                  </div>
                </div>
                <div class="reg-section-body">
                  <div class="anm-check-col">
                    <label class="check-item">
                      <input
                        v-model="currentAnamnesis.medical_history.has_recent_surgeries"
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label"
                        >Realizou cirurgias nos últimos 6 meses?</span
                      >
                    </label>
                    <label class="check-item">
                      <input
                        v-model="currentAnamnesis.medical_history.has_implants"
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label"
                        >Possui implantes, próteses ou marcapasso?</span
                      >
                    </label>
                    <label class="check-item">
                      <input
                        v-model="currentAnamnesis.medical_history.has_anesthesia_complications"
                        type="checkbox"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      />
                      <div class="check-item-box" />
                      <span class="check-item-label"
                        >Teve complicações ou reações com anestesia no
                        passado?</span
                      >
                    </label>
                  </div>
                  <div class="form-group">
                    <label class="form-label"
                      >Detalhes das Intervenções Recentes</label
                    >
                    <textarea
                      v-model="currentAnamnesis.surgical_history"
                      class="form-input form-textarea"
                      rows="2"
                      placeholder="Especifique os procedimentos, áreas e reações adversas..."
                      :disabled="currentAnamnesis.status === 'finalized'"
                    />
                  </div>
                </div>
              </div>

              <!-- ── SEÇÃO 5: HÁBITOS E ESTILO DE VIDA ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-green">
                      <i class="i-lucide-leaf w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Hábitos e Estilo de Vida</span
                      >
                      <span class="reg-section-subtitle"
                        >Tabagismo, álcool, atividade física e observações</span
                      >
                    </div>
                  </div>
                </div>
                <div class="reg-section-body">
                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label class="form-label">Fumante?</label>
                      <select
                        v-model="currentAnamnesis.relevant_habits.smoker"
                        class="form-input"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      >
                        <option value="Não">Não</option>
                        <option value="Sim, regular">Sim, regular</option>
                        <option value="Sim, socialmente">
                          Sim, socialmente
                        </option>
                        <option value="Ex-fumante">Ex-fumante</option>
                      </select>
                    </div>
                    <div class="form-group">
                      <label class="form-label">Consumo de Álcool</label>
                      <select
                        v-model="currentAnamnesis.relevant_habits.alcohol"
                        class="form-input"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      >
                        <option value="Não consome">Não consome</option>
                        <option value="Ocasionalmente">Ocasionalmente</option>
                        <option value="Frequentemente">Frequentemente</option>
                      </select>
                    </div>
                    <div class="form-group">
                      <label class="form-label">Prática de Esportes</label>
                      <select
                        v-model="currentAnamnesis.relevant_habits.sports"
                        class="form-input"
                        :disabled="currentAnamnesis.status === 'finalized'"
                      >
                        <option value="Sedentário">Sedentário</option>
                        <option value="Atividade moderada">
                          Atividade moderada
                        </option>
                        <option value="Atleta / Alta intensidade">
                          Atleta / Alta intensidade
                        </option>
                      </select>
                    </div>
                  </div>
                  <div class="anm-notes-card">
                    <div class="flex items-center gap-2 mb-3">
                      <i class="i-lucide-shield-alert w-4 h-4 text-amber-400" />
                      <span
                        class="text-xs font-semibold text-amber-400 uppercase tracking-wider"
                        >Observações Confidenciais</span
                      >
                    </div>
                    <textarea
                      v-model="currentAnamnesis.additional_notes"
                      class="form-input form-textarea anm-notes-input"
                      rows="3"
                      placeholder="Contraindicações, restrições específicas da prática clínica..."
                      :disabled="currentAnamnesis.status === 'finalized'"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- ABA: EVOLUÇÃO -->
          <div v-else-if="activeTab === 'evolution'" class="tab-pane fade-in">
            <div class="ev-tab-header">
              <div>
                <h3 class="ev-tab-title">Evolução / Atendimento</h3>
                <p class="ev-tab-subtitle">
                  Registro cronológico dos atendimentos. Novas entradas não
                  substituem as antigas.
                </p>
              </div>
            </div>
            <EvolutionTab
              :current-note="currentNote"
              :clinical-notes="clinicalNotes"
              :is-saving-note="isSavingNote"
              :format-date="formatDate"
              @update:current-note="currentNote = $event"
              @save="saveClinicalNote"
              @request-delete="requestDeleteNote"
              @edit-note="editClinicalNote"
            />
          </div>

          <!-- ABA: PLANO DE TRATAMENTO -->
          <div
            v-else-if="activeTab === 'treatment_plan'"
            class="tab-pane fade-in print-section"
          >
            <!-- ── Cabeçalho ── -->
            <div class="rp-tab-header hide-on-print">
              <div>
                <h3 class="rp-tab-title">Plano de Tratamento</h3>
                <p class="rp-tab-subtitle">
                  Planejamento clínico, orçamentos propostos e status de
                  execução.
                </p>
              </div>
              <button
                v-can="['patients', 'manage_treatment_plans']"
                class="rp-btn-new"
                @click="createTreatmentPlan"
              >
                <i class="i-lucide-plus rp-btn-new-icon" />
                Novo Plano
              </button>
            </div>

            <div class="rp-content-grid">
              <!-- ── Formulário de novo diagnóstico ── -->
              <div class="rp-card hide-on-print">
                <div class="rp-card-header">
                  <div class="rp-card-icon rp-card-icon--blue">
                    <i class="i-lucide-search" />
                  </div>
                  <div>
                    <span class="rp-card-title"
                      >Diagnóstico e Hipótese Inicial</span
                    >
                    <span class="rp-card-subtitle"
                      >Preencha para criar um novo plano de tratamento</span
                    >
                  </div>
                </div>
                <div class="rp-card-body">
                  <div class="rp-field">
                    <label class="rp-field-label"
                      >Justificativa Clínica / Queixa Principal do Novo
                      Plano</label
                    >
                    <textarea
                      v-model="globalDiagnosisDescription"
                      class="rp-field-input"
                      rows="2"
                      placeholder="Paciente apresenta escurecimento generalizado nos dentes e má oclusão leve..."
                    />
                  </div>
                  <div class="rp-field">
                    <label class="rp-field-label"
                      >Hipótese Diagnóstica / CID do Novo Plano</label
                    >
                    <input
                      v-model="globalDiagnosisTitle"
                      type="text"
                      class="rp-field-input"
                      placeholder="Ex: Esmalte escurecido (K03.7) + má oclusão leve"
                    />
                  </div>
                </div>
              </div>

              <!-- ── Empty State ── -->
              <div
                v-if="!treatmentPlans || treatmentPlans.length === 0"
                class="rp-empty"
              >
                <div class="rp-empty-icon">
                  <i class="i-lucide-clipboard-list" />
                </div>
                <p class="rp-empty-text">
                  Nenhum plano de tratamento criado ainda.
                </p>
                <p class="rp-empty-hint">
                  Preencha os campos acima e clique em "Novo Plano".
                </p>
              </div>

              <!-- ── Planos dinâmicos ── -->
              <div
                v-for="plan in treatmentPlans"
                :key="plan.id"
                class="rp-plan page-break-inside-avoid print-card"
              >
                <!-- Cabeçalho do plano -->
                <div class="rp-plan-head">
                  <div class="rp-plan-head-left">
                    <div class="rp-plan-head-icon">
                      <i class="i-lucide-list-checks" />
                    </div>
                    <div>
                      <span class="rp-plan-name">Plano de Tratamento</span>
                      <span class="rp-plan-cid">{{
                        plan.title || 'Sem hipótese definida'
                      }}</span>
                    </div>
                  </div>
                  <div class="rp-plan-actions hide-on-print">
                    <!-- Aprovado -->
                    <span
                      v-if="
                        plan.status === 'aprovado' || plan.status === 'approved'
                      "
                      class="rp-badge rp-badge--green"
                    >
                      <i class="i-lucide-check-circle rp-badge-icon" />
                      Aprovado
                    </span>
                    <!-- Proposto -->
                    <template v-else-if="plan.status === 'proposto'">
                      <button
                        class="rp-action-btn"
                        @click="
                          editingPlanId === plan.id
                            ? savePlan(plan)
                            : (editingPlanId = plan.id)
                        "
                      >
                        <i
                          :class="
                            editingPlanId === plan.id
                              ? 'i-lucide-save'
                              : 'i-lucide-pencil'
                          "
                          class="rp-action-btn-icon"
                        />
                        {{
                          editingPlanId === plan.id
                            ? 'Salvar Plano'
                            : 'Editar Plano'
                        }}
                      </button>
                      <button
                        v-can="['patients', 'manage_treatment_plans']"
                        class="rp-action-btn rp-action-btn--green"
                        @click="approvePlan(plan.id)"
                      >
                        <i class="i-lucide-check-circle rp-action-btn-icon" />
                        Aprovar
                      </button>
                      <button
                        v-can="['patients', 'manage_treatment_plans']"
                        class="rp-action-btn rp-action-btn--danger"
                        @click="requestDeletePlan(plan.id)"
                      >
                        <i class="i-lucide-trash-2 rp-action-btn-icon" />
                      </button>
                    </template>
                  </div>
                </div>

                <!-- Diagnóstico e Hipótese -->
                <div class="rp-section">
                  <div class="rp-section-label">
                    <i
                      class="i-lucide-search rp-section-icon rp-section-icon--blue"
                    />
                    Diagnóstico e Hipótese
                  </div>

                  <!-- Modo edição -->
                  <div v-if="editingPlanId === plan.id" class="rp-section-body">
                    <div class="rp-field">
                      <label class="rp-field-label"
                        >Justificativa Clínica / Queixa Principal</label
                      >
                      <textarea
                        v-model="plan.description"
                        class="rp-field-input"
                        rows="2"
                      />
                    </div>
                    <div class="rp-field">
                      <label class="rp-field-label"
                        >Hipótese Diagnóstica / CID</label
                      >
                      <input
                        v-model="plan.title"
                        type="text"
                        class="rp-field-input"
                      />
                    </div>
                  </div>

                  <!-- Modo leitura -->
                  <div v-else class="rp-section-body rp-diag-grid">
                    <div class="rp-diag-item">
                      <span class="rp-diag-label"
                        >Justificativa / Queixa Principal</span
                      >
                      <p class="rp-diag-value">
                        {{
                          plan.description ||
                          'O paciente não informou a queixa principal.'
                        }}
                      </p>
                    </div>
                    <div class="rp-diag-item">
                      <span class="rp-diag-label">Hipótese / CID</span>
                      <p class="rp-diag-value rp-diag-value--accent">
                        {{ plan.title || 'Nenhum CID informado.' }}
                      </p>
                    </div>
                  </div>
                </div>

                <!-- Procedimentos Planejados -->
                <div class="rp-section">
                  <div class="rp-section-label">
                    <i
                      class="i-lucide-clipboard-list rp-section-icon rp-section-icon--amber"
                    />
                    Procedimentos Planejados
                    <button
                      v-if="plan.status === 'proposto'"
                      class="rp-add-btn hide-on-print"
                      @click="openItemModal(plan)"
                    >
                      <i class="i-lucide-plus rp-add-btn-icon" /> Adicionar
                    </button>
                  </div>

                  <div class="rp-section-body rp-table-wrap">
                    <table class="rp-table">
                      <thead class="rp-table-head">
                        <tr>
                          <th class="rp-th">Procedimento</th>
                          <th class="rp-th">Região/Elemento</th>
                          <th class="rp-th rp-th--center">Sessões</th>
                          <th class="rp-th rp-th--right">Valor Un.</th>
                          <th class="rp-th rp-th--right">Subtotal</th>
                          <th class="rp-th rp-th--center hide-on-print">
                            Status
                          </th>
                          <th
                            v-if="plan.status === 'proposto'"
                            class="rp-th rp-th--right hide-on-print"
                          >
                            Ação
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr
                          v-if="
                            !plan.treatment_items ||
                            plan.treatment_items.length === 0
                          "
                        >
                          <td colspan="7" class="rp-td-empty">
                            Nenhum procedimento adicionado a este plano.
                          </td>
                        </tr>
                        <tr
                          v-for="item in plan.treatment_items"
                          :key="item.id"
                          class="rp-tr"
                        >
                          <td class="rp-td rp-td--name">
                            {{ item.procedure_name || item.procedure_code }}
                          </td>
                          <td class="rp-td rp-td--muted">
                            {{ item.region || item.tooth_number || '-' }}
                          </td>
                          <td class="rp-td rp-td--muted rp-td--center">
                            {{ item.sessions_planned }}
                          </td>
                          <td class="rp-td rp-td--muted rp-td--right">
                            {{ formatCurrency(item.unit_price) }}
                          </td>
                          <td class="rp-td rp-td--strong rp-td--right">
                            {{
                              formatCurrency(
                                (item.unit_price || 0) *
                                  (item.sessions_planned || 1)
                              )
                            }}
                          </td>
                          <td class="rp-td rp-td--center hide-on-print">
                            <span
                              class="rp-status"
                              :class="
                                item.status === 'aprovado' ||
                                item.status === 'approved'
                                  ? 'rp-status--green'
                                  : 'rp-status--blue'
                              "
                            >
                              {{
                                item.status === 'aprovado' ||
                                item.status === 'approved'
                                  ? 'Aprovado'
                                  : 'Proposto'
                              }}
                            </span>
                          </td>
                          <td
                            v-if="plan.status === 'proposto'"
                            class="rp-td rp-td--right hide-on-print"
                          >
                            <div class="rp-row-actions">
                              <button
                                class="rp-icon-btn"
                                title="Editar"
                                @click="openItemModal(plan, item)"
                              >
                                <i class="i-lucide-pencil" />
                              </button>
                              <button
                                class="rp-icon-btn rp-icon-btn--danger"
                                title="Remover"
                                @click="requestDeleteItem(plan.id, item.id)"
                              >
                                <i class="i-lucide-trash" />
                              </button>
                            </div>
                          </td>
                        </tr>
                      </tbody>
                    </table>

                    <!-- Total estimado -->
                    <div
                      v-if="
                        plan.treatment_items && plan.treatment_items.length > 0
                      "
                      class="rp-total"
                    >
                      <span class="rp-total-label">Total Estimado</span>
                      <span class="rp-total-value">{{
                        formatCurrency(
                          plan.treatment_items.reduce(
                            (sum, item) =>
                              sum +
                              (item.unit_price || 0) *
                                (item.sessions_planned || 1),
                            0
                          )
                        )
                      }}</span>
                    </div>
                  </div>
                </div>

                <!-- Observações e Previsão -->
                <div class="rp-section">
                  <div class="rp-section-label">
                    <i
                      class="i-lucide-calendar-clock rp-section-icon rp-section-icon--purple"
                    />
                    Observações e Previsão
                  </div>
                  <div class="rp-section-body rp-diag-grid">
                    <div class="rp-diag-item">
                      <span class="rp-diag-label">Previsão de Conclusão</span>
                      <template v-if="editingPlanId === plan.id">
                        <input
                          v-model="plan.estimated_duration"
                          type="text"
                          class="rp-field-input rp-field-input--sm"
                          placeholder="Ex: Aprox. 45 dias"
                        />
                      </template>
                      <p v-else class="rp-diag-value">
                        {{ plan.estimated_duration || 'Não informada' }}
                      </p>
                    </div>
                    <div class="rp-diag-item">
                      <span class="rp-diag-label"
                        >Profissional Responsável</span
                      >
                      <p class="rp-diag-value">
                        {{ plan.professional_name || 'Profissional da Conta' }}
                      </p>
                    </div>
                  </div>

                  <!-- Rodapé do plano -->
                  <div class="rp-plan-footer">
                    <div class="rp-approval-info">
                      <i
                        class="i-lucide-shield-check rp-approval-icon"
                        :class="
                          plan.status === 'aprovado' ||
                          plan.status === 'approved'
                            ? 'rp-approval-icon--green'
                            : 'rp-approval-icon--muted'
                        "
                      />
                      <span>{{
                        plan.status === 'aprovado' || plan.status === 'approved'
                          ? 'Plano aprovado em ' +
                            formatDate(plan.approved_at || new Date())
                          : 'Plano pendente de aprovação.'
                      }}</span>
                    </div>
                    <div class="hide-on-print">
                      <a
                        v-if="plan.pdf_url"
                        :href="plan.pdf_url"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="rp-action-btn"
                      >
                        <i class="i-lucide-file-text rp-action-btn-icon" />
                        Visualizar PDF
                      </a>
                      <button
                        v-else
                        class="rp-action-btn"
                        @click="printPlan(plan)"
                      >
                        <i class="i-lucide-printer rp-action-btn-icon" />
                        Imprimir Plano
                      </button>
                    </div>
                  </div>
                </div>
              </div>
              <!-- fim v-for planos -->
            </div>
          </div>

          <!-- ABA: PROCEDIMENTOS / SESSÕES -->
          <div v-else-if="activeTab === 'procedures'" class="tab-pane fade-in">
            <!-- Header padrão STYLE.md -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Procedimentos e Sessões
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Registro detalhado de aplicações, produtos utilizados e
                  sessões clínicas.
                </p>
              </div>
              <div class="flex items-center gap-3" style="position: relative">
                <button class="geral-header-btn" @click="toggleFilterPanel">
                  <i class="i-lucide-sliders-horizontal w-4 h-4" />
                  Filtrar
                </button>
                <button
                  class="btn-primary flex items-center gap-2"
                  @click="registerSession"
                >
                  <i class="i-lucide-plus w-4 h-4" />
                  Registrar Sessão
                </button>

                <!-- Painel de Filtro dropdown (Atualizado) -->
                <div v-if="showFilterPanel" class="proc-filter-panel">
                  <div class="flex items-center justify-between mb-4">
                    <h5
                      class="text-sm font-semibold"
                      style="color: rgb(var(--slate-12))"
                    >
                      Filtrar Histórico
                    </h5>
                    <button
                      class="proc-filter-close"
                      @click="showFilterPanel = false"
                    >
                      <i class="i-lucide-x w-3.5 h-3.5" />
                    </button>
                  </div>
                  <div class="flex flex-col gap-3">
                    <div class="proc-filter-group">
                      <label class="proc-filter-label">Procedimento</label>
                      <select
                        v-model="sessionHistoryFilter.procedure_name"
                        class="proc-filter-input"
                      >
                        <option value="">Todos os procedimentos</option>
                        <option
                          v-for="proc in uniqueProceduresLogged"
                          :key="proc"
                          :value="proc"
                        >
                          {{ proc }}
                        </option>
                      </select>
                    </div>
                    <div class="proc-filter-date-grid">
                      <div class="proc-filter-group">
                        <label class="proc-filter-label">Data Inicial</label>
                        <input
                          v-model="sessionHistoryFilter.date_from"
                          type="date"
                          class="proc-filter-input"
                        />
                      </div>
                      <div class="proc-filter-group">
                        <label class="proc-filter-label">Data Final</label>
                        <input
                          v-model="sessionHistoryFilter.date_to"
                          type="date"
                          class="proc-filter-input"
                        />
                      </div>
                    </div>
                    <div class="proc-filter-actions">
                      <button
                        class="proc-filter-btn proc-filter-btn--secondary"
                        @click="clearSessionFilter"
                      >
                        Limpar
                      </button>
                      <button
                        class="proc-filter-btn proc-filter-btn--primary"
                        @click="applySessionFilter"
                      >
                        Aplicar
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- reg-form-grid: Formulário + Histórico como reg-sections -->
            <div class="reg-form-grid">
              <!-- Formulário: Registrar Novo Procedimento -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-cyan">
                      <i class="i-lucide-syringe w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Registrar Novo Procedimento</span
                      >
                      <span class="reg-section-subtitle"
                        >Preencha os campos abaixo e salve a sessão
                        clínica</span
                      >
                    </div>
                  </div>
                  <div class="flex items-center gap-3">
                    <span class="text-xs text-slate-500">Data da sessão:</span>
                    <input
                      v-model="newSession.performed_at"
                      type="date"
                      class="form-input proc-date-input"
                    />
                  </div>
                </div>

                <div class="reg-section-body">
                  <!-- Linha 1: Procedimento + Área + Retorno -->
                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label class="form-label"
                        >Procedimento Realizado
                        <span class="reg-required">*</span></label
                      >
                      <input
                        v-model="newSession.procedure_name"
                        type="text"
                        class="form-input"
                        placeholder="Ex: Aplicação de Toxina Botulínica"
                      />
                    </div>
                    <div class="form-group">
                      <label class="form-label">Área Tratada</label>
                      <input
                        v-model="newSession.area_treated"
                        type="text"
                        class="form-input"
                        placeholder="Ex: Terço superior da face"
                      />
                    </div>
                    <div class="form-group">
                      <label class="form-label">Retorno em (Dias)</label>
                      <input
                        v-model="newSession.return_in_days"
                        type="number"
                        class="form-input"
                        placeholder="Ex: 15, 30"
                        min="1"
                      />
                    </div>
                  </div>

                  <!-- Linha 2: Produto + Quantidade + Lote -->
                  <div class="reg-field-grid-3">
                    <div class="form-group">
                      <label class="form-label">Produto Utilizado</label>
                      <input
                        v-model="newSession.product_name"
                        type="text"
                        class="form-input"
                        placeholder="Ex: Botox (Allergan)"
                      />
                    </div>
                    <div class="form-group">
                      <label class="form-label">Quantidade / Dose</label>
                      <input
                        v-model="newSession.quantity"
                        type="text"
                        class="form-input"
                        placeholder="Ex: 50U"
                      />
                    </div>
                    <div class="form-group">
                      <label class="form-label">Lote / Validade</label>
                      <input
                        v-model="newSession.batch"
                        type="text"
                        class="form-input"
                        placeholder="Ex: ABC1234 | 10/2026"
                      />
                    </div>
                  </div>

                  <!-- Linha 3: Intercorrências + Resultado -->
                  <div class="reg-field-grid-2">
                    <div class="form-group">
                      <label class="form-label"
                        >Intercorrências no Procedimento</label
                      >
                      <textarea
                        v-model="newSession.complications"
                        class="form-input form-textarea"
                        rows="3"
                        placeholder="Relato de hematomas, dor além do esperado, etc..."
                      />
                    </div>
                    <div class="form-group">
                      <label class="form-label"
                        >Resultado Imediato Observado</label
                      >
                      <textarea
                        v-model="newSession.result_observed"
                        class="form-input form-textarea"
                        rows="3"
                        placeholder="Paciente tolerou bem, assimetria corrigida..."
                      />
                    </div>
                  </div>

                  <!-- Ações do formulário -->
                  <div class="proc-form-actions">
                    <button
                      class="geral-header-btn"
                      @click="openBeforeAfterPhotos"
                    >
                      <i class="i-lucide-image w-4 h-4" />
                      Fotos Antes/Depois
                    </button>
                    <button
                      class="btn-primary flex items-center gap-2"
                      :disabled="isSavingSession"
                      @click="saveSession"
                    >
                      <i
                        v-if="isSavingSession"
                        class="i-lucide-loader-2 w-4 h-4 animate-spin"
                      />
                      <i v-else class="i-lucide-save w-4 h-4" />
                      {{
                        isSavingSession ? 'Salvando...' : 'Salvar Procedimento'
                      }}
                    </button>
                  </div>
                </div>
              </div>

              <!-- Histórico de Sessões -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-purple">
                      <i class="i-lucide-history w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Histórico de Sessões</span
                      >
                      <span class="reg-section-subtitle"
                        >Todas as sessões clínicas registradas para este
                        paciente</span
                      >
                    </div>
                  </div>
                  <div class="flex items-center gap-2">
                    <span
                      v-if="isSessionsLoading"
                      class="text-xs text-slate-500 flex items-center gap-1.5"
                    >
                      <i class="i-lucide-loader-2 w-3.5 h-3.5 animate-spin" />
                      Carregando...
                    </span>
                    <span class="proc-count-badge">{{
                      sessionLogs.length
                    }}</span>
                  </div>
                </div>

                <!-- Estado vazio -->
                <div
                  v-if="!sessionLogs || sessionLogs.length === 0"
                  class="proc-empty-state"
                >
                  <div class="proc-empty-icon">
                    <i class="i-lucide-clipboard-x w-5 h-5" />
                  </div>
                  <p class="proc-empty-text">
                    Nenhuma sessão registrada ainda.
                  </p>
                  <p class="proc-empty-hint">
                    Use o formulário acima para registrar a primeira sessão
                    clínica.
                  </p>
                </div>

                <!-- Tabela de sessões -->
                <div v-else class="proc-table-wrap">
                  <table class="proc-table">
                    <thead>
                      <tr class="proc-table-head">
                        <th>Data / Profissional</th>
                        <th>Procedimento / Área</th>
                        <th>Produto / Lote</th>
                        <th>Resultado / Intercorrências</th>
                        <th class="text-right">Ações</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="log in sessionLogs"
                        :key="log.id"
                        class="proc-table-row"
                      >
                        <td class="proc-table-cell">
                          <div class="proc-cell-primary">
                            {{
                              new Date(
                                log.performed_at || log.created_at
                              ).toLocaleDateString('pt-BR', { timeZone: BRT })
                            }}
                          </div>
                          <div class="proc-cell-secondary">
                            {{
                              log.professional_name ||
                              patient.responsibleProfessional ||
                              '—'
                            }}
                          </div>
                        </td>

                        <td class="proc-table-cell">
                          <div class="proc-cell-primary">
                            {{
                              log.procedure_name ||
                              log.treatment_plan_title ||
                              'Procedimento'
                            }}
                          </div>
                          <div
                            v-if="log.areas_treated && log.areas_treated.length"
                            class="proc-cell-secondary flex items-center gap-1 mt-0.5"
                          >
                            <i class="i-lucide-map-pin w-3 h-3 shrink-0" />
                            <span>{{
                              log.areas_treated
                                .map(a => a.region || a.description)
                                .filter(Boolean)
                                .join(', ')
                            }}</span>
                          </div>
                        </td>

                        <td class="proc-table-cell">
                          <template
                            v-if="log.products_used && log.products_used.length"
                          >
                            <div
                              v-for="(prod, idx) in log.products_used"
                              :key="idx"
                              class="proc-product-item"
                            >
                              <div class="proc-cell-primary">
                                {{ prod.name }}
                              </div>
                              <div
                                class="proc-cell-secondary flex gap-3 mt-0.5"
                              >
                                <span
                                  v-if="prod.quantity"
                                  class="flex items-center gap-1"
                                >
                                  <i class="i-lucide-box w-3 h-3" />
                                  {{ prod.quantity
                                  }}{{ prod.unit ? ' ' + prod.unit : '' }}
                                </span>
                                <span
                                  v-if="prod.batch"
                                  class="flex items-center gap-1"
                                >
                                  <i class="i-lucide-barcode w-3 h-3" />
                                  {{ prod.batch }}
                                </span>
                              </div>
                            </div>
                          </template>
                          <span v-else class="text-slate-600 text-xs">—</span>
                        </td>

                        <td class="proc-table-cell proc-cell-resultado">
                          <div
                            v-if="log.result_observed"
                            class="proc-result-row"
                          >
                            <i
                              class="i-lucide-check-circle w-3.5 h-3.5 shrink-0"
                            />
                            <span>{{ log.result_observed }}</span>
                          </div>
                          <div v-if="log.complications" class="proc-result-row">
                            <i
                              class="i-lucide-alert-triangle w-3.5 h-3.5 shrink-0"
                            />
                            <span>{{ log.complications }}</span>
                          </div>
                          <div
                            v-if="log.return_in_days"
                            class="proc-result-row"
                          >
                            <i
                              class="i-lucide-calendar-clock w-3.5 h-3.5 shrink-0"
                            />
                            <span
                              >Retorno em {{ log.return_in_days }} dias</span
                            >
                          </div>
                          <span
                            v-if="
                              !log.result_observed &&
                              !log.complications &&
                              !log.return_needed &&
                              !log.return_in_days
                            "
                            class="text-slate-600 text-xs"
                            >—</span
                          >
                        </td>

                        <td class="proc-table-cell text-right">
                          <button
                            class="proc-action-btn"
                            title="Remover"
                            @click="requestDeleteSessionLog(log.id)"
                          >
                            <i class="i-lucide-trash-2 w-3.5 h-3.5" />
                          </button>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <div class="page-footer-spacer" />
          </div>

          <!-- ABA: EXAMES E IMAGENS -->
          <div v-else-if="activeTab === 'exams'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Exames e Imagens
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Galeria clínica, exames laboratoriais e radiografias com
                  suporte a PDF e imagens.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <input
                  ref="mediaFileInput"
                  type="file"
                  class="hidden"
                  accept="image/*,application/pdf,video/mp4,video/webm,video/quicktime,video/x-msvideo"
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
              <template
                v-for="part in getFolderPath(activeFolderId)"
                :key="part.id"
              >
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
                <span class="text-slate-300 font-medium"
                  >Todos os arquivos</span
                >
              </template>
              <span class="exams-breadcrumb-count"
                >({{ mediasInFolder.length }} arquivo(s))</span
              >
              <span
                v-if="draggedMediaId || draggedFolderId"
                class="exams-drag-hint"
              >
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
                        :class="
                          expandedFolderIds.has(folder.id) ? 'rotate-90' : ''
                        "
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
                            {{
                              examMedias.filter(m => m.folder_id === sub.id)
                                .length
                            }}
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
                  <p class="text-xs text-slate-600 italic">
                    Nenhuma pasta criada
                  </p>
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
                <div
                  v-if="mediasInFolder.length === 0"
                  class="exams-empty-state"
                >
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
                      <i
                        v-else
                        class="i-lucide-image text-slate-600 text-4xl"
                      />

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
                        <span class="exams-card-category">{{
                          media.category
                        }}</span>
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
                            'opacity-40 cursor-not-allowed':
                              mediaLockMap[media.id],
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
                class="record-modal-box rounded-2xl shadow-xl w-full max-w-sm p-6 border"
              >
                <h3
                  class="record-modal-title text-lg font-semibold mb-4 flex items-center gap-2"
                >
                  <i class="i-lucide-pencil text-blue-400" /> Renomear Pasta
                </h3>
                <label class="record-modal-label text-xs font-medium mb-1 block">Nome</label
                >
                <input
                  v-model="renamingFolderName"
                  class="record-modal-input w-full rounded-xl px-4 py-2.5 text-sm focus:outline-none mb-4 border"
                  placeholder="Nome da pasta..."
                  autofocus
                  @keyup.enter="confirmRenameFolder"
                />
                <label class="record-modal-label text-xs font-medium mb-2 block">Cor da pasta</label
                >
                <div class="flex flex-wrap gap-2 mb-5">
                  <button
                    v-for="color in FOLDER_COLORS"
                    :key="color.value"
                    class="w-7 h-7 rounded-full border-2 transition-all hover:scale-110 focus:outline-none"
                    :style="{
                      backgroundColor: color.value,
                      borderColor:
                        renamingFolderColor === color.value
                          ? '#fff'
                          : 'transparent',
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

                <!-- Normal delete -->
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
                  <h3 class="text-lg font-semibold text-slate-100">
                    Excluir Arquivo
                  </h3>
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
          <!-- ABA: DOCUMENTOS -->
          <div v-else-if="activeTab === 'documents'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">Documentos</h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Receitas, atestados, pedidos de exame, encaminhamentos e
                  outros documentos clínicos.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <button
                  class="btn-primary flex items-center gap-2"
                  @click="openDocModal"
                >
                  <i class="i-lucide-file-plus w-4 h-4" /> Gerar Documento
                </button>
              </div>
            </div>

            <!-- Tabela de Documentos -->
            <div class="reg-section">
              <!-- Header da seção -->
              <div class="reg-section-toggle" style="cursor: default">
                <div class="reg-section-toggle-left">
                  <div class="reg-section-icon reg-icon-purple">
                    <i class="i-lucide-file-text w-4 h-4" />
                  </div>
                  <div>
                    <span class="reg-section-title">Documentos Gerados</span>
                    <span class="reg-section-subtitle"
                      >PDF gerados e disponíveis para download ou envio via
                      WhatsApp</span
                    >
                  </div>
                </div>
                <span class="proc-count-badge">{{
                  documents?.length || 0
                }}</span>
              </div>

              <!-- Empty state -->
              <div
                v-if="!documents || documents.length === 0"
                class="proc-empty-state"
              >
                <div class="proc-empty-icon">
                  <i class="i-lucide-file-x w-5 h-5" />
                </div>
                <p class="proc-empty-text">Nenhum documento gerado ainda.</p>
                <button
                  class="proc-empty-hint text-blue-400 cursor-pointer"
                  @click="openDocModal"
                >
                  Gerar primeiro documento →
                </button>
              </div>

              <!-- Tabela -->
              <div v-else class="proc-table-wrap">
                <table class="proc-table">
                  <thead>
                    <tr class="proc-table-head">
                      <th>Documento</th>
                      <th>Tipo</th>
                      <th>Data</th>
                      <th>Profissional</th>
                      <th>Status</th>
                      <th class="text-right">Ações</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      v-for="doc in documents"
                      :key="doc.id"
                      class="proc-table-row"
                    >
                      <!-- Nome -->
                      <td class="proc-table-cell">
                        <div class="flex items-center gap-3">
                          <div class="docs-file-icon">
                            <i class="i-lucide-file-text w-3.5 h-3.5" />
                          </div>
                          <div>
                            <p class="proc-cell-primary">
                              {{ doc.title || 'Documento' }}
                            </p>
                            <p class="proc-cell-secondary">
                              v{{ doc.version || 1 }}
                            </p>
                          </div>
                        </div>
                      </td>
                      <!-- Tipo -->
                      <td class="proc-table-cell">
                        <span class="proc-cell-secondary">
                          {{
                            DOC_TYPE_LABELS[doc.document_type] ||
                            doc.document_type ||
                            '—'
                          }}
                        </span>
                      </td>
                      <!-- Data -->
                      <td class="proc-table-cell">
                        <span class="proc-cell-secondary">{{
                          doc.created_at ? formatDate(doc.created_at) : '—'
                        }}</span>
                      </td>
                      <!-- Profissional -->
                      <td class="proc-table-cell">
                        <span class="proc-cell-secondary">{{
                          doc.generated_by?.name || 'Sistema'
                        }}</span>
                      </td>
                      <!-- Status -->
                      <td class="proc-table-cell">
                        <span
                          class="docs-status-badge"
                          :class="
                            (
                              DOC_STATUS_CONFIG[doc.status] ||
                              DOC_STATUS_CONFIG.gerado
                            ).cls
                          "
                        >
                          {{
                            (
                              DOC_STATUS_CONFIG[doc.status] ||
                              DOC_STATUS_CONFIG.gerado
                            ).label
                          }}
                        </span>
                      </td>
                      <!-- Ações -->
                      <td class="proc-table-cell text-right">
                        <div class="flex items-center justify-end gap-1">
                          <button
                            class="proc-action-btn"
                            title="Baixar documento"
                            @click="downloadDocument(doc)"
                          >
                            <i class="i-lucide-download w-3.5 h-3.5" />
                          </button>
                          <button
                            class="proc-action-btn docs-action-wa"
                            title="Enviar via WhatsApp"
                            @click="sendWhatsAppDocument(doc.id)"
                          >
                            <i class="i-lucide-message-circle w-3.5 h-3.5" />
                          </button>
                          <button
                            class="proc-action-btn"
                            title="Excluir documento"
                            @click="deleteDocument(doc.id)"
                          >
                            <i class="i-lucide-trash-2 w-3.5 h-3.5" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <!-- Modal: Gerar Documento -->
            <div
              v-if="showDocModal"
              class="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md"
              @click.self="showDocModal = false"
            >
              <div class="docs-modal">
                <!-- Header -->
                <div class="docs-modal-header">
                  <div class="flex items-center gap-3">
                    <div class="docs-modal-icon">
                      <i class="i-lucide-file-plus w-4 h-4" />
                    </div>
                    <div>
                      <h4 class="text-base font-semibold text-slate-100">
                        Gerar Documento Clínico
                      </h4>
                      <p class="text-xs text-slate-500 mt-0.5">
                        O PDF será gerado e baixado automaticamente.
                      </p>
                    </div>
                  </div>
                  <button
                    class="docs-modal-close"
                    @click="showDocModal = false"
                  >
                    <i class="i-lucide-x w-4 h-4" />
                  </button>
                </div>

                <!-- Body -->
                <div class="docs-modal-body">
                  <!-- Tipo de documento -->
                  <div class="form-group">
                    <label class="form-label"
                      >Tipo de Documento
                      <span class="reg-required">*</span></label
                    >
                    <select v-model="docForm.document_type" class="form-input">
                      <option
                        v-for="(label, key) in DOC_TYPE_LABELS"
                        :key="key"
                        :value="key"
                      >
                        {{ label }}
                      </option>
                    </select>
                  </div>

                  <!-- Título -->
                  <div class="form-group">
                    <label class="form-label"
                      >Título
                      <span class="text-slate-600">(opcional)</span></label
                    >
                    <input
                      v-model="docForm.title"
                      type="text"
                      :placeholder="DOC_TYPE_LABELS[docForm.document_type]"
                      class="form-input"
                    />
                  </div>

                  <!-- ATESTADO -->
                  <template v-if="docForm.document_type === 'atestado'">
                    <div class="reg-field-grid-2">
                      <div class="form-group">
                        <label class="form-label">CID</label>
                        <input
                          v-model="docForm.cid"
                          type="text"
                          placeholder="Ex: M54.5"
                          class="form-input"
                        />
                      </div>
                      <div class="form-group">
                        <label class="form-label">Dias de afastamento</label>
                        <input
                          v-model="docForm.dias_afastamento"
                          type="number"
                          min="1"
                          placeholder="Ex: 2"
                          class="form-input"
                        />
                      </div>
                    </div>
                  </template>

                  <!-- RECEITA -->
                  <template v-if="docForm.document_type === 'receita'">
                    <div class="form-group">
                      <label class="form-label">Medicamentos</label>
                      <textarea
                        v-model="docForm.medicamentos"
                        rows="3"
                        placeholder="Ex: Dipirona 500mg, Ibuprofeno 400mg..."
                        class="form-input"
                      />
                    </div>
                    <div class="form-group">
                      <label class="form-label">Posologia</label>
                      <textarea
                        v-model="docForm.posologia"
                        rows="2"
                        placeholder="Ex: Tomar 1 comprimido de 8 em 8 horas por 5 dias..."
                        class="form-input"
                      />
                    </div>
                  </template>

                  <!-- PEDIDO DE EXAME -->
                  <template v-if="docForm.document_type === 'pedido_exame'">
                    <div class="form-group">
                      <label class="form-label">Exames solicitados</label>
                      <textarea
                        v-model="docForm.exames_solicitados"
                        rows="3"
                        placeholder="Ex: Hemograma completo, Glicemia em jejum, TSH..."
                        class="form-input"
                      />
                    </div>
                  </template>

                  <!-- ENCAMINHAMENTO -->
                  <template v-if="docForm.document_type === 'encaminhamento'">
                    <div class="reg-field-grid-2">
                      <div class="form-group">
                        <label class="form-label">Encaminhar para</label>
                        <input
                          v-model="docForm.encaminhado_para"
                          type="text"
                          placeholder="Nome do especialista / clínica"
                          class="form-input"
                        />
                      </div>
                      <div class="form-group">
                        <label class="form-label">Especialidade</label>
                        <input
                          v-model="docForm.especialidade"
                          type="text"
                          placeholder="Ex: Ortopedia"
                          class="form-input"
                        />
                      </div>
                    </div>
                  </template>

                  <!-- CAMPOS LIVRES -->
                  <template
                    v-if="
                      [
                        'relatorio_clinico',
                        'declaracao',
                        'instrucao_procedimento',
                        'contrato',
                        'orcamento',
                        'questionario',
                        'outro',
                      ].includes(docForm.document_type)
                    "
                  >
                    <div class="form-group">
                      <label class="form-label">Conteúdo</label>
                      <textarea
                        v-model="docForm.conteudo_livre"
                        rows="5"
                        placeholder="Descreva o conteúdo do documento..."
                        class="form-input"
                      />
                    </div>
                  </template>

                  <!-- Observações -->
                  <div class="form-group">
                    <label class="form-label">Observações adicionais</label>
                    <textarea
                      v-model="docForm.observacoes"
                      rows="2"
                      placeholder="Informações complementares..."
                      class="form-input"
                    />
                  </div>
                </div>

                <!-- Footer -->
                <div class="docs-modal-footer">
                  <button class="btn-secondary" @click="showDocModal = false">
                    Cancelar
                  </button>
                  <button
                    class="btn-primary flex items-center gap-2"
                    :disabled="docModalLoading"
                    @click="generateDocument"
                  >
                    <i class="i-lucide-file-plus w-4 h-4" />
                    {{
                      docModalLoading ? 'Gerando PDF...' : 'Gerar e Baixar PDF'
                    }}
                  </button>
                </div>
              </div>
            </div>

            <!-- Modal: Confirmar Exclusão de Documento -->
            <div
              v-if="showDeleteDocModal"
              class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999]"
              style="background: rgba(0, 0, 0, 0.4)"
              @click.self="
                showDeleteDocModal = false;
                pendingDeleteDocId = null;
              "
            >
              <div
                class="delete-modal-card rounded-2xl w-full max-w-[420px] overflow-hidden"
                style="
                  background: rgb(var(--slate-1));
                  border: 1px solid rgb(var(--slate-4));
                  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.15);
                "
              >
                <div class="p-6">
                  <div class="flex items-start gap-4">
                    <div
                      class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
                    >
                      <i class="i-lucide-alert-triangle size-5 text-rose-500" />
                    </div>
                    <div class="flex flex-col gap-2 pt-1">
                      <h3
                        class="font-medium m-0 text-lg leading-tight"
                        style="color: rgb(var(--slate-12))"
                      >
                        Excluir Documento?
                      </h3>
                      <p
                        class="m-0 text-sm leading-relaxed"
                        style="color: rgb(var(--slate-10))"
                      >
                        Tem certeza que deseja excluir este documento? O arquivo
                        PDF será removido permanentemente. Esta ação não pode
                        ser desfeita.
                      </p>
                    </div>
                  </div>
                </div>
                <div
                  class="px-6 py-4 flex justify-end gap-3"
                  style="border-top: 1px solid rgb(var(--slate-4))"
                >
                  <button
                    class="rounded-lg px-4 py-2 text-sm font-medium cursor-pointer"
                    style="
                      background: transparent;
                      border: 1px solid #cbd5e1;
                      color: #475569;
                    "
                    onmouseover="this.style.backgroundColor='#f1f5f9'; this.style.borderColor='#94a3b8'; this.style.color='#334155'"
                    onmouseout="this.style.backgroundColor='transparent'; this.style.borderColor='#cbd5e1'; this.style.color='#475569'"
                    @click="
                      showDeleteDocModal = false;
                      pendingDeleteDocId = null;
                    "
                  >
                    Cancelar
                  </button>
                  <button
                    class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold border-0 cursor-pointer"
                    style="background: #ef4444; color: #ffffff"
                    onmouseover="this.style.backgroundColor='#dc2626'"
                    onmouseout="this.style.backgroundColor='#ef4444'"
                    @click="confirmDeleteDocument"
                  >
                    Excluir
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- ABA: CONSENTIMENTOS E ASSINATURAS -->
          <div v-else-if="activeTab === 'consents'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Consentimentos e Assinaturas
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Gestão jurídica de termos — LGPD, autorizações de imagem,
                  procedimentos estéticos e mais.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <button
                  class="btn-primary flex items-center gap-2"
                  :class="
                    showConsentModal
                      ? 'bg-slate-600 hover:bg-slate-500'
                      : 'bg-emerald-600 hover:bg-emerald-500'
                  "
                  @click="
                    showConsentModal
                      ? (showConsentModal = false)
                      : openConsentModal()
                  "
                >
                  <i
                    :class="
                      showConsentModal
                        ? 'i-lucide-x w-4 h-4'
                        : 'i-lucide-plus w-4 h-4'
                    "
                  />
                  {{ showConsentModal ? 'Cancelar' : 'Novo Consentimento' }}
                </button>
              </div>
            </div>

            <!-- KPIs de status -->
            <div class="consent-kpi-grid mb-5">
              <div class="consent-kpi-card">
                <div class="consent-kpi-icon consent-kpi-icon--neutral">
                  <i class="i-lucide-files w-4 h-4" />
                </div>
                <div>
                  <p class="consent-kpi-label">Total</p>
                  <p class="consent-kpi-value">{{ consentStats.total }}</p>
                </div>
              </div>
              <div class="consent-kpi-card consent-kpi-card--green">
                <div class="consent-kpi-icon consent-kpi-icon--green">
                  <i class="i-lucide-check-circle w-4 h-4" />
                </div>
                <div>
                  <p class="consent-kpi-label consent-kpi-label--green">
                    Assinados
                  </p>
                  <p class="consent-kpi-value consent-kpi-value--green">
                    {{ consentStats.signed }}
                  </p>
                </div>
              </div>
              <div class="consent-kpi-card consent-kpi-card--amber">
                <div class="consent-kpi-icon consent-kpi-icon--amber">
                  <i class="i-lucide-clock w-4 h-4" />
                </div>
                <div>
                  <p class="consent-kpi-label consent-kpi-label--amber">
                    Pendentes
                  </p>
                  <p class="consent-kpi-value consent-kpi-value--amber">
                    {{ consentStats.pending }}
                  </p>
                </div>
              </div>
              <div class="consent-kpi-card consent-kpi-card--red">
                <div class="consent-kpi-icon consent-kpi-icon--red">
                  <i class="i-lucide-alert-triangle w-4 h-4" />
                </div>
                <div>
                  <p class="consent-kpi-label consent-kpi-label--red">
                    Vencidos
                  </p>
                  <p class="consent-kpi-value consent-kpi-value--red">
                    {{ consentStats.expired }}
                  </p>
                </div>
              </div>
            </div>

            <!-- FORMULÁRIO INLINE: Novo Consentimento -->
            <div v-if="showConsentModal" class="reg-section mb-5">
              <div class="reg-section-toggle consent-form-header">
                <div class="reg-section-toggle-left">
                  <div class="reg-section-icon reg-icon-green">
                    <i class="i-lucide-plus-circle w-4 h-4" />
                  </div>
                  <div>
                    <span class="reg-section-title">Novo Consentimento</span>
                    <span class="reg-section-subtitle"
                      >Preencha os dados e o conteúdo do termo</span
                    >
                  </div>
                </div>
                <button
                  class="docs-modal-close"
                  title="Fechar"
                  @click="showConsentModal = false"
                >
                  <i class="i-lucide-x w-4 h-4" />
                </button>
              </div>

              <div class="reg-section-body">
                <!-- Linha 1: Tipo + Título + Validade -->
                <div class="grid grid-cols-12 gap-4">
                  <div class="col-span-4 form-group">
                    <label class="form-label"
                      >Tipo de Consentimento
                      <span class="reg-required">*</span></label
                    >
                    <select
                      v-model="newConsentForm.consent_type"
                      class="form-input"
                      @change="onConsentTypeChange"
                    >
                      <option value="" disabled>Selecione o tipo...</option>
                      <option
                        v-for="type in CONSENT_TYPES"
                        :key="type.value"
                        :value="type.value"
                      >
                        {{ type.label }}
                      </option>
                    </select>
                    <p
                      v-if="consentTypeDetail"
                      class="text-xs text-slate-500 mt-1.5 leading-snug"
                    >
                      {{ consentTypeDetail.description }}
                    </p>
                  </div>
                  <div class="col-span-5 form-group">
                    <label class="form-label">Título do Documento</label>
                    <input
                      v-model="newConsentForm.title"
                      type="text"
                      placeholder="Ex: Termo de Consentimento para Botox"
                      class="form-input"
                    />
                  </div>
                  <div class="col-span-3 form-group">
                    <label class="form-label">Validade</label>
                    <select
                      v-model="newConsentForm.expires_in_months"
                      class="form-input"
                    >
                      <option :value="1">1 mês</option>
                      <option :value="3">3 meses</option>
                      <option :value="6">6 meses</option>
                      <option :value="12">12 meses (1 ano)</option>
                      <option :value="24">24 meses (2 anos)</option>
                      <option :value="60">60 meses (5 anos)</option>
                      <option :value="0">Sem vencimento</option>
                    </select>
                  </div>
                </div>

                <!-- Observações -->
                <div class="form-group">
                  <label class="form-label"
                    >Observações Adicionais
                    <span class="text-slate-600">(opcional)</span></label
                  >
                  <input
                    v-model="newConsentForm.observations"
                    type="text"
                    placeholder="Ex: Aplicação na região frontal e glabela — sessão 1/3"
                    class="form-input"
                  />
                </div>

                <!-- Conteúdo do Termo -->
                <div class="form-group">
                  <div class="flex items-center justify-between mb-1.5">
                    <label class="form-label"
                      >Conteúdo do Termo
                      <span class="text-slate-600 font-normal ml-1"
                        >(editável — clique para personalizar)</span
                      >
                    </label>
                    <span
                      v-if="newConsentForm.body"
                      class="text-xs text-slate-600"
                    >
                      {{ newConsentForm.body.length }} caracteres
                    </span>
                  </div>
                  <textarea
                    v-model="newConsentForm.body"
                    rows="20"
                    placeholder="Selecione um tipo de consentimento acima para pré-preencher o template..."
                    class="form-input font-mono leading-relaxed resize-y"
                    style="min-height: 400px"
                  />
                </div>

                <!-- Ações -->
                <div
                  class="flex items-center justify-between pt-2 border-t border-white/5"
                >
                  <p class="text-xs text-slate-500 flex items-center gap-1.5">
                    <i class="i-lucide-info w-3 h-3" />
                    O consentimento será criado como
                    <strong class="text-amber-400">pendente</strong> até ser
                    assinado
                  </p>
                  <div class="flex gap-3">
                    <button
                      class="btn-secondary"
                      @click="showConsentModal = false"
                    >
                      Cancelar
                    </button>
                    <button
                      class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
                      :disabled="
                        consentModalLoading || !newConsentForm.consent_type
                      "
                      @click="createConsent"
                    >
                      <i
                        v-if="consentModalLoading"
                        class="i-lucide-loader-2 animate-spin w-4 h-4"
                      />
                      <i v-else class="i-lucide-file-plus w-4 h-4" />
                      {{
                        consentModalLoading
                          ? 'Criando...'
                          : 'Criar Consentimento'
                      }}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <!-- Loading state -->
            <div
              v-if="consentLoading"
              class="flex items-center justify-center py-16"
            >
              <div
                class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
              />
            </div>

            <!-- Empty state -->
            <div
              v-else-if="!consents || consents.length === 0"
              class="reg-section"
            >
              <div class="proc-empty-state">
                <div class="proc-empty-icon">
                  <i class="i-lucide-file-signature w-5 h-5" />
                </div>
                <p class="proc-empty-text">Nenhum consentimento registrado</p>
                <p class="proc-empty-hint">
                  Clique em "Novo Consentimento" para adicionar o primeiro termo
                </p>
              </div>
            </div>

            <!-- Tabela de Consentimentos -->
            <div v-else class="reg-section">
              <div class="reg-section-toggle consent-form-header">
                <div class="reg-section-toggle-left">
                  <div class="reg-section-icon reg-icon-purple">
                    <i class="i-lucide-file-signature w-4 h-4" />
                  </div>
                  <div>
                    <span class="reg-section-title">Termos Registrados</span>
                    <span class="reg-section-subtitle"
                      >Histórico de consentimentos do paciente</span
                    >
                  </div>
                </div>
                <span class="proc-count-badge">{{ consents.length }}</span>
              </div>

              <div class="proc-table-wrap">
                <table class="proc-table">
                  <thead>
                    <tr class="proc-table-head">
                      <th>Documento</th>
                      <th>Categoria</th>
                      <th>Validade</th>
                      <th>Status</th>
                      <th class="text-right">Ações</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      v-for="consent in consents"
                      :key="consent.id"
                      class="proc-table-row"
                    >
                      <!-- Documento -->
                      <td class="proc-table-cell">
                        <div class="flex items-center gap-3">
                          <div class="consent-doc-icon">
                            <i class="i-lucide-file-signature w-3.5 h-3.5" />
                          </div>
                          <div>
                            <p class="proc-cell-primary">
                              {{ consent.title || 'Termo de Consentimento' }}
                            </p>
                            <p class="proc-cell-secondary">
                              <i class="i-lucide-calendar w-2.5 h-2.5 mr-0.5" />
                              {{
                                consent.created_at
                                  ? formatDate(consent.created_at)
                                  : '—'
                              }}
                              <span
                                v-if="consent.version"
                                class="ml-2 text-slate-600"
                                >v{{ consent.version }}</span
                              >
                            </p>
                          </div>
                        </div>
                      </td>

                      <!-- Categoria -->
                      <td class="proc-table-cell">
                        <span class="proc-cell-secondary">{{
                          consentTypeLabel(consent.document_type)
                        }}</span>
                      </td>

                      <!-- Validade -->
                      <td class="proc-table-cell">
                        <span
                          v-if="consent.expires_at"
                          class="proc-cell-secondary flex items-center gap-1"
                        >
                          <i class="i-lucide-timer w-2.5 h-2.5" />
                          {{ formatDate(consent.expires_at) }}
                        </span>
                        <span v-else class="proc-cell-secondary">—</span>
                      </td>

                      <!-- Status -->
                      <td class="proc-table-cell">
                        <div class="flex flex-col gap-1 items-start">
                          <span
                            class="docs-status-badge"
                            :class="consentStatusLabel(consent.status).cls"
                          >
                            <i
                              :class="consentStatusLabel(consent.status).icon"
                              class="w-3 h-3 mr-1"
                            />
                            {{
                              consentStatusLabel(
                                consent.status
                              ).label.toUpperCase()
                            }}
                          </span>
                          <span
                            v-if="consent.integrity_hash"
                            class="text-[10px] text-slate-500 flex items-center gap-1"
                          >
                            <i class="i-lucide-fingerprint w-2.5 h-2.5" />
                            Hash: {{ consent.integrity_hash?.slice(0, 8) }}...
                          </span>
                          <span
                            v-if="consent.signed_at"
                            class="text-[10px] text-slate-500 flex items-center gap-1"
                          >
                            <i class="i-lucide-clock w-2.5 h-2.5" />
                            {{ formatDate(consent.signed_at) }}
                          </span>
                        </div>
                      </td>

                      <!-- Ações -->
                      <td class="proc-table-cell text-right">
                        <div class="consent-actions-group">
                          <button
                            class="consent-action-btn"
                            title="Visualizar termo"
                            @click="viewConsent(consent)"
                          >
                            <i class="i-lucide-eye w-3.5 h-3.5" />
                            <span>Ver</span>
                          </button>
                          <template
                            v-if="
                              ![
                                'signed',
                                'assinado_localmente',
                                'assinado_remotamente',
                                'revogado',
                              ].includes(consent.status)
                            "
                          >
                            <button
                              class="consent-action-btn consent-action-btn--blue"
                              title="Enviar link de assinatura por WhatsApp"
                              @click="sendConsentRemote(consent.id)"
                            >
                              <i class="i-lucide-smartphone w-3.5 h-3.5" />
                              <span>Enviar</span>
                            </button>
                            <button
                              class="consent-action-btn consent-action-btn--green"
                              title="Assinar presencialmente"
                              @click="signConsentNow(consent.id)"
                            >
                              <i class="i-lucide-pen-tool w-3.5 h-3.5" />
                              <span>Assinar</span>
                            </button>
                          </template>
                          <template
                            v-if="
                              [
                                'signed',
                                'assinado_localmente',
                                'assinado_remotamente',
                              ].includes(consent.status)
                            "
                          >
                            <button
                              class="consent-action-btn consent-action-btn--purple"
                              title="Ver integridade"
                              @click="viewConsent(consent)"
                            >
                              <i class="i-lucide-shield-check w-3.5 h-3.5" />
                              <span>Hash</span>
                            </button>
                            <button
                              class="consent-action-btn consent-action-btn--danger"
                              title="Revogar consentimento"
                              @click="revokeConsent(consent.id)"
                            >
                              <i class="i-lucide-x-circle w-3.5 h-3.5" />
                              <span>Revogar</span>
                            </button>
                          </template>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <!-- MODAL: Assinatura Digital -->
            <div
              v-if="showSignModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
              @click.self="showSignModal = false"
            >
              <div class="consent-sign-modal">
                <div class="docs-modal-header">
                  <div class="flex items-center gap-3">
                    <div class="consent-modal-icon consent-modal-icon--green">
                      <i class="i-lucide-pen-tool w-4 h-4" />
                    </div>
                    <div>
                      <h4 class="text-base font-semibold text-slate-100">
                        Assinatura Digital
                      </h4>
                      <p class="text-xs text-slate-500 mt-0.5">
                        Assine com o dedo ou mouse no campo abaixo
                      </p>
                    </div>
                  </div>
                  <button
                    class="docs-modal-close"
                    @click="showSignModal = false"
                  >
                    <i class="i-lucide-x w-4 h-4" />
                  </button>
                </div>

                <div class="docs-modal-body">
                  <!-- Canvas de assinatura -->
                  <div class="consent-canvas-wrap">
                    <canvas
                      ref="signatureCanvas"
                      width="600"
                      height="200"
                      class="consent-canvas"
                      @mousedown="startDrawing"
                      @mousemove="draw"
                      @mouseup="stopDrawing"
                      @mouseleave="stopDrawing"
                      @touchstart.prevent="startDrawing"
                      @touchmove.prevent="draw"
                      @touchend="stopDrawing"
                    />
                    <div v-if="!hasSignature" class="consent-canvas-hint">
                      <i class="i-lucide-pen-line w-5 h-5 mb-1" />
                      <p>Assine aqui</p>
                    </div>
                  </div>

                  <div class="consent-canvas-footer">
                    <button class="consent-clear-btn" @click="clearSignature">
                      <i class="i-lucide-rotate-ccw w-3 h-3" /> Limpar
                    </button>
                    <p class="consent-hash-hint">
                      <i class="i-lucide-shield w-3 h-3" />
                      Hash SHA-256 gerado automaticamente
                    </p>
                  </div>
                </div>

                <div class="docs-modal-footer">
                  <button class="btn-secondary" @click="showSignModal = false">
                    Cancelar
                  </button>
                  <button
                    class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2 disabled:opacity-50"
                    :disabled="consentModalLoading || !hasSignature"
                    @click="confirmSign"
                  >
                    <i
                      v-if="consentModalLoading"
                      class="i-lucide-loader-2 animate-spin w-4 h-4"
                    />
                    <i v-else class="i-lucide-check-circle w-4 h-4" />
                    Confirmar Assinatura
                  </button>
                </div>
              </div>
            </div>

            <!-- MODAL: Visualizar Consentimento -->
            <div
              v-if="showViewModal && consentInView"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md"
              @click.self="showViewModal = false"
            >
              <div class="consent-view-modal">
                <div class="docs-modal-header">
                  <div class="flex items-center gap-3">
                    <div class="consent-modal-icon consent-modal-icon--purple">
                      <i class="i-lucide-file-signature w-4 h-4" />
                    </div>
                    <div>
                      <h4 class="text-base font-semibold text-slate-100">
                        {{ consentInView.title || 'Termo de Consentimento' }}
                      </h4>
                      <div class="flex items-center gap-3 mt-0.5">
                        <span
                          class="docs-status-badge"
                          :class="consentStatusLabel(consentInView.status).cls"
                        >
                          {{ consentStatusLabel(consentInView.status).label }}
                        </span>
                        <span class="text-xs text-slate-500">{{
                          formatDate(consentInView.created_at)
                        }}</span>
                      </div>
                    </div>
                  </div>
                  <button
                    class="docs-modal-close"
                    @click="showViewModal = false"
                  >
                    <i class="i-lucide-x w-4 h-4" />
                  </button>
                </div>

                <div class="docs-modal-body">
                  <!-- Conteúdo do termo -->
                  <div class="consent-view-body">
                    <p class="consent-view-text">
                      {{ consentInView.body || '(Conteúdo não disponível)' }}
                    </p>
                  </div>

                  <!-- Dados de auditoria -->
                  <div
                    v-if="
                      [
                        'signed',
                        'assinado_localmente',
                        'assinado_remotamente',
                      ].includes(consentInView.status)
                    "
                    class="consent-audit-block"
                  >
                    <p class="consent-audit-title">Auditoria Forense</p>
                    <div class="consent-audit-row consent-audit-row--green">
                      <i class="i-lucide-check-circle w-3.5 h-3.5" />
                      Assinado em {{ formatDate(consentInView.signed_at) }}
                    </div>
                    <div
                      v-if="consentInView.integrity_hash"
                      class="consent-audit-row"
                    >
                      <i
                        class="i-lucide-fingerprint w-3.5 h-3.5 flex-shrink-0 mt-0.5"
                      />
                      <span class="font-mono break-all">{{
                        consentInView.integrity_hash
                      }}</span>
                    </div>
                    <div
                      v-if="consentInView.signed_ip"
                      class="consent-audit-row consent-audit-row--muted"
                    >
                      <i class="i-lucide-map-pin w-3.5 h-3.5" />
                      IP: {{ consentInView.signed_ip }}
                    </div>

                    <!-- Assinatura visual -->
                    <div
                      v-if="
                        consentInView.signature_image_url ||
                        consentInView.signature_blob
                      "
                      class="consent-sig-preview"
                    >
                      <p class="consent-sig-label">Assinatura registrada:</p>
                      <div class="consent-sig-frame">
                        <img
                          :src="
                            consentInView.signature_image_url ||
                            consentInView.signature_blob
                          "
                          alt="Assinatura"
                          class="consent-sig-img"
                        />
                      </div>
                    </div>
                  </div>
                </div>

                <div class="docs-modal-footer">
                  <button
                    v-if="
                      ![
                        'signed',
                        'assinado_localmente',
                        'assinado_remotamente',
                        'revogado',
                      ].includes(consentInView.status)
                    "
                    class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2"
                    @click="
                      signConsentNow(consentInView.id);
                      showViewModal = false;
                    "
                  >
                    <i class="i-lucide-pen-tool w-4 h-4" /> Assinar Agora
                  </button>
                  <button class="btn-secondary" @click="showViewModal = false">
                    Fechar
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- ABA: FINANCEIRO DO PACIENTE -->
          <div v-else-if="activeTab === 'financial'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Financeiro do Paciente
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Orçamentos, cobranças, parcelas e pagamentos vinculados ao
                  tratamento.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <button
                  v-can="['financial', 'create_estimate']"
                  class="geral-header-btn"
                  @click="openEstimateModal()"
                >
                  <i class="i-lucide-file-plus w-4 h-4" /> Novo Orçamento
                </button>
                <button
                  v-can="['financial', 'create_transaction']"
                  class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2"
                  @click="openPayModal(null)"
                >
                  <i class="i-lucide-receipt w-4 h-4" /> Receber Pagamento
                </button>
              </div>
            </div>

            <!-- KPIs financeiros -->
            <div class="fin-kpi-grid mb-5">
              <div class="fin-kpi-card">
                <div class="fin-kpi-icon">
                  <i class="i-lucide-trending-up w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Total Aprovado</p>
                <p class="fin-kpi-value">
                  {{ formatCurrency(financialSummary?.total_approved) }}
                </p>
                <p class="fin-kpi-hint">Plano principal</p>
              </div>
              <div class="fin-kpi-card fin-kpi-card--green">
                <div class="fin-kpi-icon fin-kpi-icon--green">
                  <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Pago / Recebido</p>
                <p class="fin-kpi-value">
                  {{ formatCurrency(financialSummary?.total_paid) }}
                </p>
                <p class="fin-kpi-hint">Atualizado</p>
              </div>
              <div class="fin-kpi-card fin-kpi-card--amber">
                <div class="fin-kpi-icon fin-kpi-icon--amber">
                  <i class="i-lucide-calendar-clock w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Em Aberto</p>
                <p class="fin-kpi-value">
                  {{ formatCurrency(financialSummary?.total_open) }}
                </p>
                <p class="fin-kpi-hint">
                  {{
                    financialSummary?.next_due_date
                      ? 'Próx: ' + formatDate(financialSummary.next_due_date)
                      : 'Sem pendências'
                  }}
                </p>
              </div>
              <div class="fin-kpi-card fin-kpi-card--red">
                <div class="fin-kpi-icon fin-kpi-icon--red">
                  <i class="i-lucide-alert-circle w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Devedor (Vencido)</p>
                <p
                  class="fin-kpi-value"
                  :class="{
                    'fin-kpi-value--danger':
                      financialSummary?.total_overdue > 0,
                  }"
                >
                  {{ formatCurrency(financialSummary?.total_overdue) }}
                </p>
                <p class="fin-kpi-hint">
                  {{
                    financialSummary?.total_overdue > 0
                      ? 'Exige atenção'
                      : 'Tudo em dia'
                  }}
                </p>
              </div>
              <div class="fin-kpi-card fin-kpi-card--blue">
                <div class="fin-kpi-icon fin-kpi-icon--blue">
                  <i class="i-lucide-wallet w-3.5 h-3.5" />
                </div>
                <p class="fin-kpi-label">Crédito</p>
                <p class="fin-kpi-value">
                  {{ formatCurrency(financialSummary?.credit_balance) }}
                </p>
                <p class="fin-kpi-hint">Saldo de estornos</p>
              </div>
            </div>

            <!-- Tabs internas + filtros -->
            <div class="fin-tabs-bar mb-4">
              <div class="fin-tabs-list">
                <button
                  class="fin-tab"
                  :class="
                    activeFinancialTab === 'transactions'
                      ? 'fin-tab--active'
                      : ''
                  "
                  @click="activeFinancialTab = 'transactions'"
                >
                  <i class="i-lucide-list w-3.5 h-3.5" /> Transações
                </button>
                <button
                  class="fin-tab"
                  :class="
                    activeFinancialTab === 'estimates' ? 'fin-tab--active' : ''
                  "
                  @click="activeFinancialTab = 'estimates'"
                >
                  <i class="i-lucide-file-text w-3.5 h-3.5" /> Orçamentos
                  <span
                    v-if="financialEstimates.length"
                    class="fin-tab-badge"
                    >{{ financialEstimates.length }}</span
                  >
                </button>
                <button
                  class="fin-tab"
                  :class="
                    activeFinancialTab === 'receipts' ? 'fin-tab--active' : ''
                  "
                  @click="activeFinancialTab = 'receipts'"
                >
                  <i class="i-lucide-receipt w-3.5 h-3.5" /> Recibos
                </button>
              </div>
              <div class="flex items-center gap-2">
                <div
                  v-if="activeFinancialTab === 'transactions'"
                  class="fin-filter-group"
                >
                  <button
                    v-for="f in [
                      { v: 'all', l: 'Todos' },
                      { v: 'pendente', l: 'Pendentes' },
                      { v: 'pago', l: 'Pagos' },
                      { v: 'vencido', l: 'Vencidos' },
                    ]"
                    :key="f.v"
                    class="fin-filter-btn"
                    :class="
                      financialFilter === f.v ? 'fin-filter-btn--active' : ''
                    "
                    @click="financialFilter = f.v"
                  >
                    {{ f.l }}
                  </button>
                </div>
                <button
                  class="fin-icon-btn"
                  title="Imprimir Extrato"
                  @click="printFinancial()"
                >
                  <i class="i-lucide-printer w-4 h-4" />
                </button>
              </div>
            </div>

            <!-- ABA TRANSAÇÕES -->
            <div v-if="activeFinancialTab === 'transactions'">
              <div
                v-if="financialLoading"
                class="flex items-center justify-center py-16"
              >
                <div
                  class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
                />
              </div>
              <div v-else class="reg-section">
                <div class="proc-table-wrap">
                  <table class="proc-table fin-tx-table">
                    <thead>
                      <tr class="proc-table-head">
                        <th>Vencimento</th>
                        <th>Descrição</th>
                        <th class="fin-tx-col-parcela">Parcela</th>
                        <th class="fin-tx-col-valor">Valor (R$)</th>
                        <th class="fin-tx-col-metodo">Método</th>
                        <th class="fin-tx-col-status">Status</th>
                        <th class="fin-tx-col-acoes">Ações</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr v-if="filteredTransactions.length === 0">
                        <td colspan="7" class="proc-table-cell">
                          <div class="proc-empty-state">
                            <div class="proc-empty-icon">
                              <i class="i-lucide-receipt-text w-5 h-5" />
                            </div>
                            <p class="proc-empty-text">
                              Nenhuma transação encontrada.
                            </p>
                          </div>
                        </td>
                      </tr>
                      <tr
                        v-for="tx in filteredTransactions"
                        :key="tx.id"
                        class="proc-table-row"
                      >
                        <td class="proc-table-cell">
                          <span
                            class="fin-tx-date"
                            :class="{
                              'fin-tx-date--overdue': tx.status === 'vencido',
                              'fin-tx-date--paid': tx.status === 'pago',
                            }"
                          >
                            {{ tx.due_date ? formatDate(tx.due_date) : '—' }}
                          </span>
                        </td>
                        <td class="proc-table-cell">
                          <p class="proc-cell-primary truncate max-w-[200px]">
                            {{ tx.description || 'Procedimento/Plano' }}
                          </p>
                          <p v-if="tx.paid_at" class="fin-tx-paid-at">
                            Pago em {{ formatDate(tx.paid_at) }}
                          </p>
                        </td>
                        <td
                          class="proc-table-cell fin-tx-col-parcela proc-cell-secondary"
                        >
                          {{ tx.installment_number || '1' }} /
                          {{ tx.total_installments || '1' }}
                        </td>
                        <td
                          class="proc-table-cell fin-tx-col-valor fin-tx-amount"
                          :class="
                            tx.transaction_type === 'despesa'
                              ? 'fin-tx-amount--expense'
                              : 'fin-tx-amount--income'
                          "
                        >
                          {{ formatCurrency(tx.amount) }}
                        </td>
                        <td class="proc-table-cell fin-tx-col-metodo">
                          <span
                            v-if="tx.payment_method"
                            class="fin-method-badge"
                          >
                            {{
                              {
                                pix: 'PIX',
                                cartao_credito: 'Crédito',
                                cartao_debito: 'Débito',
                                dinheiro: 'Dinheiro',
                                boleto: 'Boleto',
                                transferencia: 'Transf.',
                                outros: 'Outros',
                              }[tx.payment_method] || tx.payment_method
                            }}
                          </span>
                          <span v-else class="proc-cell-secondary">—</span>
                        </td>
                        <td class="proc-table-cell fin-tx-col-status">
                          <span
                            class="docs-status-badge"
                            :class="txStatusConfig(tx.status).cls"
                          >
                            <i
                              :class="txStatusConfig(tx.status).icon"
                              class="w-3 h-3 mr-1"
                            />
                            {{ txStatusConfig(tx.status).label }}
                          </span>
                        </td>
                        <td class="proc-table-cell text-right">
                          <div class="fin-tx-actions">
                            <template v-if="!tx.is_manual">
                              <button
                                v-if="
                                  tx.status === 'pendente' ||
                                  tx.status === 'vencido'
                                "
                                v-can="['financial', 'create_transaction']"
                                class="fin-action-btn fin-action-btn--green"
                                @click="openPayModal(tx.id)"
                              >
                                <i class="i-lucide-check w-3 h-3" /> Receber
                              </button>
                              <button
                                v-if="
                                  tx.status === 'pendente' ||
                                  tx.status === 'vencido'
                                "
                                class="fin-icon-btn"
                                title="Cobrar via WhatsApp"
                                @click="chargeWhatsapp(tx.id)"
                              >
                                <i class="i-lucide-message-circle w-4 h-4" />
                              </button>
                              <button
                                v-if="
                                  tx.status === 'pago' && tx.payment_proof_url
                                "
                                class="fin-icon-btn"
                                title="Ver comprovante"
                                @click="viewProof(tx)"
                              >
                                <i class="i-ph-file-text w-4 h-4" />
                              </button>
                              <button
                                v-if="
                                  tx.status === 'pago' && !tx.payment_proof_url
                                "
                                class="fin-icon-btn"
                                title="Anexar comprovante"
                                @click="openProofModal(tx.id)"
                              >
                                <i class="i-ph-upload-simple w-4 h-4" />
                              </button>
                              <button
                                v-if="tx.status === 'pago'"
                                v-can="['financial', 'delete_transaction']"
                                class="fin-icon-btn"
                                title="Estornar transação"
                                @click="refundTransaction(tx.id)"
                              >
                                <i class="i-lucide-undo w-4 h-4" />
                              </button>
                            </template>
                            <template v-else>
                              <span
                                class="inline-flex items-center gap-1 px-2 py-0.5 bg-blue-50 text-blue-600 text-[10px] font-bold uppercase tracking-wide rounded"
                              >
                                <i class="i-lucide-zap w-3 h-3" /> Manual
                              </span>
                            </template>
                          </div>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <!-- ABA ORÇAMENTOS -->
            <div v-else-if="activeFinancialTab === 'estimates'">
              <div
                v-if="financialLoading"
                class="flex items-center justify-center py-16"
              >
                <div
                  class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
                />
              </div>
              <div v-else class="flex flex-col gap-4">
                <div v-if="financialEstimates.length === 0" class="reg-section">
                  <div class="proc-empty-state">
                    <div class="proc-empty-icon">
                      <i class="i-lucide-file-text w-5 h-5" />
                    </div>
                    <p class="proc-empty-text">Nenhum orçamento encontrado.</p>
                    <p class="proc-empty-hint">
                      Clique em "Novo Orçamento" para criar.
                    </p>
                  </div>
                </div>
                <div
                  v-for="est in financialEstimates"
                  :key="est.id"
                  class="fin-estimate-card"
                >
                  <div class="fin-estimate-body">
                    <div class="fin-estimate-meta">
                      <span
                        class="docs-status-badge"
                        :class="estimateStatusConfig(est.status).cls"
                      >
                        {{ estimateStatusConfig(est.status).label }}
                      </span>
                      <span class="fin-estimate-id"
                        >Orçamento #{{ est.id }}</span
                      >
                      <span v-if="est.treatment_plan_id" class="fin-plan-badge">
                        <i class="i-lucide-link w-3 h-3" /> Plano de Tratamento
                      </span>
                    </div>

                    <div class="fin-estimate-values">
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Subtotal</p>
                        <p class="fin-estimate-value-amount">
                          {{ formatCurrency(est.subtotal) }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Desconto</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--red"
                        >
                          - {{ formatCurrency(est.discount_amount) }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Total</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--green fin-estimate-value-amount--lg"
                        >
                          {{ formatCurrency(est.total) }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Parcelas</p>
                        <p class="fin-estimate-value-amount">
                          {{ est.installments_count }}x de
                          {{ formatCurrency(est.installment_value) }}
                        </p>
                      </div>
                    </div>

                    <div class="fin-estimate-summary">
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Pago</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--green"
                        >
                          {{
                            formatCurrency(est.financial_summary?.total_paid)
                          }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Pendente</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--amber"
                        >
                          {{
                            formatCurrency(est.financial_summary?.total_pending)
                          }}
                        </p>
                      </div>
                      <div class="fin-estimate-value-item">
                        <p class="fin-estimate-value-label">Vencido</p>
                        <p
                          class="fin-estimate-value-amount fin-estimate-value-amount--red"
                        >
                          {{
                            formatCurrency(est.financial_summary?.total_overdue)
                          }}
                        </p>
                      </div>
                    </div>

                    <div v-if="est.notes" class="fin-estimate-notes">
                      {{ est.notes }}
                    </div>
                  </div>

                  <div class="fin-estimate-actions">
                    <div class="fin-estimate-dates">
                      <p>Criado em {{ formatDate(est.created_at) }}</p>
                      <p v-if="est.valid_until" class="fin-estimate-valid">
                        Válido até {{ formatDate(est.valid_until) }}
                      </p>
                    </div>
                    <div class="flex gap-2">
                      <button
                        v-if="
                          est.status === 'rascunho' || est.status === 'enviado'
                        "
                        v-can="['financial', 'approve_estimate']"
                        class="fin-action-btn fin-action-btn--green"
                        @click="approveEstimate(est.id)"
                      >
                        <i class="i-lucide-check-circle w-3.5 h-3.5" /> Aprovar
                      </button>
                      <button
                        v-if="
                          est.status !== 'cancelado' &&
                          est.status !== 'aprovado'
                        "
                        v-can="['financial', 'edit_estimate']"
                        class="fin-action-btn fin-action-btn--danger"
                        @click="cancelEstimate(est.id)"
                      >
                        <i class="i-lucide-x-circle w-3.5 h-3.5" /> Cancelar
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- ABA RECIBOS -->
            <div v-else-if="activeFinancialTab === 'receipts'">
              <div class="reg-section">
                <div class="proc-table-wrap">
                  <table class="proc-table">
                    <thead>
                      <tr class="proc-table-head">
                        <th>Data Pagamento</th>
                        <th>Descrição</th>
                        <th>Valor (R$)</th>
                        <th>Método</th>
                        <th class="text-right">Recibo</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-if="
                          transactions.filter(t => t.status === 'pago')
                            .length === 0
                        "
                      >
                        <td colspan="5" class="proc-table-cell">
                          <div class="proc-empty-state">
                            <div class="proc-empty-icon">
                              <i class="i-lucide-file-check w-5 h-5" />
                            </div>
                            <p class="proc-empty-text">
                              Nenhum pagamento confirmado ainda.
                            </p>
                          </div>
                        </td>
                      </tr>
                      <tr
                        v-for="tx in transactions.filter(
                          t => t.status === 'pago'
                        )"
                        :key="'r-' + tx.id"
                        class="proc-table-row fin-tx-row--paid"
                      >
                        <td
                          class="proc-table-cell proc-cell-secondary font-mono"
                        >
                          {{
                            tx.paid_at
                              ? formatDate(tx.paid_at)
                              : formatDate(tx.updated_at)
                          }}
                        </td>
                        <td class="proc-table-cell proc-cell-primary">
                          {{ tx.description || 'Pagamento' }}
                        </td>
                        <td
                          class="proc-table-cell fin-tx-amount fin-tx-amount--income"
                        >
                          {{ formatCurrency(tx.amount) }}
                        </td>
                        <td class="proc-table-cell">
                          <span class="fin-method-badge">
                            {{
                              {
                                pix: 'PIX',
                                cartao_credito: 'Crédito',
                                cartao_debito: 'Débito',
                                dinheiro: 'Dinheiro',
                                boleto: 'Boleto',
                                transferencia: 'Transf.',
                                outros: 'Outros',
                              }[tx.payment_method] || '—'
                            }}
                          </span>
                        </td>
                        <td class="proc-table-cell text-right">
                          <button
                            class="fin-action-btn fin-action-btn--green"
                            @click="printReceipt(tx)"
                          >
                            <i class="i-lucide-receipt w-3.5 h-3.5" /> Recibo
                          </button>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </div>
            </div>

            <!-- MODAL: Preview de Impressão -->
            <div
              v-if="showPrintModal"
              class="fixed inset-0 z-[60] flex items-center justify-center p-4 bg-black/80 backdrop-blur-sm"
              @click.self="showPrintModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-xl shadow-2xl w-full max-w-4xl h-[90vh] flex flex-col overflow-hidden relative"
              >
                <div
                  class="flex items-center justify-between px-4 py-3 border-b border-slate-700/50 flex-shrink-0"
                >
                  <h3
                    class="text-base font-semibold text-slate-100 flex items-center gap-2"
                  >
                    <i class="i-lucide-printer text-sky-400" /> {{ printTitle }}
                  </h3>
                  <div class="flex items-center gap-3">
                    <button
                      class="h-8 px-3 rounded-lg bg-white text-slate-900 font-semibold text-xs hover:bg-slate-100 flex items-center gap-2 transition-colors"
                      @click="$refs.previewIframe.contentWindow.print()"
                    >
                      <i class="i-lucide-printer" /> Imprimir / PDF
                    </button>
                    <button
                      class="p-1 rounded-lg hover:bg-slate-800 text-slate-400 transition-colors"
                      @click="showPrintModal = false"
                    >
                      <i class="i-lucide-x" />
                    </button>
                  </div>
                </div>
                <div class="flex-1 bg-slate-800 overflow-hidden relative">
                  <iframe
                    ref="previewIframe"
                    :srcdoc="printHtmlContent"
                    class="w-full h-full border-none bg-white block absolute inset-0"
                    title="Visualização de Impressão"
                  />
                </div>
              </div>
            </div>

            <!-- MODAL: Anexar Comprovante -->
            <div
              v-if="showProofModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
              @click.self="showProofModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
              >
                <div
                  class="flex items-center justify-between p-6 border-b border-slate-700/50"
                >
                  <div>
                    <h3
                      class="text-lg font-semibold text-slate-100 flex items-center gap-2"
                    >
                      <i class="i-lucide-paperclip text-sky-400" /> Anexar
                      Comprovante
                    </h3>
                    <p class="text-xs text-slate-400 mt-0.5">
                      Anexe o comprovante de pagamento (PIX, boleto, etc.)
                    </p>
                  </div>
                  <button
                    class="p-2 rounded-lg hover:bg-slate-800 text-slate-400"
                    @click="showProofModal = false"
                  >
                    <i class="i-lucide-x" />
                  </button>
                </div>
                <div class="p-6 space-y-4">
                  <div
                    v-if="proofTx"
                    class="bg-slate-800 rounded-xl p-4 space-y-1"
                  >
                    <p class="text-xs text-slate-400">Transação</p>
                    <p class="text-sm font-semibold text-slate-200">
                      {{ proofTx.description || 'Pagamento' }}
                    </p>
                    <p class="text-lg font-bold text-emerald-400">
                      {{ formatCurrency(proofTx.amount) }}
                    </p>
                  </div>
                  <label class="block">
                    <span class="text-sm text-slate-300 mb-2 block"
                      >Arquivo (imagem ou PDF)</span
                    >
                    <div
                      class="border-2 border-dashed border-slate-600 hover:border-sky-500 rounded-xl p-8 text-center cursor-pointer transition-colors relative"
                    >
                      <i
                        class="i-lucide-upload-cloud text-3xl text-slate-500 block mb-2"
                      />
                      <p class="text-sm text-slate-400">
                        Clique para selecionar ou arraste o arquivo
                      </p>
                      <p class="text-xs text-slate-600 mt-1">
                        PNG, JPG, PDF — máx. 10MB
                      </p>
                      <input
                        type="file"
                        accept="image/*,application/pdf"
                        class="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
                        :disabled="proofUploading"
                        @change="handleProofUpload"
                      />
                    </div>
                  </label>
                  <div
                    v-if="proofUploading"
                    class="flex items-center gap-2 text-sky-400 text-sm"
                  >
                    <i class="i-lucide-loader-2 animate-spin" /> Enviando
                    comprovante...
                  </div>
                </div>
              </div>
            </div>

            <!-- MODAL: Receber Pagamento -->

            <div
              v-if="showPayModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
              @click.self="showPayModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
              >
                <div
                  class="flex items-center justify-between p-6 border-b border-slate-700/50"
                >
                  <div>
                    <h3
                      class="text-lg font-semibold text-slate-100 flex items-center gap-2"
                    >
                      <i class="i-lucide-receipt text-emerald-400" /> Registrar
                      Pagamento
                    </h3>
                    <p class="text-xs text-slate-400 mt-0.5">
                      Confirme o método e data do pagamento
                    </p>
                  </div>
                  <button
                    class="text-slate-400 hover:text-slate-100"
                    @click="showPayModal = false"
                  >
                    <i class="i-lucide-x text-xl" />
                  </button>
                </div>
                <div class="p-6 space-y-4">
                  <!-- Seletor de parcela (quando aberto pelo botão do header) -->
                  <div v-if="selectedTxId === null">
                    <label class="block text-sm font-medium text-slate-300 mb-2"
                      >Selecionar Parcela *</label
                    >
                    <div
                      v-if="pendingTransactions.length === 0"
                      class="bg-slate-800/50 border border-slate-700 rounded-xl p-4 text-center text-slate-500 text-sm"
                    >
                      <i
                        class="i-lucide-check-circle-2 text-2xl mb-1 block text-emerald-400"
                      />
                      Nenhuma parcela pendente. Todas as parcelas estão pagas!
                    </div>
                    <div v-else class="space-y-2 max-h-48 overflow-y-auto">
                      <button
                        v-for="pt in pendingTransactions"
                        :key="pt.id"
                        class="w-full flex items-center justify-between p-3 rounded-xl border text-left transition-all"
                        :class="
                          selectedTxId === pt.id
                            ? 'bg-emerald-500/15 border-emerald-500/50'
                            : 'bg-slate-800/50 border-slate-700 hover:border-slate-600'
                        "
                        @click="selectedTxId = pt.id"
                      >
                        <div>
                          <p
                            class="text-sm font-medium text-slate-200 truncate max-w-[200px]"
                          >
                            {{ pt.description || 'Parcela' }}
                          </p>
                          <p class="text-xs text-slate-500 mt-0.5">
                            Venc:
                            {{ pt.due_date ? formatDate(pt.due_date) : '—' }} ·
                            Parcela {{ pt.installment_number }}/{{
                              pt.total_installments
                            }}
                          </p>
                        </div>
                        <div class="text-right shrink-0 ml-4">
                          <p class="font-mono font-semibold text-emerald-400">
                            {{ formatCurrency(pt.amount) }}
                          </p>
                          <span
                            class="text-[10px] font-medium px-1.5 py-0.5 rounded-full border"
                            :class="txStatusConfig(pt.status).cls"
                          >
                            {{ txStatusConfig(pt.status).label }}
                          </span>
                        </div>
                      </button>
                    </div>
                  </div>
                  <!-- Info da parcela já selecionada -->
                  <div
                    v-else
                    class="bg-emerald-500/10 border border-emerald-500/20 rounded-xl p-3 flex items-center justify-between"
                  >
                    <div>
                      <p class="text-xs text-emerald-400 font-medium">
                        Parcela selecionada
                      </p>
                      <p class="text-sm text-slate-200 mt-0.5">
                        {{
                          transactions.find(t => t.id === selectedTxId)
                            ?.description || 'Parcela'
                        }}
                      </p>
                    </div>
                    <button
                      class="text-slate-400 hover:text-red-400 text-xs"
                      @click="selectedTxId = null"
                    >
                      Trocar
                    </button>
                  </div>

                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Método de Pagamento *</label
                    >
                    <div class="grid grid-cols-3 gap-2">
                      <button
                        v-for="m in [
                          { v: 'pix', l: 'PIX', icon: 'i-lucide-qr-code' },
                          {
                            v: 'dinheiro',
                            l: 'Dinheiro',
                            icon: 'i-lucide-banknote',
                          },
                          {
                            v: 'cartao_credito',
                            l: 'Crédito',
                            icon: 'i-lucide-credit-card',
                          },
                          {
                            v: 'cartao_debito',
                            l: 'Débito',
                            icon: 'i-lucide-credit-card',
                          },
                          {
                            v: 'transferencia',
                            l: 'Transf.',
                            icon: 'i-lucide-arrow-right-left',
                          },
                          {
                            v: 'boleto',
                            l: 'Boleto',
                            icon: 'i-lucide-file-text',
                          },
                        ]"
                        :key="m.v"
                        class="flex flex-col items-center gap-1 p-2.5 rounded-xl border text-xs font-medium transition-all"
                        :class="
                          payForm.payment_method === m.v
                            ? 'bg-emerald-500/15 border-emerald-500/50 text-emerald-400'
                            : 'bg-slate-800/50 border-slate-700 text-slate-400 hover:border-slate-600 hover:text-slate-200'
                        "
                        @click="payForm.payment_method = m.v"
                      >
                        <i :class="m.icon" />
                        {{ m.l }}
                      </button>
                    </div>
                  </div>
                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Data do Pagamento</label
                    >
                    <input
                      v-model="payForm.paid_at"
                      type="date"
                      class="form-input w-full"
                    />
                  </div>
                  <!-- Conta de Destino -->
                  <div v-if="bankAccountsForPay.length">
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Conta de Destino</label>
                    <select
                      v-model="payForm.bank_account_id"
                      class="form-input w-full"
                    >
                      <option value="">— Selecionar conta —</option>
                      <option
                        v-for="ba in bankAccountsForPay"
                        :key="ba.id"
                        :value="ba.id"
                      >
                        {{ ba.bank_code ? `${ba.bank_code} · ` : ''
                        }}{{ ba.name
                        }}{{ ba.bank_name ? ` (${ba.bank_name})` : '' }}
                      </option>
                    </select>
                  </div>
                </div>
                <div
                  class="p-6 border-t border-slate-700/50 flex justify-end gap-3"
                >
                  <button class="btn-secondary" @click="showPayModal = false">
                    Cancelar
                  </button>
                  <button
                    class="btn-primary bg-emerald-600 hover:bg-emerald-500 text-white flex items-center gap-2 disabled:opacity-50"
                    :disabled="payModalLoading || !selectedTxId"
                    @click="confirmPayment()"
                  >
                    <i
                      v-if="payModalLoading"
                      class="i-lucide-loader-2 animate-spin"
                    />
                    <i v-else class="i-lucide-check" />
                    Confirmar Pagamento
                  </button>
                </div>
              </div>
            </div>

            <!-- MODAL: Novo Orçamento -->
            <div
              v-if="showEstimateModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
              @click.self="showEstimateModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-lg"
              >
                <div
                  class="flex items-center justify-between p-6 border-b border-slate-700/50"
                >
                  <div>
                    <h3
                      class="text-lg font-semibold text-slate-100 flex items-center gap-2"
                    >
                      <i class="i-lucide-file-plus text-blue-400" /> Novo
                      Orçamento
                    </h3>
                    <p class="text-xs text-slate-400 mt-0.5">
                      Crie um orçamento avulso para este paciente
                    </p>
                  </div>
                  <button
                    class="text-slate-400 hover:text-slate-100"
                    @click="showEstimateModal = false"
                  >
                    <i class="i-lucide-x text-xl" />
                  </button>
                </div>
                <div class="p-6 space-y-4">
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Subtotal (R$) *</label
                      >
                      <div class="relative">
                        <span
                          class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 text-sm font-medium z-10 pointer-events-none"
                          >R$</span
                        >
                        <input
                          :value="subtotalRaw"
                          type="text"
                          inputmode="numeric"
                          placeholder="0,00"
                          style="padding-left: 2.25rem !important"
                          class="form-input w-full font-mono"
                          @input="onSubtotalInput"
                        />
                      </div>
                    </div>
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Parcelas</label
                      >
                      <input
                        v-model="estimateForm.installments_count"
                        type="number"
                        min="1"
                        max="60"
                        class="form-input w-full"
                      />
                    </div>
                  </div>
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Tipo de Desconto</label
                      >
                      <select
                        v-model="estimateForm.discount_type"
                        class="form-input w-full"
                      >
                        <option value="fixo">Valor Fixo (R$)</option>
                        <option value="percentual">Percentual (%)</option>
                      </select>
                    </div>
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Valor Desconto</label
                      >
                      <input
                        v-model="estimateForm.discount_value"
                        type="number"
                        step="0.01"
                        min="0"
                        class="form-input w-full"
                      />
                    </div>
                  </div>
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >Método Padrão</label
                      >
                      <select
                        v-model="estimateForm.payment_method"
                        class="form-input w-full"
                      >
                        <option value="pix">PIX</option>
                        <option value="cartao_credito">
                          Cartão de Crédito
                        </option>
                        <option value="cartao_debito">Cartão de Débito</option>
                        <option value="dinheiro">Dinheiro</option>
                        <option value="boleto">Boleto</option>
                        <option value="transferencia">Transferência</option>
                        <option value="outros">Outros</option>
                      </select>
                    </div>
                    <div>
                      <label
                        class="block text-sm font-medium text-slate-300 mb-1.5"
                        >1º Vencimento</label
                      >
                      <input
                        v-model="estimateForm.valid_until"
                        type="date"
                        class="form-input w-full"
                      />
                    </div>
                  </div>
                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Observações</label
                    >
                    <textarea
                      v-model="estimateForm.notes"
                      rows="2"
                      placeholder="Observações sobre o orçamento..."
                      class="form-input w-full resize-none"
                    />
                  </div>
                  <!-- Preview do total -->
                  <div
                    v-if="subtotalRaw"
                    class="bg-slate-800/50 border border-slate-700/50 rounded-xl p-3 flex items-center justify-between"
                  >
                    <div class="text-xs text-slate-400">
                      <span
                        >Subtotal:
                        <strong class="text-slate-200"
                          >R$ {{ subtotalRaw }}</strong
                        ></span
                      >
                      <span
                        v-if="estimateForm.discount_value > 0"
                        class="ml-3 text-red-400"
                      >
                        - Desconto:
                        {{
                          estimateForm.discount_type === 'percentual'
                            ? estimateForm.discount_value + '%'
                            : 'R$ ' + estimateForm.discount_value
                        }}
                      </span>
                    </div>
                    <div class="text-right">
                      <p class="text-xs text-slate-400">
                        {{ estimateForm.installments_count }}x de
                      </p>
                      <p class="text-sm font-bold text-emerald-400 font-mono">
                        {{
                          formatCurrency(
                            parseCurrencyInput(subtotalRaw) /
                              (parseInt(estimateForm.installments_count) || 1)
                          )
                        }}
                      </p>
                    </div>
                  </div>
                </div>
                <div
                  class="p-6 border-t border-slate-700/50 flex justify-end gap-3"
                >
                  <button
                    class="btn-secondary"
                    @click="showEstimateModal = false"
                  >
                    Cancelar
                  </button>
                  <button
                    class="btn-primary bg-blue-600 hover:bg-blue-500 text-white flex items-center gap-2 disabled:opacity-50"
                    :disabled="estimateModalLoading || !subtotalRaw"
                    @click="confirmCreateEstimate()"
                  >
                    <i
                      v-if="estimateModalLoading"
                      class="i-lucide-loader-2 animate-spin"
                    />
                    <i v-else class="i-lucide-file-check" />
                    Criar Orçamento
                  </button>
                </div>
              </div>
            </div>
          </div>
          <!-- ABA: AGENDA E HISTÓRICO -->

          <div v-else-if="activeTab === 'schedule'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-6">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Agenda e Histórico
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Acompanhamento completo de agendamentos, faltas e retornos do
                  paciente.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <button
                  class="geral-header-btn"
                  @click="navigateToAgendaWithPatient"
                >
                  <i class="i-lucide-calendar w-4 h-4" /> Ver na Agenda
                </button>
                <button
                  class="btn-primary bg-woot-600 hover:bg-woot-500 text-white flex items-center gap-2"
                  @click="navigateToAgendaWithPatient"
                >
                  <i class="i-lucide-calendar-plus w-4 h-4" /> Novo Agendamento
                </button>
              </div>
            </div>

            <!-- KPIs -->
            <div class="sched-kpi-grid mb-6">
              <!-- Total -->
              <div class="sched-kpi-card">
                <div class="sched-kpi-icon">
                  <i class="i-lucide-calendar-days w-4 h-4" />
                </div>
                <p class="sched-kpi-label">Total</p>
                <p class="sched-kpi-value">{{ aptKPIs.total }}</p>
              </div>
              <!-- Realizados -->
              <div class="sched-kpi-card sched-kpi-card--green">
                <div class="sched-kpi-icon sched-kpi-icon--green">
                  <i class="i-lucide-check-circle-2 w-4 h-4" />
                </div>
                <p class="sched-kpi-label">Realizados</p>
                <p class="sched-kpi-value">{{ aptKPIs.done }}</p>
              </div>
              <!-- Próximos -->
              <div class="sched-kpi-card sched-kpi-card--blue">
                <div class="sched-kpi-icon sched-kpi-icon--blue">
                  <i class="i-lucide-clock w-4 h-4" />
                </div>
                <p class="sched-kpi-label">Próximos</p>
                <p class="sched-kpi-value">{{ aptKPIs.upcoming }}</p>
              </div>
              <!-- Faltas -->
              <div class="sched-kpi-card sched-kpi-card--red">
                <div class="sched-kpi-icon sched-kpi-icon--red">
                  <i class="i-lucide-user-x w-4 h-4" />
                </div>
                <p class="sched-kpi-label">Faltas</p>
                <p class="sched-kpi-value">{{ aptKPIs.noShows }}</p>
              </div>
            </div>

            <!-- Filtros pill -->
            <div class="sched-filter-row mb-6">
              <button
                class="sched-filter-btn"
                :class="{
                  'sched-filter-btn--active': appointmentFilter === 'all',
                }"
                @click="appointmentFilter = 'all'"
              >
                <i class="i-lucide-layout-grid w-3.5 h-3.5" /> Todos
              </button>
              <button
                class="sched-filter-btn"
                :class="{
                  'sched-filter-btn--active': appointmentFilter === 'upcoming',
                }"
                @click="appointmentFilter = 'upcoming'"
              >
                <i class="i-lucide-calendar-clock w-3.5 h-3.5" /> Próximos
              </button>
              <button
                class="sched-filter-btn"
                :class="{
                  'sched-filter-btn--active': appointmentFilter === 'issues',
                }"
                @click="appointmentFilter = 'issues'"
              >
                <i class="i-lucide-octagon-alert w-3.5 h-3.5" />
                Faltas/Cancelados
                <span v-if="issuesCount > 0" class="sched-filter-badge">{{
                  issuesCount
                }}</span>
              </button>
            </div>

            <!-- Alerta de Retorno Pendente -->
            <div
              v-if="pendingRecallAppointment"
              class="sched-recall-alert mb-6"
            >
              <div class="sched-recall-icon">
                <i class="i-lucide-bell-ring w-4 h-4" />
              </div>
              <div class="sched-recall-body">
                <h4 class="sched-recall-title">
                  <i class="i-lucide-triangle-alert w-3 h-3" />
                  Retorno Pendente — Paciente Faltou
                </h4>
                <p class="sched-recall-desc">
                  O paciente não compareceu à consulta de
                  <strong>{{
                    APPOINTMENT_TYPE_LABELS[
                      pendingRecallAppointment.appointment_type
                    ]
                  }}</strong>
                  agendada para
                  <strong
                    >{{ formatDate(pendingRecallAppointment.scheduled_at) }} às
                    {{
                      formatTime(pendingRecallAppointment.scheduled_at)
                    }}</strong
                  >. Nenhum lembrete foi enviado ainda.
                </p>
                <div class="flex items-center gap-2">
                  <button
                    class="sched-recall-btn"
                    :disabled="recallLoading"
                    @click="sendRecallWhatsApp(pendingRecallAppointment.id)"
                  >
                    <i
                      v-if="recallLoading"
                      class="i-lucide-loader-2 animate-spin w-3 h-3"
                    />
                    <i v-else class="i-lucide-message-circle w-3 h-3" />
                    Lembrar via WhatsApp
                  </button>
                  <button
                    class="sched-recall-btn-ghost"
                    @click="openRescheduleFromRecall(pendingRecallAppointment)"
                  >
                    <i class="i-lucide-calendar-arrow-up w-3 h-3" />
                    Reagendar Manualmente
                  </button>
                </div>
              </div>
              <div class="sched-recall-dismiss">
                <button
                  class="sched-dismiss-text"
                  @click="dismissRecallForever"
                >
                  Não mostrar mais
                </button>
                <button
                  class="sched-dismiss-x"
                  title="Fechar lembrete"
                  @click="dismissRecallSession"
                >
                  <i class="i-lucide-x w-5 h-5" />
                </button>
              </div>
            </div>

            <!-- Loading -->
            <div
              v-if="appointmentsLoading"
              class="flex items-center justify-center py-16 gap-3 text-slate-400"
            >
              <i class="i-lucide-loader-2 animate-spin text-woot-400 text-xl" />
              <span>Carregando agendamentos...</span>
            </div>

            <!-- Empty State -->
            <div
              v-else-if="
                !appointmentsLoading && filteredAppointments.length === 0
              "
              class="sched-empty"
            >
              <div class="sched-empty-icon">
                <i class="i-lucide-calendar-off w-7 h-7" />
              </div>
              <p class="sched-empty-title">Nenhum agendamento encontrado</p>
              <p class="sched-empty-hint">
                {{
                  appointmentFilter === 'all'
                    ? 'Este paciente ainda não tem consultas registradas.'
                    : 'Nenhum registro neste filtro.'
                }}
              </p>
              <button
                class="btn-primary mt-2 flex items-center gap-2"
                @click="navigateToAgendaWithPatient"
              >
                <i class="i-lucide-calendar-plus" /> Agendar Primeira Consulta
              </button>
            </div>

            <!-- Lista de Agendamentos -->
            <div v-else class="sched-timeline">
              <!-- Linha vertical -->
              <div class="sched-timeline-line" />

              <div
                v-for="apt in filteredAppointments"
                :key="apt.id"
                class="sched-apt-item"
              >
                <!-- Dot na linha do tempo -->
                <div
                  class="sched-apt-dot"
                  :class="{
                    'sched-apt-dot--noshow':
                      apt.status === 'no_show' || apt.status === 'canceled',
                    'sched-apt-dot--scheduled': [
                      'scheduled',
                      'confirmed',
                      'rescheduled',
                    ].includes(apt.status),
                    'sched-apt-dot--done':
                      apt.status === 'done' || apt.status === 'completed',
                  }"
                />

                <!-- Card de Agendamento -->
                <div class="sched-apt-card">
                  <!-- Topo: badges + data -->
                  <div class="sched-apt-header">
                    <div class="sched-apt-badges">
                      <!-- Status -->
                      <span
                        class="sched-status-badge"
                        :class="aptStatusCfg(apt.status).badgeCls"
                      >
                        <i
                          class="w-3 h-3"
                          :class="aptStatusCfg(apt.status).icon"
                        />
                        {{ aptStatusCfg(apt.status).label }}
                      </span>
                      <!-- Tipo -->
                      <span
                        v-if="
                          EVENT_TYPE_LABELS[apt.event_type_label] ||
                          EVENT_TYPE_LABELS[apt.appointment_type]
                        "
                        class="sched-type-badge"
                      >
                        {{
                          EVENT_TYPE_LABELS[apt.event_type_label] ||
                          EVENT_TYPE_LABELS[apt.appointment_type] ||
                          '—'
                        }}
                      </span>
                      <!-- Prioridade -->
                      <span
                        v-if="apt.priority"
                        class="sched-priority-badge"
                        :class="priorityCfg(apt.priority).cls"
                      >
                        {{ priorityCfg(apt.priority).text }}
                        {{ priorityCfg(apt.priority).label }}
                      </span>
                      <!-- PRÓXIMA -->
                      <span
                        v-if="
                          apt.id === nextAppointmentId &&
                          !['canceled', 'no_show'].includes(apt.status)
                        "
                        class="sched-next-badge"
                      >
                        <i class="i-lucide-sparkles w-2.5 h-2.5" /> PRÓXIMA
                      </span>
                    </div>

                    <!-- Data/Hora -->
                    <div class="sched-apt-datetime">
                      <p class="sched-apt-date">
                        {{ formatDate(apt.scheduled_at) }}
                      </p>
                      <p class="sched-apt-time">
                        {{ formatTime(apt.scheduled_at) }} ·
                        {{ apt.duration_minutes || 60 }}min
                      </p>
                    </div>
                  </div>

                  <!-- Conteúdo: info em grid -->
                  <div class="sched-apt-info">
                    <!-- Profissional -->
                    <div class="sched-info-col">
                      <p class="sched-info-label">Profissional Responsável</p>
                      <div class="flex items-center gap-2">
                        <i class="i-lucide-user w-3.5 h-3.5 text-slate-500" />
                        <span
                          v-if="apt.professional?.name || apt.professional_name"
                          class="sched-info-value"
                        >
                          {{ apt.professional?.name || apt.professional_name }}
                        </span>
                        <span
v-else class="sched-info-empty"
                          >Não informado</span
                        >
                      </div>
                    </div>
                    <!-- Tratamento -->
                    <div v-if="apt.treatment" class="sched-info-col">
                      <p class="sched-info-label">Tratamento</p>
                      <div class="flex items-center gap-2">
                        <i
                          class="i-lucide-activity w-3.5 h-3.5 text-slate-500"
                        />
                        <span class="sched-info-value">{{
                          apt.treatment
                        }}</span>
                      </div>
                    </div>
                  </div>

                  <!-- Motivo Reagendamento -->
                  <div
                    v-if="apt.reschedule_reason"
                    class="sched-reason sched-reason--amber"
                  >
                    <i class="i-lucide-info w-3.5 h-3.5 mt-0.5 shrink-0" />
                    <span
                      ><strong>Motivo Reagendamento:</strong>
                      {{ apt.reschedule_reason }}</span
                    >
                  </div>

                  <!-- Motivo Cancelamento -->
                  <div
                    v-if="apt.cancellation_reason"
                    class="sched-reason sched-reason--red"
                  >
                    <i
                      class="i-lucide-circle-slash w-3.5 h-3.5 mt-0.5 shrink-0"
                    />
                    <span
                      ><strong>Motivo Cancelamento:</strong>
                      {{ apt.cancellation_reason }}</span
                    >
                  </div>

                  <!-- Observações -->
                  <div v-if="apt.notes" class="sched-notes">
                    "{{ apt.notes }}"
                  </div>

                  <!-- Ações (footer do card) -->
                  <div
                    v-if="
                      apt.cancellable ||
                      apt.reschedulable ||
                      apt.status === 'no_show'
                    "
                    class="sched-apt-actions"
                  >
                    <button
                      v-if="apt.status === 'no_show' && !apt.recall_sent"
                      class="sched-action-btn sched-action-btn--amber"
                      :disabled="recallLoading"
                      @click="sendRecallWhatsApp(apt.id)"
                    >
                      <i
                        v-if="recallLoading"
                        class="i-lucide-loader-2 animate-spin w-3.5 h-3.5"
                      />
                      <i v-else class="i-lucide-message-circle w-3.5 h-3.5" />
                      Notificar WhatsApp
                    </button>
                    <button
                      v-if="apt.reschedulable || apt.status === 'no_show'"
                      class="sched-action-btn"
                      @click="
                        apt.status === 'no_show'
                          ? navigateToAgendaWithPatient()
                          : openRescheduleModal(apt)
                      "
                    >
                      <i class="i-lucide-calendar-clock w-3.5 h-3.5" />
                      Reagendar Agora
                    </button>
                    <button
                      v-if="apt.cancellable"
                      class="sched-action-btn sched-action-btn--danger"
                      @click="openNoShowModal(apt)"
                    >
                      <i class="i-lucide-user-minus w-3.5 h-3.5" />
                      Marcar Falta
                    </button>
                  </div>
                </div>
              </div>

              <!-- Fim da linha do tempo -->
              <div
                v-if="filteredAppointments.length > 0"
                class="sched-timeline-end"
              >
                <div class="sched-timeline-end-line" />
                <span class="sched-timeline-end-label"
                  >Início do histórico</span
                >
                <div class="sched-timeline-end-line" />
              </div>
            </div>

            <!-- Modal: Reagendar -->
            <div
              v-if="showRescheduleModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
              @click.self="showRescheduleModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-md"
              >
                <div
                  class="flex items-center justify-between p-6 border-b border-slate-700/50"
                >
                  <div>
                    <h3
                      class="text-lg font-semibold text-slate-100 flex items-center gap-2"
                    >
                      <i class="i-lucide-calendar-arrow-up text-orange-400" />
                      Reagendar Consulta
                    </h3>
                    <p class="text-xs text-slate-400 mt-0.5">
                      Selecione a nova data e horário
                    </p>
                  </div>
                  <button
                    class="text-slate-400 hover:text-slate-100"
                    @click="showRescheduleModal = false"
                  >
                    <i class="i-lucide-x text-xl" />
                  </button>
                </div>
                <div class="p-6 space-y-4">
                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Nova Data e Hora *</label
                    >
                    <input
                      v-model="rescheduleForm.new_scheduled_at"
                      type="datetime-local"
                      class="form-input w-full"
                    />
                  </div>
                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Duração (minutos)</label
                    >
                    <input
                      v-model="rescheduleForm.duration_minutes"
                      type="number"
                      min="15"
                      max="480"
                      step="15"
                      class="form-input w-full"
                    />
                  </div>
                  <div>
                    <label
                      class="block text-sm font-medium text-slate-300 mb-1.5"
                      >Motivo do Reagendamento</label
                    >
                    <input
                      v-model="rescheduleForm.reschedule_reason"
                      type="text"
                      placeholder="Ex: Solicitação do paciente..."
                      class="form-input w-full"
                    />
                  </div>
                </div>
                <div
                  class="p-6 border-t border-slate-700/50 flex justify-end gap-3"
                >
                  <button
                    class="btn-secondary"
                    @click="showRescheduleModal = false"
                  >
                    Cancelar
                  </button>
                  <button
                    class="bg-orange-600 hover:bg-orange-500 text-white font-medium py-2 px-4 rounded-xl transition-colors flex items-center gap-2 disabled:opacity-50"
                    :disabled="
                      rescheduleLoading || !rescheduleForm.new_scheduled_at
                    "
                    @click="handleReschedule"
                  >
                    <i
                      v-if="rescheduleLoading"
                      class="i-lucide-loader-2 animate-spin"
                    />
                    <i v-else class="i-lucide-calendar-check" />
                    Confirmar Reagendamento
                  </button>
                </div>
              </div>
            </div>

            <!-- Modal: Confirmar Falta -->
            <div
              v-if="showNoShowModal"
              class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
              @click.self="showNoShowModal = false"
            >
              <div
                class="bg-slate-900 border border-slate-700 rounded-xl w-full max-w-sm"
              >
                <!-- Header -->
                <div
                  class="flex items-center justify-between p-5 border-b border-slate-700/50"
                >
                  <div class="flex items-center gap-3">
                    <i class="i-lucide-user-minus text-red-400 text-lg" />
                    <div>
                      <h3 class="text-base font-semibold text-slate-100">
                        Registrar Falta
                      </h3>
                      <p class="text-xs text-slate-400 mt-0.5">
                        Esta ação não pode ser desfeita
                      </p>
                    </div>
                  </div>
                  <button
                    class="text-slate-500 hover:text-slate-200 transition-colors"
                    @click="showNoShowModal = false"
                  >
                    <i class="i-lucide-x text-lg" />
                  </button>
                </div>

                <!-- Body -->
                <div class="p-5">
                  <p class="text-sm text-slate-400">
                    O status será alterado para
                    <span class="font-semibold text-red-400">Falta</span>
                    e o contador de faltas do paciente será incrementado.
                  </p>
                </div>

                <!-- Footer -->
                <div
                  class="p-5 border-t border-slate-700/50 flex justify-end gap-3"
                >
                  <button
                    class="btn-secondary"
                    @click="showNoShowModal = false"
                  >
                    Cancelar
                  </button>
                  <button
                    class="btn-primary bg-red-600 hover:bg-red-500 text-white flex items-center gap-2 disabled:opacity-50"
                    :disabled="noShowLoading"
                    @click="handleNoShow"
                  >
                    <i
                      v-if="noShowLoading"
                      class="i-lucide-loader-2 animate-spin"
                    />
                    <i v-else class="i-lucide-user-minus" />
                    Confirmar Falta
                  </button>
                </div>
              </div>
            </div>
          </div>
          <!-- ABA: TIMELINE -->
          <div v-else-if="activeTab === 'timeline'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-6">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Timeline do Paciente
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Visão consolidada de todas as interações, prontuários e
                  movimentações.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <span class="text-xs text-slate-500">
                  {{ filteredTimelineEvents.length }} evento{{
                    filteredTimelineEvents.length !== 1 ? 's' : ''
                  }}
                </span>
                <!-- Filtro de ordenação -->
                <div class="relative">
                  <button
                    class="geral-header-btn"
                    @click="timelineFilterOpen = !timelineFilterOpen"
                  >
                    <i class="i-lucide-arrow-up-down w-3.5 h-3.5" />
                    {{
                      timelineSortOrder === 'oldest'
                        ? 'Mais antigo'
                        : 'Mais recente'
                    }}
                  </button>
                  <div
                    v-if="timelineFilterOpen"
                    class="tl-sort-dropdown"
                    @click.stop
                  >
                    <button
                      v-for="sort in [
                        {
                          value: 'newest',
                          label: 'Mais recente primeiro',
                          icon: 'i-lucide-arrow-down-narrow-wide',
                        },
                        {
                          value: 'oldest',
                          label: 'Mais antigo primeiro',
                          icon: 'i-lucide-arrow-up-narrow-wide',
                        },
                      ]"
                      :key="sort.value"
                      class="tl-sort-option"
                      :class="{
                        'tl-sort-option--active':
                          timelineSortOrder === sort.value,
                      }"
                      @click="
                        timelineSortOrder = sort.value;
                        timelineFilterOpen = false;
                      "
                    >
                      <i :class="sort.icon" class="w-3.5 h-3.5" />
                      {{ sort.label }}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <!-- Filtros de categoria (pills) -->
            <div class="tl-filter-row mb-6">
              <button
                v-for="chip in [
                  { value: 'all', label: 'Tudo', icon: 'i-lucide-layers' },
                  {
                    value: 'appointments',
                    label: 'Consultas',
                    icon: 'i-lucide-calendar',
                  },
                  {
                    value: 'clinical',
                    label: 'Clínico',
                    icon: 'i-lucide-stethoscope',
                  },
                  {
                    value: 'financial',
                    label: 'Financeiro',
                    icon: 'i-lucide-circle-dollar-sign',
                  },
                  {
                    value: 'documents',
                    label: 'Documentos',
                    icon: 'i-lucide-file-text',
                  },
                ]"
                :key="chip.value"
                class="tl-filter-btn"
                :class="{
                  'tl-filter-btn--active': timelineFilter === chip.value,
                }"
                @click="timelineFilter = chip.value"
              >
                <i :class="chip.icon" class="w-3.5 h-3.5" />
                {{ chip.label }}
              </button>
            </div>

            <!-- Loading -->
            <div
              v-if="timelineLoading"
              class="flex items-center justify-center py-20 gap-3 text-slate-400"
            >
              <i class="i-lucide-loader-2 animate-spin text-woot-400 text-xl" />
              <span>Carregando timeline...</span>
            </div>

            <!-- Empty state -->
            <div
              v-else-if="
                !timelineLoading && filteredTimelineEvents.length === 0
              "
              class="tl-empty"
            >
              <div class="tl-empty-icon">
                <i class="i-lucide-clock-x w-6 h-6" />
              </div>
              <p class="tl-empty-title">Nenhum evento encontrado</p>
              <p class="tl-empty-hint">
                {{
                  timelineFilter !== 'all'
                    ? 'Tente remover os filtros aplicados.'
                    : 'As interações com o paciente aparecerão aqui.'
                }}
              </p>
              <button
                v-if="timelineFilter !== 'all'"
                class="btn-secondary mt-1"
                @click="timelineFilter = 'all'"
              >
                Limpar filtros
              </button>
            </div>

            <!-- Timeline agrupada por data -->
            <div v-else class="tl-timeline">
              <div
                v-for="group in groupedTimelineEvents"
                :key="group.date"
                class="tl-group"
              >
                <!-- Separador de data -->
                <div class="tl-date-divider">
                  <div class="tl-date-line" />
                  <span class="tl-date-label">{{ group.date }}</span>
                  <div class="tl-date-line" />
                </div>

                <!-- Eventos do grupo -->
                <div class="tl-events">
                  <!-- Linha vertical contínua -->
                  <div class="tl-vline" />

                  <div
                    v-for="event in group.events"
                    :key="event.id"
                    class="tl-event-row"
                  >
                    <!-- Ícone circular do evento -->
                    <div
                      class="tl-event-icon"
                      :class="tlIconCls(event.event_type)"
                    >
                      <i
                        :class="timelineEventConfig(event.event_type).icon"
                        class="w-4 h-4"
                      />
                    </div>

                    <!-- Card do evento -->
                    <div class="tl-event-card">
                      <!-- Cabeçalho: badge tipo + hora -->
                      <div class="tl-event-header">
                        <span
                          class="tl-event-badge"
                          :class="tlBadgeCls(event.event_type)"
                        >
                          {{ timelineEventConfig(event.event_type).label }}
                        </span>
                        <span class="tl-event-time">{{
                          formatTime(event.occurred_at)
                        }}</span>
                      </div>

                      <!-- Título -->
                      <p class="tl-event-title">{{ event.label }}</p>

                      <!-- Metadados -->
                      <div
                        v-if="
                          event.metadata &&
                          Object.keys(event.metadata).length > 0
                        "
                        class="tl-event-meta"
                      >
                        <template
                          v-for="(val, key) in event.metadata"
                          :key="key"
                        >
                          <div
                            v-if="
                              val &&
                              key !== 'account_id' &&
                              key !== 'patient_id'
                            "
                            class="tl-meta-item"
                          >
                            <span class="tl-meta-key">{{
                              key.replace(/_/g, ' ')
                            }}</span>
                            <span class="tl-meta-val">{{
                              typeof val === 'string' &&
                              /^\d{4}-\d{2}-\d{2}T/.test(val)
                                ? new Date(val)
                                    .toLocaleString('pt-BR', {
                                      day: '2-digit',
                                      month: '2-digit',
                                      year: 'numeric',
                                      hour: '2-digit',
                                      minute: '2-digit',
                                      timeZone: BRT,
                                    })
                                    .replace(',', ' às')
                                : val
                            }}</span>
                          </div>
                        </template>
                      </div>

                      <!-- Actor -->
                      <div v-if="event.actor_name" class="tl-event-actor">
                        <i class="i-lucide-user-round w-3 h-3" />
                        <span>{{ event.actor_name }}</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Marcador de início do histórico -->
              <div class="tl-history-end">
                <div class="tl-history-line" />
                <div class="tl-history-dot" />
                <span class="tl-history-label">Início do histórico</span>
                <div class="tl-history-line" />
              </div>
            </div>
          </div>
          <!-- ABA: AUDITORIA E PERMISSÕES -->

          <div v-else-if="activeTab === 'audit'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-6">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Auditoria e Segurança
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Rastreabilidade com valor legal de todos os acessos, edições e
                  assinaturas no prontuário.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <button
                  class="geral-header-btn disabled:opacity-50 disabled:cursor-not-allowed"
                  :disabled="isExportingPdf"
                  @click="exportPdf"
                >
                  <i
                    v-if="isExportingPdf"
                    class="i-lucide-loader-2 animate-spin w-3.5 h-3.5"
                  />
                  <i v-else class="i-lucide-download w-3.5 h-3.5" />
                  {{
                    isExportingPdf
                      ? 'Gerando PDF...'
                      : 'Exportar Prontuário PDF'
                  }}
                </button>
              </div>
            </div>

            <!-- Barra de filtros -->
            <div class="aud-filter-bar mb-5">
              <div class="aud-filter-field">
                <label class="aud-filter-label">Tipo de Ação</label>
                <select
                  v-model="auditFilters.action_type"
                  class="form-input text-sm"
                >
                  <option
                    v-for="opt in AUDIT_ACTION_OPTIONS"
                    :key="opt.value"
                    :value="opt.value"
                  >
                    {{ opt.label }}
                  </option>
                </select>
              </div>
              <div class="aud-filter-field">
                <label class="aud-filter-label">Data Início</label>
                <input
                  v-model="auditFilters.start_date"
                  type="date"
                  class="form-input text-sm"
                />
              </div>
              <div class="aud-filter-field">
                <label class="aud-filter-label">Data Fim</label>
                <input
                  v-model="auditFilters.end_date"
                  type="date"
                  class="form-input text-sm"
                />
              </div>
              <div class="aud-filter-actions">
                <button
                  class="btn-primary flex items-center gap-1.5"
                  @click="applyAuditFilters"
                >
                  <i class="i-lucide-filter w-3.5 h-3.5" /> Filtrar
                </button>
                <button
                  class="btn-secondary aud-clear-btn"
                  title="Limpar filtros"
                  @click="clearAuditFilters"
                >
                  <i class="i-lucide-x w-4 h-4" />
                </button>
              </div>
            </div>

            <!-- Tabela de Logs -->
            <div class="aud-table-wrap">
              <!-- Loading -->
              <div v-if="isAuditLoading" class="aud-loading">
                <i class="i-lucide-loader-2 animate-spin w-5 h-5" />
                <span>Carregando logs de auditoria...</span>
              </div>

              <!-- Tabela real -->
              <div v-else class="overflow-x-auto">
                <table class="aud-table">
                  <thead>
                    <tr class="aud-thead-row">
                      <th class="aud-th">Data / Hora</th>
                      <th class="aud-th">Ação</th>
                      <th class="aud-th">Usuário / Perfil</th>
                      <th class="aud-th">Módulo &amp; Detalhes</th>
                      <th class="aud-th">IP</th>
                      <th class="aud-th aud-th--center">Info</th>
                    </tr>
                  </thead>
                  <tbody>
                    <!-- Estado vazio -->
                    <tr v-if="auditLogs.length === 0">
                      <td colspan="6" class="aud-empty-cell">
                        <div class="aud-empty-state">
                          <i class="i-lucide-shield-off w-6 h-6" />
                          <p>
                            Nenhum log de auditoria encontrado para este
                            paciente.
                          </p>
                          <p class="aud-empty-hint">
                            Tente ajustar os filtros ou verifique suas
                            permissões.
                          </p>
                        </div>
                      </td>
                    </tr>

                    <!-- Linhas de log -->
                    <template v-for="log in auditLogs" :key="log.id">
                      <tr class="aud-row">
                        <!-- Data/Hora -->
                        <td class="aud-td aud-td--mono aud-td--dim">
                          {{ formatAuditDateTime(log.occurred_at) }}
                        </td>

                        <!-- Tipo de ação -->
                        <td class="aud-td">
                          <span
                            class="aud-action-badge"
                            :class="formatAuditAction(log.action).color"
                          >
                            <i
                              class="w-3 h-3"
                              :class="formatAuditAction(log.action).icon"
                            />
                            {{ formatAuditAction(log.action).label }}
                          </span>
                        </td>

                        <!-- Usuário / Perfil -->
                        <td class="aud-td">
                          <div class="aud-user-cell">
                            <div class="aud-avatar">
                              {{ getInitials(log.actor_name) }}
                            </div>
                            <div>
                              <p class="aud-user-name">
                                {{ log.actor_name || 'Sistema' }}
                              </p>
                              <p class="aud-user-role">
                                {{ log.actor_role || '—' }}
                              </p>
                            </div>
                          </div>
                        </td>

                        <!-- Módulo & Detalhes -->
                        <td class="aud-td aud-td--details">
                          <span class="aud-module-name">{{
                            log.resource_type || 'Ficha'
                          }}</span>
                          <span
v-if="log.resource_id" class="aud-module-id"
                            >#{{ log.resource_id }}</span
                          >

                          <!-- Diff de campos alterados -->
                          <div
                            v-if="
                              log.changed_fields &&
                              Object.keys(log.changed_fields).length > 0
                            "
                            class="aud-diff"
                          >
                            <div
                              v-for="(vals, field) in log.changed_fields"
                              :key="field"
                              class="aud-diff-row"
                            >
                              <span class="aud-diff-field">{{ field }}:</span>
                              <span class="aud-diff-old">{{
                                vals[0] !== null ? vals[0] : 'vazio'
                              }}</span>
                              <i
                                class="i-lucide-arrow-right w-2.5 h-2.5 text-slate-600"
                              />
                              <span class="aud-diff-new">{{
                                vals[1] !== null ? vals[1] : 'vazio'
                              }}</span>
                            </div>
                          </div>

                          <!-- Snapshot new_value -->
                          <div
                            v-else-if="log.new_value"
                            class="aud-snapshot"
                            :title="JSON.stringify(log.new_value)"
                          >
                            {{ JSON.stringify(log.new_value).slice(0, 80)
                            }}{{
                              JSON.stringify(log.new_value).length > 80
                                ? '…'
                                : ''
                            }}
                          </div>
                        </td>

                        <!-- IP -->
                        <td class="aud-td aud-td--mono aud-td--dim">
                          {{ log.ip_address || '—' }}
                        </td>

                        <!-- Ver detalhes -->
                        <td class="aud-td aud-td--center">
                          <button
                            class="aud-detail-btn"
                            :title="
                              expandedLogs.has(log.id)
                                ? 'Recolher detalhes'
                                : 'Ver detalhes completos'
                            "
                            @click="toggleLogDetails(log.id)"
                          >
                            <i
                              class="w-4 h-4"
                              :class="
                                expandedLogs.has(log.id)
                                  ? 'i-lucide-eye-off'
                                  : 'i-lucide-eye'
                              "
                            />
                          </button>
                        </td>
                      </tr>

                      <!-- Linha expandida -->
                      <tr
                        v-if="expandedLogs.has(log.id)"
                        class="aud-expanded-row"
                      >
                        <td colspan="6" class="aud-expanded-cell">
                          <div class="aud-expanded-body">
                            <i
                              class="i-lucide-info w-4 h-4 aud-expanded-icon"
                            />
                            <div>
                              <p class="aud-expanded-title">
                                Registro de Ação Detalhado
                              </p>
                              <p class="aud-expanded-text">
                                {{ generateDetailedAuditText(log) }}
                              </p>

                              <!-- Diff completo -->
                              <div
                                v-if="
                                  log.action === 'update' &&
                                  log.changed_fields &&
                                  Object.keys(log.changed_fields).length > 0
                                "
                                class="aud-expanded-diff"
                              >
                                <p class="aud-expanded-diff-title">
                                  Histórico de Alterações (De → Para)
                                </p>
                                <ul class="aud-expanded-diff-list">
                                  <li
                                    v-for="(vals, field) in log.changed_fields"
                                    :key="field"
                                    class="aud-expanded-diff-item"
                                  >
                                    <span class="aud-diff-f">{{ field }}</span>
                                    <span class="aud-diff-o">{{
                                      vals[0] !== null ? vals[0] : 'nulo'
                                    }}</span>
                                    <i
                                      class="i-lucide-arrow-right w-3 h-3 text-slate-600"
                                    />
                                    <span class="aud-diff-n">{{
                                      vals[1] !== null ? vals[1] : 'nulo'
                                    }}</span>
                                  </li>
                                </ul>
                              </div>
                            </div>
                          </div>
                        </td>
                      </tr>
                    </template>
                  </tbody>
                </table>
              </div>
            </div>

            <!-- Rodapé: nota de imutabilidade + paginação -->
            <div class="aud-footer mt-5">
              <p class="aud-footer-note">
                <i class="i-lucide-lock w-3 h-3" />
                Registros imutáveis — gravados permanentemente no banco.
                <span class="aud-footer-total"
                  >Total: {{ auditMeta.total_count }} eventos</span
                >
              </p>
              <div class="aud-pagination">
                <span class="aud-page-info"
                  >Página {{ auditMeta.current_page }} de
                  {{ auditMeta.total_pages }}</span
                >
                <div class="flex gap-2">
                  <button
                    class="btn-secondary disabled:opacity-40 disabled:cursor-not-allowed"
                    :disabled="auditFilters.page <= 1 || isAuditLoading"
                    @click="auditPagePrev"
                  >
                    ← Anterior
                  </button>
                  <button
                    class="btn-secondary disabled:opacity-40 disabled:cursor-not-allowed"
                    :disabled="
                      auditFilters.page >= auditMeta.total_pages ||
                      isAuditLoading
                    "
                    @click="auditPageNext"
                  >
                    Próxima →
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div v-else class="tab-pane fade-in">
            <div class="card placeholder-card">
              <div class="placeholder-icon">
                <i class="i-lucide-hammer" />
              </div>
              <h3>Aba em Construção</h3>
              <p>
                Esta área (<strong>{{
                  tabs.find(t => t.id === activeTab)?.label
                }}</strong>
                ) receberá os componentes específicos em breve.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Confirm Delete Note Modal -->
    <div
      v-if="showConfirmDeleteNote"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999] bg-black/60"
      @click.self="cancelDeleteNote"
    >
      <div
        class="delete-modal-card rounded-xl shadow-xl w-full max-w-[420px] overflow-hidden bg-[var(--color-background,#1d2b3e)] border border-white/10"
      >
        <div class="p-6">
          <div class="flex items-start gap-4">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
            >
              <i class="i-lucide-alert-triangle size-5 text-rose-500" />
            </div>
            <div class="flex flex-col gap-2 pt-1">
              <h3 class="font-medium text-slate-100 m-0 text-lg leading-tight">
                Excluir Rascunho?
              </h3>
              <p class="text-slate-400 m-0 text-sm leading-relaxed">
                Deseja realmente excluir este rascunho de evolução? Esta ação
                não pode ser desfeita.
              </p>
            </div>
          </div>
        </div>
        <div
          class="px-6 py-4 flex justify-end gap-3 border-t border-white/10 bg-white/5"
        >
          <button
            class="rounded-lg px-4 py-2 text-sm font-medium bg-transparent text-slate-400 hover:text-slate-100 hover:bg-slate-800 transition-colors border-0 cursor-pointer"
            @click="cancelDeleteNote"
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-rose-500 hover:text-rose-400 hover:bg-rose-500/10 bg-transparent transition-all border-0 cursor-pointer"
            @click="confirmDeleteNote"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>

    <!-- Treatment Item Modal -->
    <div
      v-if="showItemModal"
      class="tp-modal-overlay"
      @click.self="showItemModal = false"
    >
      <div class="tp-modal-card">
        <!-- Header -->
        <div class="tp-modal-header">
          <div>
            <h3 class="tp-modal-title">
              {{ currentItem.id ? 'Editar Procedimento' : 'Novo Procedimento' }}
            </h3>
            <p class="tp-modal-subtitle">
              Defina os detalhes da intervenção planejada
            </p>
          </div>
          <button class="tp-modal-close" @click="showItemModal = false">
            <i class="i-lucide-x" />
          </button>
        </div>

        <!-- Body -->
        <div class="tp-modal-body">
          <!-- Procedimento -->
          <div class="tp-field">
            <label class="tp-label">
              Nome do Procedimento <span class="tp-required">*</span>
            </label>
            <select
              v-model="currentItem.procedure_name"
              class="tp-input tp-select"
              @change="handleProcedureSelect"
            >
              <option disabled value="">Selecione um serviço...</option>
              <option
                v-for="svc in agendaServices"
                :key="svc.id"
                :value="svc.name"
              >
                {{ svc.name }} - {{ formatCurrency(svc.price) }}
              </option>
            </select>
          </div>

          <!-- Região + Sessões -->
          <div class="tp-row-2">
            <div class="tp-field">
              <label class="tp-label">Região/Dente</label>
              <input
                v-model="currentItem.region"
                class="tp-input"
                placeholder="Ex: 11, 21 ou Geral"
              />
            </div>
            <div class="tp-field">
              <label class="tp-label">Qtd. Sessões</label>
              <input
                v-model.number="currentItem.sessions_planned"
                type="number"
                min="1"
                class="tp-input"
              />
            </div>
          </div>
        </div>

        <!-- Footer -->
        <div class="tp-modal-footer">
          <button class="tp-btn-cancel" @click="showItemModal = false">
            Cancelar
          </button>
          <button
            class="tp-btn-submit"
            :disabled="isSavingItem || !currentItem.procedure_name"
            @click="saveItem"
          >
            <i
              v-if="isSavingItem"
              class="i-lucide-loader-2 tp-spinner-icon animate-spin"
            />
            <span v-else>Confirmar</span>
          </button>
        </div>
      </div>
    </div>

    <!-- Modal Excluir Procedimento -->
    <div
      v-if="showConfirmDeleteItem"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999] bg-black/60"
      @click.self="cancelDeleteItem"
    >
      <div
        class="delete-modal-card rounded-2xl w-full max-w-[420px] overflow-hidden bg-[linear-gradient(145deg,#1e293b,#0f172a)] border border-white/5 shadow-[0_25px_50px_-12px_rgba(0,0,0,0.5)]"
      >
        <div class="p-6">
          <div class="flex items-start gap-4">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
            >
              <i class="i-lucide-alert-triangle size-5 text-rose-500" />
            </div>
            <div class="flex flex-col gap-2 pt-1">
              <h3 class="font-medium text-slate-100 m-0 text-lg leading-tight">
                Excluir Procedimento?
              </h3>
              <p class="text-slate-400 m-0 text-sm leading-relaxed">
                Esta ação não pode ser desfeita. O procedimento será removido
                permanentemente do plano de tratamento selecionado.
              </p>
            </div>
          </div>
        </div>
        <div class="px-6 py-4 flex justify-end gap-3 border-t border-white/5">
          <button
            class="rounded-lg px-4 py-2 text-sm font-medium bg-transparent text-slate-400 hover:text-slate-100 transition-colors border-0 cursor-pointer"
            @click="cancelDeleteItem"
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-rose-500 hover:text-rose-400 hover:bg-rose-500/10 bg-transparent transition-all border-0 cursor-pointer"
            @click="confirmDeleteItem"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>

    <!-- Modal: Tirar Foto (Webcam) -->
    <div
      v-if="showCameraModal"
      class="fixed inset-0 z-[99999] flex items-center justify-center bg-black/75 backdrop-blur-md px-4"
      @click.self="closeCameraModal"
    >
      <div class="cam-modal">
        <!-- Header -->
        <div class="cam-modal-header">
          <div class="flex items-center gap-2.5">
            <div class="cam-header-icon">
              <i class="i-lucide-camera w-4 h-4" />
            </div>
            <div>
              <p class="text-sm font-semibold text-n-slate-12 leading-none">
                Tirar Foto
              </p>
              <p class="text-xs text-n-slate-10 mt-0.5">
                Posicione seu rosto no centro
              </p>
            </div>
          </div>
          <button class="cam-close-btn" @click="closeCameraModal">
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </div>

        <!-- Viewfinder -->
        <div class="cam-viewfinder">
          <video
            v-show="!capturedPhoto"
            ref="videoElement"
            class="cam-video"
            autoplay
            playsinline
          />
          <img v-show="capturedPhoto" :src="capturedPhoto" class="cam-video" />
          <canvas ref="canvasElement" class="hidden" />

          <!-- Overlay de guia circular -->
          <div v-if="!capturedPhoto && !cameraError" class="cam-guide-overlay">
            <div class="cam-guide-ring" />
          </div>

          <!-- Erro de câmera -->
          <div v-if="cameraError" class="cam-error-overlay">
            <i class="i-lucide-camera-off w-10 h-10 text-n-red-10 dark:text-n-red-9 mb-3" />
            <p class="text-sm text-n-slate-11 text-center px-4">
              Permissão negada ou câmera não encontrada.
            </p>
          </div>
        </div>

        <!-- Controles -->
        <div class="cam-controls">
          <template v-if="!capturedPhoto">
            <button class="cam-btn-ghost" @click="closeCameraModal">
              Cancelar
            </button>
            <button
              class="cam-btn-capture"
              :disabled="cameraError"
              @click="capturePhoto"
            >
              <span class="cam-shutter" />
            </button>
            <div class="w-20" />
          </template>
          <template v-else>
            <button
              class="cam-btn-ghost flex items-center gap-1.5"
              @click="retakePhoto"
            >
              <i class="i-lucide-refresh-cw w-3.5 h-3.5" /> Repetir
            </button>
            <button
              class="cam-btn-confirm flex items-center gap-2"
              @click="useCapturedPhoto"
            >
              <i class="i-lucide-check w-4 h-4" /> Usar foto
            </button>
          </template>
        </div>
      </div>
    </div>

    <!-- Lightbox: Visualizar Mídia -->
    <div
      v-if="lightboxMedia"
      class="fixed inset-0 z-[99999] bg-black/90 backdrop-blur-sm flex flex-col"
      @click.self="lightboxMedia = null"
    >
      <!-- Header -->
      <div
        class="flex items-center justify-between px-6 py-4 border-b border-white/10"
      >
        <div class="flex flex-col">
          <span class="text-sm font-medium text-slate-100">{{
            lightboxMedia.file_name || 'Arquivo'
          }}</span>
          <span class="text-xs text-slate-400 uppercase mt-0.5">{{
            lightboxMedia.category
          }}</span>
        </div>
        <div class="flex items-center gap-2">
          <a
            :href="lightboxMedia.url"
            target="_blank"
            rel="noopener noreferrer"
            class="h-9 px-3 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 text-xs flex items-center gap-1.5 transition-colors border-0 cursor-pointer no-underline"
          >
            <i class="i-lucide-external-link" /> Abrir
          </a>
          <button
            class="h-9 w-9 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 flex items-center justify-center transition-colors border-0 cursor-pointer"
            @click="lightboxMedia = null"
          >
            <i class="i-lucide-x" />
          </button>
        </div>
      </div>
      <!-- Conteúdo -->
      <div class="flex-1 flex items-center justify-center p-4 overflow-hidden">
        <!-- PDF: embed via iframe -->
        <template
          v-if="
            lightboxMedia.mime_type?.includes('pdf') ||
            lightboxMedia.file_name?.toLowerCase().endsWith('.pdf')
          "
        >
          <iframe
            :src="lightboxMedia.url"
            class="w-full h-full rounded-lg bg-white"
            style="max-height: calc(100vh - 120px)"
          />
        </template>
        <!-- Imagem -->
        <template v-else>
          <img
            :src="lightboxMedia.url"
            class="max-w-full max-h-full object-contain rounded-lg"
            style="max-height: calc(100vh - 120px)"
          />
        </template>
      </div>
    </div>

    <!-- Modal Excluir Plano de Tratamento -->
    <div
      v-if="showConfirmDeletePlan"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999] bg-black/60"
      @click.self="cancelDeletePlan"
    >
      <div
        class="delete-modal-card rounded-2xl w-full max-w-[420px] overflow-hidden bg-[linear-gradient(145deg,#1e293b,#0f172a)] border border-white/5 shadow-[0_25px_50px_-12px_rgba(0,0,0,0.5)]"
      >
        <div class="p-6">
          <div class="flex items-start gap-4">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
            >
              <i class="i-lucide-alert-triangle size-5 text-rose-500" />
            </div>
            <div class="flex flex-col gap-2 pt-1">
              <h3 class="font-medium text-slate-100 m-0 text-lg leading-tight">
                Excluir Plano de Tratamento?
              </h3>
              <p class="text-slate-400 m-0 text-sm leading-relaxed">
                Tem certeza que deseja excluir este plano? Esta ação é
                irreversível e todos os procedimentos serão apagados.
              </p>
            </div>
          </div>
        </div>
        <div class="px-6 py-4 flex justify-end gap-3 border-t border-white/5">
          <button
            class="rounded-lg px-4 py-2 text-sm font-medium bg-transparent text-slate-400 hover:text-slate-100 transition-colors border-0 cursor-pointer"
            @click="cancelDeletePlan"
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-rose-500 hover:text-rose-400 hover:bg-rose-500/10 bg-transparent transition-all border-0 cursor-pointer"
            @click="confirmDeletePlan"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>

    <!-- Modal Excluir Sessão (Procedimento) -->
    <div
      v-if="showConfirmDeleteSession"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999]"
      style="background: rgba(0, 0, 0, 0.4)"
      @click.self="cancelDeleteSessionLog"
    >
      <div
        class="delete-modal-card rounded-2xl w-full max-w-[420px] overflow-hidden"
        style="
          background: rgb(var(--slate-1));
          border: 1px solid rgb(var(--slate-4));
          box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.15);
        "
      >
        <div class="p-6">
          <div class="flex items-start gap-4">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
            >
              <i class="i-lucide-alert-triangle size-5 text-rose-500" />
            </div>
            <div class="flex flex-col gap-2 pt-1">
              <h3
                class="font-medium m-0 text-lg leading-tight"
                style="color: rgb(var(--slate-12))"
              >
                Excluir Registro de Sessão?
              </h3>
              <p
                class="m-0 text-sm leading-relaxed"
                style="color: rgb(var(--slate-10))"
              >
                Deseja remover este registro de sessão? Esta ação não pode ser
                desfeita.
              </p>
            </div>
          </div>
        </div>
        <div
          class="px-6 py-4 flex justify-end gap-3"
          style="border-top: 1px solid rgb(var(--slate-4))"
        >
          <button
            class="rounded-lg px-4 py-2 text-sm font-medium cursor-pointer"
            style="
              background: transparent;
              border: 1px solid #cbd5e1;
              color: #475569;
            "
            onmouseover="this.style.backgroundColor='#f1f5f9'; this.style.borderColor='#94a3b8'; this.style.color='#334155'"
            onmouseout="this.style.backgroundColor='transparent'; this.style.borderColor='#cbd5e1'; this.style.color='#475569'"
            @click="cancelDeleteSessionLog"
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold border-0 cursor-pointer"
            style="background: #ef4444; color: #ffffff"
            onmouseover="this.style.backgroundColor='#dc2626'"
            onmouseout="this.style.backgroundColor='#ef4444'"
            @click="confirmDeleteSessionLog"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>

    <!-- FAB Mobile: Abrir Sidebar -->
    <button
      class="lg:hidden fixed bottom-6 right-6 w-14 h-14 bg-n-alpha-2 backdrop-blur-lg shadow hover:shadow-md border border-n-strong text-n-slate-12 rounded-full flex items-center justify-center z-30 transition-all duration-200 active:scale-95 hover:brightness-110"
      @click="isSidebarOpen = true"
    >
      <i class="i-lucide-menu w-6 h-6" />
    </button>
  </div>
</template>

<style scoped>
@media print {
  .hide-on-print {
    display: none !important;
  }
  body,
  .record-container {
    background: white !important;
    color: black !important;
  }
  .record-header,
  .menu-sidebar {
    display: none !important;
  }
  .record-layout {
    display: block !important;
    padding: 0 !important;
    max-width: 100% !important;
  }
  .main-content {
    margin: 0 !important;
    padding: 0 !important;
    width: 100% !important;
  }
  .tab-pane {
    animation: none !important;
  }
  .card,
  .form-section {
    box-shadow: none !important;
    border: 1px solid #ccc !important;
    background: white !important;
    color: black !important;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  * {
    color: black !important;
  }
  .print-section {
    width: 100% !important;
    max-width: 100% !important;
    padding: 0 !important;
    margin: 0 !important;
  }
  .print-card {
    box-shadow: none !important;
    border: 1px solid #ccc !important;
    break-inside: avoid;
    break-after: auto;
    page-break-inside: avoid;
  }
  .page-break-inside-avoid {
    break-inside: avoid;
    page-break-inside: avoid;
  }
}

.critical-popup-body {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.status-select {
  padding: 4px 28px 4px 12px !important;
  font-size: 13px !important;
  font-weight: 500 !important;
  height: 32px !important;
  width: auto !important;
  margin-top: 4px;
}

/* Patient status badge — colored static tag in header */
.patient-status-badge {
  display: inline-flex;
  align-items: center;
  padding: 3px 12px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
  margin-top: 4px;
  letter-spacing: 0.02em;
  width: fit-content;
  max-width: fit-content;
  align-self: flex-start;
}
.patient-status-badge.status-novo {
  background: rgba(59, 130, 246, 0.15);
  color: #60a5fa;
  border: 1px solid rgba(59, 130, 246, 0.3);
}
.patient-status-badge.status-ativo {
  background: rgba(34, 197, 94, 0.15);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.3);
}
.patient-status-badge.status-inativo {
  background: rgba(100, 116, 139, 0.15);
  color: #94a3b8;
  border: 1px solid rgba(100, 116, 139, 0.3);
}
.patient-status-badge.status-faltoso {
  background: rgba(234, 179, 8, 0.15);
  color: #fde047;
  border: 1px solid rgba(234, 179, 8, 0.3);
}
.patient-status-badge.status-alta {
  background: rgba(168, 85, 247, 0.15);
  color: #c084fc;
  border: 1px solid rgba(168, 85, 247, 0.3);
}
.patient-status-badge.status-arquivado {
  background: rgba(71, 85, 105, 0.15);
  color: #64748b;
  border: 1px solid rgba(71, 85, 105, 0.3);
}

.record-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  background: var(--color-background, #121212);
  color: #f1f5f9;
  padding: 24px 32px;
  box-sizing: border-box;
  overflow-y: auto;
  font-family: inherit;
}

/* ====== HEADER/TOP ACTIONS ====== */
.header-nav {
  margin-bottom: 24px;
}

.btn-back {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  background: transparent;
  border: none;
  color: #94a3b8;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  padding: 0 16px;
  min-height: 36px;
  border-radius: 8px;
  transition: all 0.2s;
}

.btn-back:hover {
  color: #f1f5f9;
}

.btn-primary,
.btn-secondary {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 16px;
  height: 40px;
  border-radius: 8px;
  font-weight: 500;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.2s ease;
}

.btn-primary {
  background: #3b82f6;
  color: #fff;
  border: none;
  box-shadow: none;
}
.btn-primary:hover {
  background: #2563eb;
}

.btn-secondary {
  background: rgba(255, 255, 255, 0.05);
  color: #e2e8f0;
  border: 1px solid rgba(255, 255, 255, 0.1);
  box-shadow: none;
}
.btn-secondary:hover {
  background: rgba(255, 255, 255, 0.1);
}

.record-layout {
  display: flex;
  gap: 24px;
  align-items: flex-start;
  min-height: min-content; /* Ensure container can grow with content */
}

.menu-sidebar {
  flex: 0 0 240px;
  max-width: 240px;
  position: sticky;
  top: 132px; /* Fix the left menu underneath the header banner */
  overflow-y: auto; /* Adiciona scroll interno no menu se as abas passarem do viewport */
  border-radius: 16px;
  padding: 12px;
}

/* Esconde scrollbar do menu para manter a estética limpa */
.menu-sidebar::-webkit-scrollbar {
  width: 4px;
}
.menu-sidebar::-webkit-scrollbar-track {
  background: transparent;
}
.menu-sidebar::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.1);
  border-radius: 4px;
}
.menu-sidebar::-webkit-scrollbar-thumb:hover {
  background: rgba(255, 255, 255, 0.2);
}

.main-content {
  flex: 1;
  min-width: 0; /* Previne overlay de flex children */
  display: flex;
  flex-direction: column;
}

@media (max-width: 1024px) {
  .record-layout {
    flex-direction: column;
  }
  .profile-sidebar {
    flex: none;
    max-width: 100%;
    position: static;
  }
}

/* NAVEGAÇÃO DE ABAS VERTICAL */
.vertical-tabs-nav {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.vertical-tab-btn {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  background: transparent;
  border: none;
  border-radius: 8px;
  color: rgb(var(--slate-10));
  font-size: 14px;
  font-weight: 500;
  text-align: left;
  cursor: pointer;
  transition: all 0.2s;
}

.vertical-tab-btn i {
  font-size: 16px;
  flex-shrink: 0;
}

.vertical-tab-btn:hover {
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-3));
}

.vertical-tab-btn.active {
  color: #3b82f6;
  background: rgba(59, 130, 246, 0.1);
}

/* CONTEÚDO DAS ABAS */
.tab-content-area {
  display: flex;
  flex-direction: column;
  gap: 24px;
}

.fade-in {
  animation: fadeIn 0.3s ease-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(5px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* CARDS PADRÃO */
.card {
  background: #1c1c1d;
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 16px;
  padding: 24px;
}

.card-title {
  margin: 0 0 16px;
  font-size: 16px;
  font-weight: 600;
  color: #f1f5f9;
}

/* ==================================

   NOVO: ESTILOS DO CADASTRO
==================================== */

/* ── Header do Cadastro ── */
.reg-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

/* ── Barra de progresso ── */
.reg-progress-track {
  height: 4px;
  background: rgba(255, 255, 255, 0.08);
  border-radius: 99px;
  overflow: hidden;
}

.reg-progress-fill {
  height: 100%;
  background: linear-gradient(90deg, #3b82f6, #60a5fa);
  border-radius: 99px;
  transition: width 0.4s ease;
}

/* ── Layout das seções ── */
.reg-form-grid {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* ── Seção colapsável ── */
.reg-section {
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
  overflow: hidden;
}

.reg-section-toggle {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  background: transparent;
  border: none;
  cursor: pointer;
  text-align: left;
  color: inherit;
  transition: background 0.15s;
}

.reg-section-toggle:hover {
  background: rgba(255, 255, 255, 0.03);
}

.reg-section-toggle-left {
  display: flex;
  align-items: center;
  gap: 14px;
}

.reg-section-icon {
  width: 36px;
  height: 36px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.reg-icon-blue {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}
.reg-icon-green {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
}
.reg-icon-amber {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
}
.reg-icon-purple {
  background: rgba(168, 85, 247, 0.1);
  color: #c084fc;
}
.reg-icon-cyan {
  background: rgba(6, 182, 212, 0.1);
  color: #22d3ee;
}
.reg-icon-red {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
}
.reg-icon-orange {
  background: rgba(249, 115, 22, 0.1);
  color: #fb923c;
}

/* ── Label de campo ── */
.form-label {
  display: block;
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-11));
  margin-bottom: 6px;
}

/* ── Checkbox customizado (check-item) - Light Mode ── */
.check-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  border-radius: 8px;
  cursor: pointer;
  user-select: none;
}

.check-item input[type='checkbox'] {
  position: absolute;
  opacity: 0;
  width: 0;
  height: 0;
  pointer-events: none;
}

.check-item-box {
  width: 18px;
  min-width: 18px;
  height: 18px;
  border-radius: 5px;
  border: 1.5px solid rgb(var(--slate-3));
  background: #ffffff;
  display: flex;
  align-items: center;
  justify-content: center;
  transition:
    background 0.15s,
    border-color 0.15s;
  flex-shrink: 0;
}

.check-item:hover .check-item-box {
  border-color: rgb(var(--slate-4));
}

.check-item input[type='checkbox']:checked + .check-item-box {
  background: #3b82f6;
  border-color: #3b82f6;
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 12 10' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 5l3 3 7-7' stroke='white' stroke-width='1.8' fill='none' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: center;
  background-size: 10px;
}

.check-item input[type='checkbox']:disabled + .check-item-box {
  background: rgb(var(--slate-2));
  border-color: rgb(var(--slate-3));
  cursor: not-allowed;
}

/* garante que checkbox marcado + disabled (ex: anamnese finalizada)
   continue visualmente marcado — a regra :disabled acima sobrescrevia :checked */
.check-item input[type='checkbox']:checked:disabled + .check-item-box {
  background: #3b82f6;
  border-color: #3b82f6;
  opacity: 0.7;
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 12 10' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 5l3 3 7-7' stroke='white' stroke-width='1.8' fill='none' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: center;
  background-size: 10px;
}

.check-item-label {
  font-size: 14px;
  color: rgb(var(--slate-11));
  font-weight: 500;
  line-height: 1.4;
}

.check-item input[type='checkbox']:disabled ~ .check-item-label {
  color: rgb(var(--slate-8));
}

/* ── Grid de checkboxes (2 colunas para histórico de saúde) ── */
.anm-check-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0;
}

/* ── Coluna de checkboxes (1 coluna para cirúrgico) ── */
.anm-check-col {
  display: flex;
  flex-direction: column;
  gap: 0;
}

/* ── Tags de alergias / medicamentos ── */
.anm-tags-row {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 8px;
}

.anm-tag {
  display: inline-flex;
  align-items: center;
  font-size: 12px;
  font-weight: 500;
  padding: 2px 10px;
  border-radius: 99px;
  border: 1px solid transparent;
}

.anm-tag--red {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.2);
}
.anm-tag-remove {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  margin-left: 6px;
  padding: 0;
  width: 14px;
  height: 14px;
  border: none;
  background: transparent;
  color: currentColor;
  opacity: 0.6;
  cursor: pointer;
  border-radius: 3px;
  transition: opacity 0.15s, background 0.15s;
}
.anm-tag-remove:hover {
  opacity: 1;
  background: rgba(255, 255, 255, 0.08);
}

.anm-tag--blue {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}

/* ── Label de alerta (alergias) ── */
.anm-label-danger {
  display: flex;
  align-items: center;
  gap: 5px;
  color: #f87171;
  font-size: 13px;
  font-weight: 500;
  margin-bottom: 6px;
}

/* ── Input de alergias com borda vermelha sutil ── */
.anm-input-danger {
  border-color: rgba(239, 68, 68, 0.3) !important;
}

.anm-input-danger:focus {
  border-color: #ef4444 !important;
}

/* ── Card de observações confidenciais ── */
.anm-notes-card {
  background: rgba(251, 191, 36, 0.04);
  border: 1px solid rgba(251, 191, 36, 0.15);
  border-radius: 10px;
  padding: 16px;
}

.anm-notes-input {
  border-color: rgba(251, 191, 36, 0.2) !important;
}

.anm-notes-input:focus {
  border-color: rgba(251, 191, 36, 0.5) !important;
}

/* ════════════════════════════════════════
   ABA GERAL — estilos específicos
   ════════════════════════════════════════ */

/* Banner de alertas críticos */
.geral-alert-banner {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  background: rgba(239, 68, 68, 0.07);
  border: 1px solid rgba(239, 68, 68, 0.2);
  border-radius: 12px;
  padding: 14px 16px;
}

.geral-alert-icon {
  width: 32px;
  min-width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgba(239, 68, 68, 0.13);
  color: #f87171;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.geral-alert-body {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.geral-alert-title {
  font-size: 13px;
  font-weight: 600;
  color: #f87171;
}

.geral-alert-text {
  font-size: 13px;
  color: #fca5a5;
}

/* Nota fixada */
.geral-pinned-note {
  display: flex;
  align-items: center;
  gap: 10px;
  background: rgba(251, 191, 36, 0.05);
  border: 1px solid rgba(251, 191, 36, 0.15);
  border-radius: 10px;
  padding: 12px 16px;
}

/* Botão de ação inline no header das seções */
.geral-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 8px;
  padding: 5px 10px;
  cursor: pointer;
  transition:
    color 0.15s,
    background 0.15s,
    border-color 0.15s;
  white-space: nowrap;
  flex-shrink: 0;
}

.geral-action-btn:hover {
  color: #e2e8f0;
  background: rgba(255, 255, 255, 0.06);
  border-color: rgba(255, 255, 255, 0.14);
}

/* Botão de topo (Editar Ficha, Agendar Consulta) seguindo o Style Guide */
.geral-header-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  padding: 8px 14px;
  cursor: pointer;
  transition: all 0.15s ease;
  box-shadow: none !important;
  white-space: nowrap;
  flex-shrink: 0;
}

.geral-header-btn:hover {
  background: rgb(var(--slate-3));
  border-color: rgb(var(--slate-5));
}

/* Tags clínicas row */
.geral-tags-row {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

/* Título do plano de tratamento ativo */
.geral-plan-title {
  font-size: 15px;
  font-weight: 600;
  color: #e2e8f0;
  line-height: 1.3;
}

/* Divisor interno */
.geral-divider {
  height: 1px;
  background: rgba(255, 255, 255, 0.06);
  margin: 16px 0;
}

/* Linha do profissional responsável */
.geral-prof-row {
  display: flex;
  align-items: center;
  gap: 10px;
}

.geral-prof-avatar {
  width: 32px;
  min-width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  display: flex;
  align-items: center;
  justify-content: center;
}

/* Meta itens (unidade, origem) */
.geral-meta-row {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 4px;
}

.geral-meta-item {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.geral-meta-label {
  font-size: 12px;
  color: #475569;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.geral-meta-value {
  font-size: 14px;
}

/* Cards de consulta (última / próxima) */
.geral-visit-card {
  display: flex;
  align-items: center;
  gap: 14px;
}

.geral-visit-icon {
  width: 40px;
  min-width: 40px;
  height: 40px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.geral-visit-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.geral-visit-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.geral-visit-date {
  font-size: 15px;
  font-weight: 600;
}

.geral-visit-date--highlight {
  color: #4ade80;
}

.geral-visit-time {
  font-size: 12px;
  color: #64748b;
}

.geral-visit-empty {
  font-size: 13px;
  color: #475569;
  font-style: italic;
}

/* ════════════════════════════════════════
   ABA EVOLUÇÃO — estilos específicos
   ════════════════════════════════════════ */

/* Textareas de corpo */
.evo-textarea {
  min-height: 90px;
  resize: vertical;
}

.evo-textarea-sm {
  min-height: 70px;
  resize: vertical;
}

/* Footer: retorno + botões na mesma linha */
.evo-footer-row {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}

/* Remover setinhas do input number */
.no-spinners::-webkit-inner-spin-button,
.no-spinners::-webkit-outer-spin-button {
  -webkit-appearance: none;
  margin: 0;
}
.no-spinners {
  -moz-appearance: textfield;
}

.evo-retorno {
  flex: 1;
  min-width: 180px;
}

.evo-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-shrink: 0;
  padding-bottom: 1px;
}

/* Empty state */
.evo-empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 32px 16px;
  text-align: center;
}

.evo-empty-icon {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #475569;
}

.evo-empty-text {
  font-size: 14px;
  color: #475569;
}

/* Card de nota individual */
.evo-note-card {
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-left: 3px solid transparent;
  background: rgba(255, 255, 255, 0.02);
  overflow: hidden;
}

.evo-note-card + .evo-note-card {
  margin-top: 12px;
}

.evo-note-card--signed {
  border-left-color: rgba(34, 197, 94, 0.5);
}

.evo-note-card--draft {
  border-left-color: rgba(100, 116, 139, 0.3);
}

/* Header do card de nota */
.evo-note-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px;
  border-bottom: 1px solid rgb(var(--slate-4));
  gap: 12px;
}

.evo-note-header-left {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

/* Ícone de status da nota */
.evo-note-status-icon {
  width: 28px;
  min-width: 28px;
  height: 28px;
  border-radius: 7px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.evo-note-status-icon--signed {
  background: rgba(34, 197, 94, 0.12);
  color: #4ade80;
}

.evo-note-status-icon--draft {
  background: rgba(100, 116, 139, 0.12);
  color: #64748b;
}

/* Título e meta da nota */
.evo-note-title {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.evo-note-badge {
  font-size: 10px;
  font-weight: 600;
  padding: 1px 7px;
  border-radius: 99px;
  letter-spacing: 0.03em;
}

.evo-note-badge--signed {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.2);
}

.evo-note-badge--draft {
  background: rgba(100, 116, 139, 0.1);
  color: #64748b;
  border: 1px solid rgba(100, 116, 139, 0.2);
}

.evo-note-meta {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: rgb(var(--slate-9));
  margin-top: 2px;
}

.evo-note-meta-sep {
  color: rgb(var(--slate-6));
  margin: 0 2px;
}

/* Botões de ação (Excluir / Editar) */
.evo-note-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

.evo-note-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  font-weight: 500;
  padding: 4px 10px;
  border-radius: 7px;
  border: 1px solid rgb(var(--slate-4));
  background: transparent;
  color: rgb(var(--slate-9));
  cursor: pointer;
  transition:
    color 0.15s,
    background 0.15s,
    border-color 0.15s;
}

.evo-note-btn:hover {
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-2));
  border-color: rgb(var(--slate-6));
}

.evo-note-btn--danger {
  color: rgb(var(--color-danger-dark));
  border-color: rgba(var(--color-danger-rgb), 0.2);
}

.evo-note-btn--danger:hover {
  color: rgb(var(--color-danger-dark));
  background: rgba(var(--color-danger-rgb), 0.08);
  border-color: rgba(var(--color-danger-rgb), 0.3);
}

/* Corpo do card de nota */
.evo-note-body {
  display: flex;
  flex-direction: column;
  gap: 0;
  padding: 0 16px 16px;
}

.evo-note-field {
  display: grid;
  grid-template-columns: 110px 1fr;
  gap: 8px;
  padding: 10px 0;
  border-bottom: 1px solid rgb(var(--slate-3));
  align-items: baseline;
}

.evo-note-field:last-child {
  border-bottom: none;
}

.evo-note-field-label {
  font-size: 12px;
  font-weight: 700;
  color: #0f172a;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  line-height: 1.5;
}

.evo-note-field-value {
  font-size: 14px;
  font-weight: 500;
  color: #475569;
  line-height: 1.5;
  white-space: pre-wrap;
}

/* ════════════════════════════════════════
   ABA PLANO DE TRATAMENTO — tp-*
   ════════════════════════════════════════ */

/* Card principal de um plano */
.tp-plan-card {
  border-radius: 12px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: rgba(255, 255, 255, 0.02);
  overflow: hidden;
  margin-bottom: 20px;
}

/* Cabeçalho do plano (título + ações) */
.tp-plan-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
  background: rgba(255, 255, 255, 0.015);
  gap: 12px;
  flex-wrap: wrap;
}

.tp-plan-header-left {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.tp-plan-title-text {
  font-size: 14px;
}

.tp-plan-actions {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-shrink: 0;
}

/* Badge de status aprovado */
.tp-status-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  font-weight: 600;
  padding: 3px 10px;
  border-radius: 99px;
  letter-spacing: 0.03em;
}

.tp-status-badge--approved {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.2);
}

/* Botão aprovar */
.tp-btn-approve {
  color: #4ade80 !important;
  border-color: rgba(34, 197, 94, 0.25) !important;
}

.tp-btn-approve:hover {
  background: rgba(34, 197, 94, 0.08) !important;
  border-color: rgba(34, 197, 94, 0.4) !important;
}

/* Botão de PDF */
.tp-btn-pdf {
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.25);
}

.tp-btn-pdf:hover {
  background: rgba(59, 130, 246, 0.08);
}

/* Sub-seção interna (diagnóstico, procedimentos, observações) */
.tp-plan-section {
  border-top: 1px solid rgba(255, 255, 255, 0.04);
}

.tp-plan-section:first-of-type {
  border-top: none;
}

/* Header de sub-seção */
.tp-section-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 20px;
  background: rgba(255, 255, 255, 0.015);
  border-bottom: 1px solid rgba(255, 255, 255, 0.04);
}

.tp-section-label {
  font-size: 12px;
  font-weight: 600;
  color: #475569;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

/* Corpo das sub-seções */
.tp-section-body {
  padding: 16px 20px;
}

/* Grid de diagnóstico (2 colunas) */
.tp-diag-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
}

@media (max-width: 640px) {
  .tp-diag-grid {
    grid-template-columns: 1fr;
  }
}

.tp-diag-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.tp-diag-label {
  font-size: 11px;
  font-weight: 600;
  color: #475569;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.tp-diag-value {
  font-size: 14px;
  color: #cbd5e1;
  margin: 0;
  line-height: 1.5;
}

/* Wrapper de tabela */
.tp-table-wrap {
  padding: 0;
  overflow-x: auto;
}

/* Tabela de procedimentos */
.tp-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  text-align: left;
}

.tp-table-head tr {
  background: rgba(255, 255, 255, 0.02);
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
}

.tp-table-head th {
  padding: 10px 20px;
  font-size: 11px;
  font-weight: 600;
  color: #475569;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  white-space: nowrap;
}

.tp-table-empty {
  padding: 28px 20px;
  text-align: center;
  color: #475569;
  font-size: 13px;
}

.tp-table-row {
  border-bottom: 1px solid rgba(255, 255, 255, 0.03);
  transition: background 0.12s;
}

.tp-table-row:last-child {
  border-bottom: none;
}

.tp-table-row:hover {
  background: rgba(255, 255, 255, 0.02);
}

.tp-table-cell {
  padding: 10px 20px;
  vertical-align: middle;
}

.tp-cell-name {
  color: #e2e8f0;
  font-weight: 500;
}

.tp-cell-muted {
  color: #64748b;
}

/* Badge de status de item */
.tp-item-status {
  display: inline-block;
  font-size: 10px;
  font-weight: 700;
  padding: 2px 8px;
  border-radius: 99px;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.tp-item-status--proposto {
  background: rgba(59, 130, 246, 0.08);
  color: #60a5fa;
  border: 1px solid rgba(59, 130, 246, 0.18);
}

.tp-item-status--aprovado {
  background: rgba(34, 197, 94, 0.08);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.18);
}

/* Botões de linha (editar/remover) */
.tp-row-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
}

.tp-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  background: transparent;
  border: 1px solid transparent;
  color: #475569;
  cursor: pointer;
  transition:
    color 0.12s,
    background 0.12s,
    border-color 0.12s;
}

.tp-icon-btn:hover {
  color: #93c5fd;
  background: rgba(59, 130, 246, 0.08);
  border-color: rgba(59, 130, 246, 0.2);
}

.tp-icon-btn--danger:hover {
  color: #f87171;
  background: rgba(239, 68, 68, 0.08);
  border-color: rgba(239, 68, 68, 0.2);
}

/* Total estimado */
.tp-total-row {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 16px;
  padding: 12px 20px;
  background: rgba(0, 0, 0, 0.15);
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}

.tp-total-label {
  font-size: 11px;
  font-weight: 600;
  color: #475569;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}

.tp-total-value {
  font-size: 18px;
  font-weight: 700;
  color: #34d399;
}

/* Grid de observações (2 colunas) */
.tp-obs-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 20px;
  margin-bottom: 16px;
}

@media (max-width: 640px) {
  .tp-obs-grid {
    grid-template-columns: 1fr;
  }
}

/* Rodapé do plano */
.tp-plan-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-top: 14px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
  gap: 12px;
  flex-wrap: wrap;
}

.tp-approval-info {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: #475569;
}

.reg-section-title {
  display: block;
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  line-height: 1.2;
}

.reg-section-subtitle {
  display: block;
  font-size: 12px;
  color: rgb(var(--slate-10));
  margin-top: 2px;
}

.reg-chevron {
  color: #475569;
  transition: transform 0.2s ease;
  flex-shrink: 0;
}

.reg-chevron-open {
  transform: rotate(180deg);
}

/* ── Corpo expandido da seção ── */
.reg-section-body {
  padding: 20px;
  display: flex;
  flex-direction: column;
  gap: 16px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}

/* ── Grids de campos ── */
.reg-field-grid-2 {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 14px;
}

.reg-field-grid-3 {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 14px;
}

.reg-field-grid-cep {
  display: grid;
  grid-template-columns: 160px 1fr;
  gap: 14px;
}

@media (max-width: 768px) {
  .reg-field-grid-2,
  .reg-field-grid-3,
  .reg-field-grid-cep {
    grid-template-columns: 1fr;
  }
}

/* ── Divisor interno ── */
.reg-divider {
  height: 1px;
  background: rgba(255, 255, 255, 0.05);
  margin: 0;
}

/* ── Rótulo de subseção ── */
.reg-subsection-label {
  font-size: 11px;
  font-weight: 600;
  color: #475569;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  margin-bottom: -6px;
}

/* ── Campo obrigatório ── */
.reg-required {
  color: #f87171;
  margin-left: 2px;
}

/* ── Badge WhatsApp ── */
.reg-badge-wpp {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  font-size: 10px;
  font-weight: 500;
  color: #4ade80;
  background: rgba(34, 197, 94, 0.1);
  border: 1px solid rgba(34, 197, 94, 0.2);
  padding: 1px 6px;
  border-radius: 99px;
  margin-left: 6px;
  vertical-align: middle;
}

/* ── Dropdown de busca de contato ── */
.reg-field-relative {
  position: relative;
}

.reg-contact-dropdown {
  position: absolute;
  top: calc(100% + 4px);
  left: 0;
  right: 0;
  z-index: 200;
  background: #1e2433;
  border: 1px solid rgba(148, 163, 184, 0.15);
  border-radius: 10px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
  overflow: hidden;
}

.reg-dropdown-loading {
  padding: 12px 16px;
  font-size: 13px;
  color: #94a3b8;
  text-align: center;
}

.reg-dropdown-list {
  list-style: none;
  margin: 0;
  padding: 4px;
  max-height: 240px;
  overflow-y: auto;
}

.reg-dropdown-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 10px;
  border-radius: 7px;
  cursor: pointer;
  transition: background 0.15s;
}

.reg-dropdown-item:hover {
  background: rgba(148, 163, 184, 0.08);
}

.reg-item-avatar {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 13px;
  font-weight: 600;
  color: #fff;
  flex-shrink: 0;
}

.reg-item-avatar--img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}

.reg-item-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}

.reg-item-name {
  font-size: 13px;
  font-weight: 500;
  color: #e2e8f0;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.reg-item-phone {
  font-size: 11px;
  color: #64748b;
}

/* ── Avatar Upload Premium ── */
.reg-avatar-row {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 4px 0;
}

.reg-avatar-wrapper {
  position: relative;
  width: 80px;
  height: 80px;
  flex-shrink: 0;
  cursor: pointer;
  border-radius: 50%;
  overflow: hidden;
}

.reg-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
  border: 2px solid rgba(255, 255, 255, 0.1);
}

.reg-avatar-placeholder {
  width: 100%;
  height: 100%;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #3b82f6, #8b5cf6);
  font-size: 26px;
  font-weight: 700;
  color: #fff;
  border: 2px solid rgba(255, 255, 255, 0.1);
}

.reg-avatar-overlay {
  position: absolute;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  border-radius: 50%;
  opacity: 0;
  transition: opacity 0.2s;
}

.reg-avatar-wrapper:hover .reg-avatar-overlay {
  opacity: 1;
}

.reg-avatar-info {
  flex: 1;
}

/* ── Botões pequenos ── */
.btn-xs {
  padding: 5px 12px !important;
  height: auto !important;
  font-size: 12px !important;
}

/* ── Toggle Switch ── */
.reg-opt-in-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}

@media (max-width: 640px) {
  .reg-opt-in-grid {
    grid-template-columns: 1fr;
  }
}

.reg-opt-in-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 14px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.02);
  cursor: pointer;
  transition:
    border-color 0.15s,
    background 0.15s;
}

.reg-opt-in-card:hover {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.12);
}

.reg-opt-in-info {
  display: flex;
  align-items: center;
  gap: 10px;
}

.reg-toggle {
  width: 38px;
  height: 22px;
  border-radius: 99px;
  background: rgb(206 206 206);
  position: relative;
  flex-shrink: 0;
  transition: background 0.2s;
  cursor: pointer;
}

.reg-toggle-on {
  background: #3b82f6;
}

.reg-toggle-thumb {
  position: absolute;
  top: 3px;
  left: 3px;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: #fff;
  transition: transform 0.2s ease;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.4);
}

.reg-toggle-on .reg-toggle-thumb {
  transform: translateX(16px);
}

/* =====================================
   MODAL DE CÂMERA PREMIUM (Light Mode adaptado)
===================================== */
.cam-modal {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-3));
  border-radius: 20px;
  overflow: hidden;
  width: 100%;
  max-width: 420px;
  box-shadow:
    0 16px 40px rgba(0, 0, 0, 0.16),
    0 0 0 1px rgba(0, 0, 0, 0.05);
}

.cam-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid rgb(var(--slate-3));
  background: rgb(var(--slate-2));
}

.cam-header-icon {
  width: 34px;
  height: 34px;
  border-radius: 10px;
  background: rgba(59, 130, 246, 0.1);
  color: #3b82f6;
  display: flex;
  align-items: center;
  justify-content: center;
}

.cam-close-btn {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-2));
  color: rgb(var(--slate-6));
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition:
    background 0.15s,
    color 0.15s;
  flex-shrink: 0;
}

.cam-close-btn:hover {
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-9));
}

/* Viewfinder: área do vídeo */
.cam-viewfinder {
  position: relative;
  width: 100%;
  aspect-ratio: 1 / 1;
  background: #000;
  overflow: hidden;
}

.cam-video {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
  transform: scaleX(-1);
}

.cam-captured {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

/* Overlay de guia oval para o rosto */
.cam-guide-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  background: rgba(255, 255, 255, 0.15);
}

.cam-guide-ring {
  width: 200px;
  height: 240px;
  border-radius: 50%;
  border: 2px solid rgba(255, 255, 255, 0.8);
  box-shadow:
    0 0 0 9999px rgba(0, 0, 0, 0.35),
    inset 0 0 0 1px rgba(0, 0, 0, 0.2);
}

/* Overlay de erro */
.cam-error-overlay {
  position: absolute;
  inset: 0;
  z-index: 10;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: rgb(var(--slate-2));
}

/* Barra de controles */
.cam-controls {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 20px 24px;
  background: rgb(var(--slate-2));
  border-top: 1px solid rgb(var(--slate-3));
}

/* Botão fantasma (Cancelar / Repetir) */
.cam-btn-ghost {
  min-width: 80px;
  padding: 8px 14px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-6));
  background: transparent;
  border: none;
  cursor: pointer;
  transition:
    color 0.15s,
    background 0.15s;
}

.cam-btn-ghost:hover {
  color: rgb(var(--slate-9));
  background: rgb(var(--slate-2));
}

/* Botão circular de captura (obturador) */
.cam-btn-capture {
  padding: 0;
  width: 68px;
  min-width: 68px;
  max-width: 68px;
  height: 68px;
  min-height: 68px;
  max-height: 68px;
  aspect-ratio: 1 / 1;
  border-radius: 50%;
  background: transparent;
  border: 3px solid rgb(var(--slate-3));
  box-sizing: border-box;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition:
    border-color 0.15s,
    transform 0.1s;
  flex-shrink: 0;
  align-self: center;
}

.cam-btn-capture:hover:not(:disabled) {
  border-color: rgb(var(--slate-4));
  transform: scale(1.04);
}

.cam-btn-capture:active:not(:disabled) {
  transform: scale(0.94);
}

.cam-btn-capture:disabled {
  opacity: 0.35;
  cursor: not-allowed;
}

/* Disco interno do obturador */
.cam-shutter {
  display: block;
  width: 52px;
  min-width: 52px;
  height: 52px;
  min-height: 52px;
  aspect-ratio: 1 / 1;
  border-radius: 50%;
  background: #ffffff;
  border: 1px solid rgb(var(--slate-2));
  flex-shrink: 0;
  transition:
    transform 0.1s,
    background-color 0.1s;
}

.cam-btn-capture:active:not(:disabled) .cam-shutter {
  transform: scale(0.88);
  background: rgb(var(--slate-1));
}

/* Botão confirmar (Usar foto) */
.cam-btn-confirm {
  min-width: 100px;
  padding: 10px 18px;
  border-radius: 10px;
  font-size: 13px;
  font-weight: 600;
  color: #fff;
  background: #10b981;
  border: none;
  cursor: pointer;
  transition:
    background 0.15s,
    transform 0.1s;
}

.cam-btn-confirm:hover {
  background: #059669;
  transform: scale(1.02);
}

.form-section {
  padding: 24px;
}

.form-section-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
  padding-bottom: 12px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
}

.form-section-header i {
  color: #3b82f6;
  font-size: 20px;
}

.form-section-header h4 {
  font-size: 16px;
  font-weight: 600;
  color: #f1f5f9;
  margin: 0;
}

/* ═══════════════════════════════════════════
   PROCEDIMENTOS – estilos exclusivos
═══════════════════════════════════════════ */

/* Painel de filtro dropdown */
.proc-filter-panel {
  position: absolute;
  right: 0;
  top: calc(100% + 8px);
  z-index: 40;
  width: 360px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.15);
  padding: 16px;
}

.proc-filter-close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 6px;
  color: rgb(var(--slate-9));
  background: transparent;
  border: none;
  cursor: pointer;
  transition:
    background 0.15s,
    color 0.15s;
}
.proc-filter-close:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.proc-filter-group {
  display: flex;
  flex-direction: column;
  gap: 5px;
  width: 100%;
}

.proc-filter-label {
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--slate-11));
}

.proc-filter-input {
  box-sizing: border-box;
  width: 100%;
  padding: 8px 12px;
  font-size: 13px;
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  outline: none;
  min-width: 0;
}
.proc-filter-input:focus {
  border-color: #3b82f6;
}

.proc-filter-date-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  width: 100%;
}

.proc-filter-actions {
  display: flex;
  gap: 8px;
  margin-top: 4px;
}

.proc-filter-btn {
  flex: 1;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 600;
  padding: 8px;
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.15s;
  box-shadow: none;
}
.proc-filter-btn--secondary {
  background: transparent;
  color: #475569; /* slate-600 para alta legibilidade */
  border: 1px solid #cbd5e1; /* slate-300 para borda levemente cinza */
}
.proc-filter-btn--secondary:hover {
  background: #f1f5f9;
  color: #334155;
  border-color: #94a3b8;
}
.proc-filter-btn--primary {
  background: #3b82f6;
  color: #fff;
  border: none;
}
.proc-filter-btn--primary:hover {
  background: #2563eb;
}

/* Input de data no header do formulário */
.proc-date-input {
  width: auto;
  min-width: 140px;
  font-size: 13px;
  padding: 7px 10px;
}

/* Ações do formulário (Fotos + Salvar) */
.proc-form-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  margin-top: 24px;
  padding-top: 20px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}

/* Badge de contagem */
.proc-count-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 24px;
  height: 20px;
  padding: 0 6px;
  background: rgba(100, 116, 139, 0.2);
  color: #94a3b8;
  font-size: 11px;
  font-weight: 600;
  border-radius: 10px;
}

/* Empty state */
.proc-empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 48px 24px;
  text-align: center;
}
.proc-empty-icon {
  width: 44px;
  height: 44px;
  border-radius: 12px;
  background: rgba(100, 116, 139, 0.12);
  color: #475569;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 14px;
}
.proc-empty-text {
  font-size: 14px;
  font-weight: 500;
  color: #64748b;
  margin: 0;
}
.proc-empty-hint {
  font-size: 12px;
  color: #475569;
  margin: 6px 0 0;
}

/* Tabela de sessões */
.proc-table-wrap {
  overflow-x: auto;
  border-radius: 0 0 14px 14px;
}
.proc-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}
.proc-table-head {
  background: rgba(15, 23, 42, 0.4);
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}
.proc-table-head th {
  padding: 10px 16px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #64748b;
  white-space: nowrap;
}
.proc-table-row {
  border-bottom: 1px solid rgba(255, 255, 255, 0.04);
  transition: background 0.12s;
}
.proc-table-row:last-child {
  border-bottom: none;
}
.proc-table-row:hover {
  background: rgba(255, 255, 255, 0.025);
}
.proc-table-cell {
  padding: 14px 16px;
  vertical-align: top;
}
.proc-cell-primary {
  font-weight: 500;
  color: #e2e8f0;
  font-size: 13px;
  line-height: 1.4;
}
.proc-cell-secondary {
  font-size: 11.5px;
  color: #64748b;
  margin-top: 2px;
  line-height: 1.3;
}
.proc-product-item + .proc-product-item {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid rgba(255, 255, 255, 0.04);
}

/* Células de resultado */
.proc-cell-resultado {
  max-width: 260px;
}
.proc-result-row {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  font-size: 12px;
  line-height: 1.4;
  margin-bottom: 5px;
}
.proc-result-row:last-child {
  margin-bottom: 0;
}

/* Botão de ação (lixeira) */
.proc-action-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 8px;
  border: none;
  background: transparent;
  color: #475569;
  cursor: pointer;
  transition:
    background 0.15s,
    color 0.15s;
}
.proc-action-btn:hover {
  background: rgba(239, 68, 68, 0.12);
  color: #f87171;
}

/* Required asterisk */
.reg-required {
  color: #f87171;
  margin-left: 2px;
}

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
  border: 1px solid rgba(255, 255, 255, 0.35);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  transition: background 0.2s, border-color 0.2s;
}
.exams-card:hover .exams-thumb-eye {
  background: rgba(59, 130, 246, 0.85);
  border-color: rgba(96, 165, 250, 1);
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
  width: 26px;
  height: 26px;
  border-radius: 6px;
  border: none;
  background: transparent;
  color: #475569;
  cursor: pointer;
  transition:
    background 0.12s,
    color 0.12s;
  flex-shrink: 0;
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

/* ═══════════════════════════════════════════
   DOCUMENTOS — estilos exclusivos
═══════════════════════════════════════════ */

/* Ícone de arquivo na tabela */
.docs-file-icon {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgba(59, 130, 246, 0.1);
  border: 1px solid rgba(59, 130, 246, 0.15);
  color: #60a5fa;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

/* Badge de status do documento */
.docs-status-badge {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 11px;
  font-weight: 600;
  border: 1px solid transparent;
}

/* Botão WhatsApp (override da cor do proc-action-btn no hover) */
.docs-action-wa:hover {
  background: rgba(16, 185, 129, 0.1);
  color: #34d399;
}

/* Modal de Gerar Documento */
.docs-modal {
  background: #111318;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 18px;
  box-shadow: 0 32px 80px rgba(0, 0, 0, 0.5);
  width: 100%;
  max-width: 520px;
  display: flex;
  flex-direction: column;
  max-height: 90vh;
  overflow: hidden;
}
.docs-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 20px 24px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  flex-shrink: 0;
}
.docs-modal-icon {
  width: 36px;
  height: 36px;
  border-radius: 9px;
  background: rgba(168, 85, 247, 0.12);
  color: #c084fc;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.docs-modal-close {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  border: none;
  background: transparent;
  color: #475569;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition:
    background 0.15s,
    color 0.15s;
}
.docs-modal-close:hover {
  background: rgba(255, 255, 255, 0.07);
  color: #94a3b8;
}
.docs-modal-body {
  padding: 20px 24px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 16px;
  flex: 1;
}
.docs-modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  padding: 16px 24px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
  flex-shrink: 0;
}

.form-row-1,
.form-row-2,
.form-row-3,
.form-row-cep {
  display: grid;
  gap: 16px;
  margin-bottom: 16px;
}

.form-row-2 {
  grid-template-columns: repeat(2, 1fr);
}
.form-row-3 {
  grid-template-columns: repeat(3, 1fr);
}
.form-row-cep {
  grid-template-columns: 1fr 2fr;
}

@media (max-width: 768px) {
  .form-row-2,
  .form-row-3,
  .form-row-cep {
    grid-template-columns: 1fr;
  }
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-group label {
  font-size: 13px;
  font-weight: 500;
  color: #cbd5e1;
}

.form-input {
  background: rgba(0, 0, 0, 0.2);
  border: 1px solid rgba(255, 255, 255, 0.1);
  color: #f1f5f9;
  border-radius: 8px;
  padding: 10px 14px;
  font-size: 14px;
  font-family: inherit;
  transition: border-color 0.2s;
  width: 100%;
}

.form-textarea {
  resize: vertical;
  min-height: 80px;
}

.form-input:focus {
  outline: none;
  border-color: #3b82f6;
  background: rgba(0, 0, 0, 0.3);
}

.form-input::placeholder {
  color: #475569;
}

select.form-input {
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%2394a3b8' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 12px center;
  padding-right: 40px;
}

.input-with-action {
  position: relative;
  display: flex;
  align-items: center;
}

.btn-icon-inside {
  position: absolute;
  right: 8px;
  background: transparent;
  border: none;
  color: #94a3b8;
  cursor: pointer;
  padding: 4px;
  border-radius: 4px;
}

.btn-icon-inside:hover {
  background: rgba(255, 255, 255, 0.1);
  color: #f1f5f9;
}

.checkbox-group {
  gap: 12px;
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: 10px;
  cursor: pointer;
  font-size: 13px !important;
  color: #cbd5e1 !important;
  font-weight: 400 !important;
}

.checkbox-label input[type='checkbox'] {
  margin-top: 2px;
  accent-color: #3b82f6;
  width: 16px;
  height: 16px;
  cursor: pointer;
}

.avatar-wrapper-small {
  position: relative;
  width: 56px;
  height: 56px;
  display: flex;
  justify-content: center;
}

.avatar-img-small,
.avatar-placeholder-small {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  border: 2px solid rgba(255, 255, 255, 0.05);
  object-fit: cover;
}

.avatar-placeholder-small {
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #3b82f6, #8b5cf6);
  font-size: 20px;
  font-weight: 600;
  color: #fff;
}

.status-badge-small {
  position: absolute;
  bottom: -6px;
  left: 50%;
  transform: translateX(-50%);
  padding: 2px 8px;
  border-radius: 12px;
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  white-space: nowrap;
  border: 2px solid #1c1c1d;
  z-index: 2;
}

.status-em-tratamento {
  background: #fbbf24;
  color: #78350f;
}
.status-novo {
  background: #3b82f6;
  color: #eff6ff;
}
.status-em-avaliação {
  background: #a855f7;
  color: #faf5ff;
}
.status-ativo {
  background: #22c55e;
  color: #022c22;
}
.status-inativo {
  background: #94a3b8;
  color: #0f172a;
}
.status-alta {
  background: #14b8a6;
  color: #042f2e;
}
.status-abandonou {
  background: #ef4444;
  color: #450a0a;
}
.status-faltoso {
  background: #f97316;
  color: #431407;
}

/* ── Header Buttons (hdr-*) ────────────────────────────────── */
.hdr-btn {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 0 13px;
  height: 36px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition:
    background 0.15s,
    border-color 0.15s,
    color 0.15s;
  white-space: nowrap;
  flex-shrink: 0;
  border: 1px solid transparent;
}

.hdr-btn--secondary {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.09);
  color: #94a3b8;
}
.hdr-btn--secondary:hover {
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(255, 255, 255, 0.14);
  color: #e2e8f0;
}

.hdr-btn--charge {
  background: rgba(34, 197, 94, 0.07);
  border-color: rgba(34, 197, 94, 0.18);
  color: #4ade80;
}
.hdr-btn--charge:hover {
  background: rgba(34, 197, 94, 0.13);
  border-color: rgba(34, 197, 94, 0.28);
}

.hdr-btn--primary {
  background: #3b82f6;
  border-color: #3b82f6;
  color: #fff;
}
.hdr-btn--primary:hover {
  background: #2563eb;
  border-color: #2563eb;
}

.hdr-divider {
  width: 1px;
  height: 22px;
  background: rgba(255, 255, 255, 0.08);
  flex-shrink: 0;
}

/* ── Profile Banner ────────────────────────────────────────── */
.profile-banner {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: #1c1c1d;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 12px;
  padding: 16px 20px;
  margin-bottom: 20px;
  position: sticky;
  top: 0;
  z-index: 10;
  gap: 16px;
}

.profile-banner-left {
  display: flex;
  align-items: center;
  gap: 14px;
  min-width: 0;
  flex: 1;
}

/* ── Avatar ── */
.pb-avatar-wrap {
  position: relative;
  flex-shrink: 0;
}

.pb-avatar-img,
.pb-avatar-placeholder {
  width: 52px;
  height: 52px;
  border-radius: 12px;
  object-fit: cover;
  display: flex;
  align-items: center;
  justify-content: center;
}

.pb-avatar-img {
  border: 1px solid rgba(255, 255, 255, 0.1);
}

.pb-avatar-placeholder {
  background: rgba(59, 130, 246, 0.15);
  border: 1px solid rgba(59, 130, 246, 0.2);
  color: #60a5fa;
  font-size: 20px;
  font-weight: 600;
}

.pb-status-dot {
  position: absolute;
  bottom: -3px;
  right: -3px;
  width: 13px;
  height: 13px;
  border-radius: 50%;
  border: 2px solid #0e1016;
}
.pb-dot-novo {
  background: #60a5fa;
}
.pb-dot-ativo {
  background: #4ade80;
}
.pb-dot-inativo {
  background: #94a3b8;
}
.pb-dot-faltoso {
  background: #fbbf24;
}
.pb-dot-alta {
  background: #c084fc;
}
.pb-dot-arquivado {
  background: #64748b;
}

/* ── Identity ── */
.pb-identity {
  display: flex;
  flex-direction: column;
  gap: 5px;
  min-width: 0;
}

.pb-name-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.pb-name {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: #f1f5f9;
  line-height: 1.2;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* ── Meta row ── */
.pb-meta-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.pb-meta-text {
  font-size: 13px;
  color: #64748b;
}

.pb-meta-sep {
  font-size: 12px;
  color: #334155;
}

/* Status pill */
.pb-status-pill {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border: 1px solid transparent;
}
.pb-pill-novo {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}
.pb-pill-ativo {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
  border-color: rgba(34, 197, 94, 0.2);
}
.pb-pill-inativo {
  background: rgba(100, 116, 139, 0.12);
  color: #94a3b8;
  border-color: rgba(100, 116, 139, 0.2);
}
.pb-pill-faltoso {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
  border-color: rgba(251, 191, 36, 0.2);
}
.pb-pill-alta {
  background: rgba(168, 85, 247, 0.1);
  color: #c084fc;
  border-color: rgba(168, 85, 247, 0.2);
}
.pb-pill-arquivado {
  background: rgba(71, 85, 105, 0.1);
  color: #64748b;
  border-color: rgba(71, 85, 105, 0.2);
}

/* ── Info chips ── */
.pb-chips {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 2px;
}

.pb-chip {
  display: flex;
  align-items: center;
  gap: 5px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 6px;
  padding: 3px 8px;
  font-size: 12px;
  color: #94a3b8;
  white-space: nowrap;
  transition:
    background 0.15s,
    border-color 0.15s;
}

.pb-chip-icon {
  color: #475569;
  flex-shrink: 0;
}

/* ── Right side: finance badge ── */
.pb-right {
  flex-shrink: 0;
  display: flex;
  align-items: center;
}

.pb-finance-badge {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 7px 14px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 600;
  border: 1px solid transparent;
}

.pb-finance-adimplente {
  background: rgba(34, 197, 94, 0.08);
  color: #4ade80;
  border-color: rgba(34, 197, 94, 0.18);
}
.pb-finance-inadimplente {
  background: rgba(239, 68, 68, 0.08);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.18);
}
.pb-finance-crédito,
.pb-finance-credito {
  background: rgba(59, 130, 246, 0.08);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.18);
}
.pb-finance-em.pb-finance-aberto {
  background: rgba(251, 191, 36, 0.08);
  color: #fbbf24;
  border-color: rgba(251, 191, 36, 0.18);
}

@media (max-width: 1280px) {
  .hide-mobile {
    display: none;
  }
}

@media (max-width: 1024px) {
  .profile-banner {
    flex-direction: column;
    align-items: flex-start;
    gap: 14px;
    position: static;
  }
  .hide-mobile {
    display: flex;
  }
}

/* POPUP E ÍCONE CLÍNICO */
.critical-alert-container {
  position: relative;
  display: flex;
  align-items: center;
}

.btn-critical-alert {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: rgba(239, 68, 68, 0.15);
  border: 1px solid rgba(239, 68, 68, 0.3);
  color: #ef4444;
  font-size: 20px;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-critical-alert:hover {
  background: rgba(239, 68, 68, 0.25);
  transform: scale(1.05);
}

.critical-popup {
  position: absolute;
  top: calc(100% + 12px);
  left: -3px;
  width: 320px;
  background: #1c1c1d;
  border: 1px solid rgba(239, 68, 68, 0.3);
  border-radius: 12px;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6);
  z-index: 100;
  animation: fadeIn 0.2s ease-out;
  text-align: left;
}

/* Seta pro balãozinho */
.critical-popup::before {
  content: '';
  position: absolute;
  top: -6px;
  left: 14px;
  transform: rotate(45deg);
  width: 10px;
  height: 10px;
  background: #1c1c1d;
  border-top: 1px solid rgba(239, 68, 68, 0.3);
  border-left: 1px solid rgba(239, 68, 68, 0.3);
}

.popup-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
  color: #ef4444;
  font-size: 13px;
  font-weight: 600;
}

.popup-header i {
  font-size: 16px;
}

.btn-close-popup {
  margin-left: auto;
  background: transparent;
  border: none;
  color: #94a3b8;
  cursor: pointer;
  font-size: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
}

.btn-close-popup:hover {
  color: #f1f5f9;
}

.popup-body {
  padding: 12px 16px;
  font-size: 13px;
  color: #cbd5e1;
  line-height: 1.5;
}

.finance-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
}
.finance-adimplente {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
}
.finance-inadimplente {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
}
.finance-crédito {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
}

.divider {
  width: 100%;
  height: 1px;
  background: rgba(255, 255, 255, 0.05);
  margin: 24px 0;
}

.info-list {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 16px;
  text-align: left;
}

.info-item {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}

.info-item i {
  color: #64748b;
  font-size: 18px;
  margin-top: 2px;
  flex-shrink: 0;
}

.info-data {
  display: flex;
  flex-direction: column;
  overflow: hidden; /* Avoid text expanding the card */
}

.info-label {
  font-size: 12px;
  color: #94a3b8;
  margin-bottom: 2px;
}

.info-value {
  font-size: 14px;
  color: #e2e8f0;
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* PLACEHOLDER / STATES */
.placeholder-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 60px 24px;
}

.placeholder-icon {
  font-size: 48px;
  color: rgba(255, 255, 255, 0.05);
  margin-bottom: 20px;
}

.placeholder-card h3 {
  font-size: 18px;
  color: #f1f5f9;
  margin: 0 0 10px;
}

.placeholder-card p {
  color: #94a3b8;
  font-size: 14px;
  margin: 0;
  max-width: 400px;
}

/* TAGS */
.tags-container {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.clinical-tag {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
}

.tag-danger {
  background: rgba(239, 68, 68, 0.15);
  color: #fca5a5;
  border: 1px solid rgba(239, 68, 68, 0.3);
}
.tag-warning {
  background: rgba(245, 158, 11, 0.15);
  color: #fcd34d;
  border: 1px solid rgba(245, 158, 11, 0.3);
}
.tag-info {
  background: rgba(59, 130, 246, 0.15);
  color: #93c5fd;
  border: 1px solid rgba(59, 130, 246, 0.3);
}

.btn-add-tag {
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: 1px dashed rgba(255, 255, 255, 0.2);
  color: #94a3b8;
  padding: 6px 12px;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.2s;
}
.btn-add-tag:hover {
  background: rgba(255, 255, 255, 0.05);
  color: #fff;
}

/* 2 COLS ROW */
.row-2-cols {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
  margin-bottom: 24px;
}

@media (max-width: 768px) {
  .row-2-cols {
    grid-template-columns: 1fr;
  }
}

.detail-group {
  display: flex;
  flex-direction: column;
  margin-bottom: 12px;
}
.detail-group:last-child {
  margin-bottom: 0;
}

.detail-label {
  font-size: 12px;
  color: #94a3b8;
  margin-bottom: 4px;
}

.detail-value {
  font-size: 15px;
  color: #e2e8f0;
}

.detail-value.highlight {
  color: #3b82f6;
  font-weight: 500;
}

.mt-2 {
  margin-top: 16px;
}

.prof-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: rgba(255, 255, 255, 0.05);
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 13px;
  color: #cbd5e1;
  width: fit-content;
}

.status-chip {
  padding: 4px 10px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.status-approved {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.2);
}

.status-pending {
  background: rgba(245, 158, 11, 0.1);
  color: #fbbf24;
  border: 1px solid rgba(245, 158, 11, 0.2);
}

/* TIMELINE E EVOLUÇÃO */
.align-end {
  align-items: flex-end;
}

.timeline-container {
  margin-top: 32px;
  padding-top: 16px;
}

.timeline-wrapper {
  position: relative;
  padding-left: 18px; /* Espaço para o eixo da timeline centralizado com o marcador */
}

/* Linha da timeline conectando os pontos */
.timeline-wrapper::before {
  content: '';
  position: absolute;
  top: 10px;
  bottom: 0;
  left: 18px; /* centraliza a linha exatamente no meio do marcador que tem 36px e fica com `left: 0` */
  width: 2px;
  background: rgba(255, 255, 255, 0.05); /* soft line */
  z-index: 0;
}

.timeline-item {
  position: relative;
  display: flex;
  align-items: stretch;
  z-index: 1; /* z-index maior q a linha para cobrir com bg-color */
}

.timeline-marker {
  position: absolute;
  left: 0;
  top: 0; /* Alinha com o inicio do card */
  width: 36px;
  height: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 16px;
  z-index: 2; /* Importante p sobrepor a linha fina da borda esquerda */
}

.timeline-content {
  flex: 1;
  margin-left: 56px; /* espaço pro icone (36px + 20px gap) */
  margin-bottom: 24px;
}
.timeline-content:hover {
  border-color: rgba(255, 255, 255, 0.15);
}

.visits-grid-2 {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
}

@media (max-width: 640px) {
  .visits-grid-2 {
    grid-template-columns: 1fr;
  }
}

.visit-box {
  display: flex;
  align-items: center;
  gap: 12px;
  background: rgba(0, 0, 0, 0.2);
  padding: 16px;
  border-radius: 12px;
  border: 1px solid rgba(255, 255, 255, 0.03);
}

.visit-box.highlight-box {
  background: rgba(59, 130, 246, 0.1);
  border-color: rgba(59, 130, 246, 0.2);
}

.visit-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  font-size: 18px;
}
.prev {
  background: rgba(148, 163, 184, 0.2);
  color: #cbd5e1;
}
.next {
  background: rgba(59, 130, 246, 0.2);
  color: #60a5fa;
}

.visit-info {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.v-label {
  font-size: 12px;
  color: #94a3b8;
}

.v-date {
  font-size: 14px;
  color: #e2e8f0;
}
.v-date.font-bold {
  font-weight: 600;
  color: #fff;
}

/* compact appointment layout */
.visit-compact-row {
  display: flex;
  align-items: baseline;
  gap: 6px;
  flex-wrap: wrap;
}

.v-time-inline {
  font-size: 12px;
  color: #64748b;
}

.v-title-compact {
  font-size: 12px;
  color: #60a5fa;
  margin-top: 2px;
  display: block;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 200px;
}

/* keep legacy .v-time/.v-title for any other use */
.v-time {
  font-size: 12px;
  color: #94a3b8;
}

.v-title {
  font-size: 13px;
  color: #60a5fa;
  font-weight: 500;
}

/* card-header-row: title + action button side-by-side */
.card-header-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}
.card-header-row .card-title {
  margin-bottom: 0;
}

/* btn-xs: small ghost button */
.btn-xs {
  font-size: 11px;
  padding: 3px 10px;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.1);
  background: transparent;
  color: #94a3b8;
  cursor: pointer;
  transition: all 0.15s;
  white-space: nowrap;
}
.btn-xs:hover {
  background: rgba(255, 255, 255, 0.07);
  color: #e2e8f0;
}

/* critical-banner */
.critical-banner {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 14px 18px;
  background: rgba(239, 68, 68, 0.12);
  border: 1px solid rgba(239, 68, 68, 0.35);
  border-radius: 12px;
  color: #fca5a5;
  font-size: 14px;
}
.critical-banner i {
  font-size: 20px;
  flex-shrink: 0;
  margin-top: 2px;
}

/* pinned-note-card */
.pinned-note-card {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 16px;
  background: rgba(234, 179, 8, 0.1);
  border: 1px solid rgba(234, 179, 8, 0.25);
  border-radius: 12px;
  color: #fde68a;
  font-size: 14px;
}
.pinned-note-card i {
  font-size: 16px;
  flex-shrink: 0;
}

/* status-badge variants */
.status-badge {
  display: inline-flex;
  align-items: center;
  padding: 2px 10px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
}
.badge-green {
  background: rgba(34, 197, 94, 0.15);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.25);
}
.badge-blue {
  background: rgba(59, 130, 246, 0.15);
  color: #60a5fa;
  border: 1px solid rgba(59, 130, 246, 0.25);
}
.badge-yellow {
  background: rgba(234, 179, 8, 0.15);
  color: #fde047;
  border: 1px solid rgba(234, 179, 8, 0.25);
}
.badge-red {
  background: rgba(239, 68, 68, 0.15);
  color: #f87171;
  border: 1px solid rgba(239, 68, 68, 0.25);
}

/* treatment-meta */
.treatment-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}

/* quick-nav-row */
.quick-nav-row {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.quick-nav-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 12px 16px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 12px;
  color: #94a3b8;
  cursor: pointer;
  font-size: 12px;
  transition: all 0.15s;
  flex: 1;
  min-width: 70px;
}
.quick-nav-btn i {
  font-size: 18px;
  color: #60a5fa;
}
.quick-nav-btn:hover {
  background: rgba(59, 130, 246, 0.1);
  border-color: rgba(59, 130, 246, 0.25);
  color: #e2e8f0;
}

/* macOS-style drag animation for exam cards */
.exam-card-dragging {
  transform: scale(0.82) rotate(-2deg) !important;
  opacity: 0.55 !important;
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.6) !important;
  z-index: 50;
  transition:
    transform 0.18s cubic-bezier(0.4, 0, 0.2, 1),
    opacity 0.18s ease,
    box-shadow 0.18s ease !important;
}

/* ═══════════════════════════════════════════
   CONSENTIMENTOS — estilos exclusivos
═══════════════════════════════════════════ */

/* Cabeçalho não-interativo das seções de consentimento */
.consent-form-header {
  cursor: default;
}

/* Grid dos KPI cards */
.consent-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 14px;
}

/* KPI card base */
.consent-kpi-card {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 16px 18px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
  transition: background 0.15s;
}
.consent-kpi-card:hover {
  background: rgba(255, 255, 255, 0.05);
}

/* KPI card variants */
.consent-kpi-card--green {
  border-color: rgba(74, 222, 128, 0.15);
}
.consent-kpi-card--amber {
  border-color: rgba(251, 191, 36, 0.15);
}
.consent-kpi-card--red {
  border-color: rgba(248, 113, 113, 0.15);
}

/* KPI icon */
.consent-kpi-icon {
  width: 36px;
  height: 36px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.consent-kpi-icon--neutral {
  background: rgba(100, 116, 139, 0.12);
  color: #64748b;
}
.consent-kpi-icon--green {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
}
.consent-kpi-icon--amber {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
}
.consent-kpi-icon--red {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
}

/* KPI label & value */
.consent-kpi-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #64748b;
  margin: 0;
}
.consent-kpi-value {
  font-size: 24px;
  font-weight: 700;
  color: #e2e8f0;
  margin: 2px 0 0;
  line-height: 1;
}

/* Label/value color variants */
.consent-kpi-label--green {
  color: #4ade80;
}
.consent-kpi-label--amber {
  color: #fbbf24;
}
.consent-kpi-label--red {
  color: #f87171;
}
.consent-kpi-value--green {
  color: #4ade80;
}
.consent-kpi-value--amber {
  color: #fbbf24;
}
.consent-kpi-value--red {
  color: #f87171;
}

/* Ícone de documento na tabela */
.consent-doc-icon {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgba(168, 85, 247, 0.1);
  border: 1px solid rgba(168, 85, 247, 0.18);
  color: #c084fc;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

/* Grupo de botões de ação */
.consent-actions-group {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
}

/* Botão de ação com label — base */
.consent-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 5px 10px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: transparent;
  color: #64748b;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  transition:
    background 0.14s,
    color 0.14s,
    border-color 0.14s;
  white-space: nowrap;
}
.consent-action-btn:hover {
  background: rgba(255, 255, 255, 0.06);
  color: #94a3b8;
  border-color: rgba(255, 255, 255, 0.12);
}

/* Variantes semânticas */
.consent-action-btn--green:hover {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
  border-color: rgba(34, 197, 94, 0.2);
}
.consent-action-btn--blue:hover {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}
.consent-action-btn--purple:hover {
  background: rgba(168, 85, 247, 0.1);
  color: #c084fc;
  border-color: rgba(168, 85, 247, 0.2);
}
.consent-action-btn--danger:hover {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.2);
}

/* Ícone do modal de consentimento */
.consent-modal-icon {
  width: 36px;
  height: 36px;
  border-radius: 9px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.consent-modal-icon--green {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
}
.consent-modal-icon--purple {
  background: rgba(168, 85, 247, 0.1);
  color: #c084fc;
}

/* Modal de assinatura */
.consent-sign-modal {
  background: #111318;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 18px;
  box-shadow: 0 32px 80px rgba(0, 0, 0, 0.5);
  width: 100%;
  max-width: 540px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* Modal de visualização */
.consent-view-modal {
  background: #111318;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 18px;
  box-shadow: 0 32px 80px rgba(0, 0, 0, 0.5);
  width: 100%;
  max-width: 640px;
  max-height: 85vh;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* Área do canvas de assinatura */
.consent-canvas-wrap {
  position: relative;
  border-radius: 12px;
  border: 2px dashed rgba(255, 255, 255, 0.1);
  background: rgba(0, 0, 0, 0.2);
  aspect-ratio: 16/5;
  overflow: hidden;
}
.consent-canvas {
  width: 100%;
  height: 100%;
  display: block;
  cursor: crosshair;
  touch-action: none;
}
.consent-canvas-hint {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  color: #334155;
  font-size: 13px;
}

/* Footer do canvas */
.consent-canvas-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 10px;
}
.consent-clear-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 12px;
  color: #64748b;
  background: transparent;
  border: none;
  cursor: pointer;
  padding: 4px 6px;
  border-radius: 6px;
  transition:
    color 0.15s,
    background 0.15s;
}
.consent-clear-btn:hover {
  color: #cbd5e1;
  background: rgba(255, 255, 255, 0.05);
}
.consent-hash-hint {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  color: #475569;
  margin: 0;
}

/* Corpo do termo (visualização) */
.consent-view-body {
  background: rgba(0, 0, 0, 0.15);
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 10px;
  padding: 16px 18px;
  max-height: 340px;
  overflow-y: auto;
}
.consent-view-text {
  font-size: 13px;
  color: #94a3b8;
  line-height: 1.7;
  white-space: pre-wrap;
  font-family: 'SF Mono', 'Fira Code', monospace;
  margin: 0;
}

/* Bloco de auditoria forense */
.consent-audit-block {
  background: rgba(34, 197, 94, 0.04);
  border: 1px solid rgba(34, 197, 94, 0.12);
  border-radius: 10px;
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.consent-audit-title {
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: #475569;
  margin: 0 0 4px;
}
.consent-audit-row {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  font-size: 12px;
  color: #94a3b8;
}
.consent-audit-row--green {
  color: #4ade80;
}
.consent-audit-row--muted {
  color: #64748b;
}

/* Preview da assinatura visual */
.consent-sig-preview {
  margin-top: 12px;
}
.consent-sig-label {
  font-size: 11px;
  color: #475569;
  margin: 0 0 8px;
}
.consent-sig-frame {
  border-radius: 10px;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: rgba(0, 0, 0, 0.2);
  padding: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
}
.consent-sig-img {
  max-height: 96px;
  object-fit: contain;
}

/* ═══════════════════════════════════════════
   FINANCEIRO — estilos exclusivos
═══════════════════════════════════════════ */

/* ═══════════════════════════════════════════
   FINANCEIRO — estilos exclusivos
═══════════════════════════════════════════ */

/* KPI grid — 5 colunas iguais */
.fin-kpi-grid {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 12px;
}

/* KPI card base */
.fin-kpi-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 16px 18px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
}

/* Variantes de cor do card */
.fin-kpi-card--green {
  border-color: rgba(34, 197, 94, 0.2);
  background: rgba(34, 197, 94, 0.04);
}
.fin-kpi-card--amber {
  border-color: rgba(251, 191, 36, 0.2);
  background: rgba(251, 191, 36, 0.04);
}
.fin-kpi-card--red {
  border-color: rgba(239, 68, 68, 0.2);
  background: rgba(239, 68, 68, 0.04);
}
.fin-kpi-card--blue {
  border-color: rgba(59, 130, 246, 0.2);
  background: rgba(59, 130, 246, 0.04);
}

/* KPI ícone */
.fin-kpi-icon {
  width: 28px;
  height: 28px;
  border-radius: 7px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  background: rgba(255, 255, 255, 0.05);
  color: #475569;
  margin-bottom: 4px;
}
.fin-kpi-icon--green {
  background: rgba(34, 197, 94, 0.12);
  color: #4ade80;
}
.fin-kpi-icon--amber {
  background: rgba(251, 191, 36, 0.12);
  color: #fbbf24;
}
.fin-kpi-icon--red {
  background: rgba(239, 68, 68, 0.12);
  color: #f87171;
}
.fin-kpi-icon--blue {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}

.fin-kpi-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #475569;
  margin: 0;
}

.fin-kpi-value {
  font-size: 18px;
  font-weight: 700;
  color: #e2e8f0;
  margin: 2px 0 0;
  line-height: 1.1;
  font-variant-numeric: tabular-nums;
}

.fin-kpi-hint {
  font-size: 10px;
  color: #334155;
  margin: 0;
}

.fin-kpi-value--danger {
  color: #f87171;
}

/* ── Tabs internas ──
   O indicador ativo é uma linha reta (sem border-radius no elemento).
   O próprio <button> não tem border-radius para garantir que o underline
   apareça como linha plana de ponta a ponta. */
.fin-tabs-bar {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  margin-bottom: 16px;
}
.fin-tabs-list {
  display: flex;
  gap: 0;
}

.fin-tab {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 9px 16px;
  font-size: 13px;
  font-weight: 500;
  color: #64748b;
  background: transparent;
  border: none;
  border-radius: 0; /* sem arredondamento — underline é linha reta */
  border-bottom: 2px solid transparent;
  cursor: pointer;
  transition:
    color 0.15s,
    border-color 0.15s;
  white-space: nowrap;
  margin-bottom: -1px;
}
.fin-tab:hover {
  color: #94a3b8;
}
.fin-tab--active {
  color: #60a5fa;
  border-bottom-color: #3b82f6;
}

.fin-tab-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  border-radius: 99px;
  background: rgba(255, 255, 255, 0.07);
  color: #64748b;
  font-size: 10px;
  font-weight: 600;
}

/* ── Filtros ──
   Margem inferior para o grupo não tocar a borda divisória */
.fin-filter-group {
  display: flex;
  align-items: center;
  gap: 2px;
  background: rgba(0, 0, 0, 0.2);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 8px;
  padding: 3px;
  margin-bottom: 8px; /* afasta da linha divisória abaixo */
}
.fin-filter-btn {
  padding: 4px 10px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 500;
  color: #64748b;
  background: transparent;
  border: none;
  cursor: pointer;
  transition:
    background 0.13s,
    color 0.13s;
  white-space: nowrap;
}
.fin-filter-btn:hover {
  color: #94a3b8;
}
.fin-filter-btn--active {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}

/* Ícone-botão */
.fin-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  border: none;
  background: transparent;
  color: #475569;
  cursor: pointer;
  transition:
    background 0.14s,
    color 0.14s;
  margin-bottom: 8px; /* alinha com o filtro */
}
.fin-icon-btn:hover {
  background: rgba(255, 255, 255, 0.05);
  color: #94a3b8;
}

/* ── Tabela de transações ──
   Zebra striping: linha par (lighter), linha ímpar (base).
   Alinhamento vertical central em todas as células.
   proc-table-row já adiciona hover; aqui adicionamos nth-child striping. */
.fin-tx-table tbody tr:nth-child(odd) {
  background: rgba(255, 255, 255, 0);
}
.fin-tx-table tbody tr:nth-child(even) {
  background: rgba(255, 255, 255, 0.025);
}

/* Cells — vertical center */
.fin-tx-table td,
.fin-tx-table th {
  vertical-align: middle;
  padding: 12px 14px;
}

/* Alinhamento: colunas numéricas centradas, texto à esquerda */
.fin-tx-table th {
  text-align: left;
}
.fin-tx-table td {
  text-align: left;
}
.fin-tx-col-parcela,
.fin-tx-col-valor,
.fin-tx-col-metodo,
.fin-tx-col-status {
  text-align: center;
}
.fin-tx-col-acoes {
  text-align: right;
}

/* Data de vencimento */
.fin-tx-date {
  font-size: 12px;
  font-family: ui-monospace, monospace;
  color: #64748b;
}
.fin-tx-date--overdue {
  color: #f87171;
  font-weight: 600;
}
.fin-tx-date--paid {
  color: #334155;
  text-decoration: line-through;
}

.fin-tx-paid-at {
  font-size: 11px;
  color: #334155;
  margin-top: 2px;
}

/* Valor */
.fin-tx-amount {
  font-family: ui-monospace, monospace;
  font-weight: 600;
  font-size: 13px;
  color: #e2e8f0;
}
.fin-tx-amount--income {
  color: #e2e8f0;
}
.fin-tx-amount--expense {
  color: #f87171;
}

/* Badge método */
.fin-method-badge {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 11px;
  font-weight: 500;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  color: #64748b;
  white-space: nowrap;
}

/* Ações */
.fin-tx-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
}

/* Botão de ação */
.fin-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 5px 10px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: rgba(255, 255, 255, 0.04);
  color: #64748b;
  transition:
    background 0.13s,
    color 0.13s,
    border-color 0.13s;
  white-space: nowrap;
}
.fin-action-btn:hover {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}
.fin-action-btn--danger:hover {
  background: rgba(239, 68, 68, 0.08);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.15);
}

/* ── Cards de orçamento ── */
.fin-estimate-card {
  display: flex;
  gap: 20px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
  padding: 20px;
  transition: background 0.15s;
}
.fin-estimate-card:hover {
  background: rgba(255, 255, 255, 0.04);
}

.fin-estimate-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.fin-estimate-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.fin-estimate-id {
  font-size: 11px;
  color: #334155;
}

.fin-plan-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: #60a5fa;
  background: rgba(59, 130, 246, 0.08);
  border: 1px solid rgba(59, 130, 246, 0.15);
  border-radius: 99px;
  padding: 2px 8px;
}

.fin-estimate-values {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 14px;
}
.fin-estimate-summary {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 14px;
  padding-top: 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}
.fin-estimate-value-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.fin-estimate-value-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #334155;
  margin: 0;
}

.fin-estimate-value-amount {
  font-size: 13px;
  font-weight: 600;
  color: #94a3b8;
  margin: 0;
  font-variant-numeric: tabular-nums;
}
.fin-estimate-value-amount--highlight {
  color: #e2e8f0;
  font-size: 15px;
}
.fin-estimate-value-amount--danger {
  color: #f87171;
}

.fin-estimate-notes {
  font-size: 12px;
  color: #475569;
  background: rgba(0, 0, 0, 0.15);
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 8px;
  padding: 8px 12px;
}

.fin-estimate-actions {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  justify-content: space-between;
  gap: 12px;
  flex-shrink: 0;
  min-width: 130px;
}
.fin-estimate-dates {
  text-align: right;
  font-size: 11px;
  color: #334155;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.fin-estimate-valid {
  color: #475569;
}

/* ═══════════════════════════════════════════
   AGENDA E HISTÓRICO — estilos exclusivos
═══════════════════════════════════════════ */

/* KPI grid 4 colunas */
.sched-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
}

/* KPI card base */
.sched-kpi-card {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 16px 18px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
}
.sched-kpi-card--green {
  border-color: rgba(34, 197, 94, 0.2);
  background: rgba(34, 197, 94, 0.04);
}
.sched-kpi-card--blue {
  border-color: rgba(59, 130, 246, 0.2);
  background: rgba(59, 130, 246, 0.04);
}
.sched-kpi-card--red {
  border-color: rgba(239, 68, 68, 0.2);
  background: rgba(239, 68, 68, 0.04);
}

/* KPI ícone */
.sched-kpi-icon {
  width: 28px;
  height: 28px;
  border-radius: 7px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(255, 255, 255, 0.05);
  color: #475569;
  margin-bottom: 4px;
}
.sched-kpi-icon--green {
  background: rgba(34, 197, 94, 0.12);
  color: #4ade80;
}
.sched-kpi-icon--blue {
  background: rgba(59, 130, 246, 0.12);
  color: #60a5fa;
}
.sched-kpi-icon--red {
  background: rgba(239, 68, 68, 0.12);
  color: #f87171;
}

.sched-kpi-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #475569;
  margin: 0;
}
.sched-kpi-value {
  font-size: 28px;
  font-weight: 700;
  color: #e2e8f0;
  margin: 0;
  line-height: 1;
  font-variant-numeric: tabular-nums;
}

/* Filtros pill */
.sched-filter-row {
  display: flex;
  align-items: center;
  gap: 6px;
}
.sched-filter-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 6px 14px;
  border-radius: 99px;
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  cursor: pointer;
  transition:
    background 0.13s,
    color 0.13s,
    border-color 0.13s;
  white-space: nowrap;
}
.sched-filter-btn:hover {
  color: #94a3b8;
  background: rgba(255, 255, 255, 0.06);
}
.sched-filter-btn--active {
  background: rgba(59, 130, 246, 0.12);
  border-color: rgba(59, 130, 246, 0.25);
  color: #60a5fa;
}
.sched-filter-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 18px;
  height: 18px;
  padding: 0 4px;
  border-radius: 99px;
  background: rgba(255, 255, 255, 0.08);
  color: #64748b;
  font-size: 10px;
  font-weight: 700;
}

/* Alerta de retorno */
.sched-recall-alert {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 18px;
  background: rgba(251, 191, 36, 0.06);
  border: 1px solid rgba(251, 191, 36, 0.2);
  border-radius: 12px;
}
.sched-recall-icon {
  width: 36px;
  height: 36px;
  border-radius: 99px;
  background: rgba(251, 191, 36, 0.15);
  color: #fbbf24;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.sched-recall-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.sched-recall-title {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 13px;
  font-weight: 600;
  color: #fbbf24;
  margin: 0;
}
.sched-recall-desc {
  font-size: 12px;
  color: rgba(251, 191, 36, 0.7);
  margin: 0;
  line-height: 1.5;
}
.sched-recall-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 600;
  background: #fbbf24;
  color: #1e1b0e;
  border: none;
  cursor: pointer;
  transition: background 0.13s;
}
.sched-recall-btn:hover {
  background: #f59e0b;
}
.sched-recall-btn:disabled {
  opacity: 0.5;
  cursor: default;
}
.sched-recall-btn-ghost {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 12px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 500;
  background: transparent;
  border: 1px solid rgba(251, 191, 36, 0.25);
  color: #fbbf24;
  cursor: pointer;
  transition: background 0.13s;
}
.sched-recall-btn-ghost:hover {
  background: rgba(251, 191, 36, 0.08);
}
.sched-recall-dismiss {
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}
.sched-dismiss-text {
  font-size: 10px;
  color: rgba(251, 191, 36, 0.4);
  background: none;
  border: none;
  cursor: pointer;
  text-decoration: underline;
  text-underline-offset: 2px;
  white-space: nowrap;
  transition: color 0.13s;
  padding: 0;
  line-height: 1.4;
}
.sched-dismiss-text:hover {
  color: rgba(251, 191, 36, 0.7);
}
.sched-dismiss-x {
  width: auto;
  height: auto;
  padding: 2px;
  border-radius: 4px;
  background: none;
  border: none;
  color: rgba(251, 191, 36, 0.45);
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 16px;
  transition: color 0.13s;
}
.sched-dismiss-x:hover {
  color: #fbbf24;
}

/* Empty state */
.sched-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 56px 24px;
  background: rgba(255, 255, 255, 0.02);
  border: 1px dashed rgba(255, 255, 255, 0.07);
  border-radius: 16px;
  text-align: center;
}
.sched-empty-icon {
  width: 52px;
  height: 52px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  color: #334155;
  display: flex;
  align-items: center;
  justify-content: center;
}
.sched-empty-title {
  font-size: 14px;
  font-weight: 500;
  color: #94a3b8;
  margin: 0;
}
.sched-empty-hint {
  font-size: 12px;
  color: #334155;
  margin: 0;
}

/* Linha do tempo */
.sched-timeline {
  position: relative;
  padding-left: 48px;
  display: flex;
  flex-direction: column;
  gap: 0;
}
/* A linha é centralizada exatamente no eixo dos dots (dot left=-28, metade=7px → 48-28+7=27px) */
.sched-timeline-line {
  position: absolute;
  left: 27px;
  top: 12px;
  bottom: 12px;
  width: 1px;
  background: linear-gradient(
    to bottom,
    rgba(255, 255, 255, 0.07) 80%,
    transparent
  );
}

/* Item da linha do tempo */
.sched-apt-item {
  position: relative;
  margin-bottom: 16px;
}

/* Dot — sólido, sem borda */
.sched-apt-dot {
  position: absolute;
  left: -28px; /* 48px padding - 28px = dot começa no eixo certo */
  top: 20px;
  width: 14px;
  height: 14px;
  border-radius: 99px;
  background: #334155; /* neutro para status desconhecido */
  border: none;
  z-index: 2;
}
/* Falta / Cancelado → amarelo */
.sched-apt-dot--noshow {
  background: #eab308;
}
/* Agendado / Confirmado  → verde */
.sched-apt-dot--scheduled {
  background: #22c55e;
}
/* Realizado              → cinza claro */
.sched-apt-dot--done {
  background: #475569;
}

/* Card de agendamento */
.sched-apt-card {
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 12px;
  padding: 18px 20px;
  display: flex;
  flex-direction: column;
  gap: 14px;
  transition:
    background 0.14s,
    border-color 0.14s;
}
.sched-apt-card:hover {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.1);
}

/* Header do card */
.sched-apt-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}
.sched-apt-badges {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px;
}

/* Badge de status — herda cores do aptStatusCfg */
.sched-status-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 10px;
  border-radius: 99px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

/* Tipo de evento */
.sched-type-badge {
  background: rgba(255, 255, 255, 0.05);
  color: #94a3b8;
  border: 1px solid rgba(255, 255, 255, 0.07);
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 500;
}

/* Prioridade */
.sched-priority-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 600;
}

/* PRÓXIMA */
.sched-next-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 700;
  background: rgba(59, 130, 246, 0.1);
  border: 1px solid rgba(59, 130, 246, 0.2);
  color: #60a5fa;
  animation: pulse 2s ease-in-out infinite;
}

/* Data/Hora */
.sched-apt-datetime {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
  flex-shrink: 0;
}
.sched-apt-date {
  font-size: 13px;
  font-weight: 600;
  color: #e2e8f0;
  margin: 0;
  font-variant-numeric: tabular-nums;
}
.sched-apt-time {
  font-size: 11px;
  color: #475569;
  margin: 0;
  font-variant-numeric: tabular-nums;
}

/* Info grid (profissional / tratamento) */
.sched-apt-info {
  display: grid;
  grid-template-columns: repeat(2, auto);
  gap: 16px 40px;
  align-items: start;
}
.sched-info-col {
  display: flex;
  flex-direction: column;
  gap: 5px;
}
.sched-info-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #334155;
  margin: 0;
}
.sched-info-value {
  font-size: 13px;
  font-weight: 500;
  color: #cbd5e1;
}
.sched-info-empty {
  font-size: 13px;
  color: #334155;
  font-style: italic;
}

/* Motivo (reagendamento / cancelamento) */
.sched-reason {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 10px 12px;
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.4;
}
.sched-reason--amber {
  background: rgba(251, 191, 36, 0.05);
  border: 1px solid rgba(251, 191, 36, 0.12);
  color: rgba(251, 191, 36, 0.7);
}
.sched-reason--red {
  background: rgba(239, 68, 68, 0.05);
  border: 1px solid rgba(239, 68, 68, 0.12);
  color: rgba(248, 113, 113, 0.7);
}

/* Observações */
.sched-notes {
  font-size: 12px;
  color: #475569;
  font-style: italic;
  background: rgba(0, 0, 0, 0.12);
  border: 1px solid rgba(255, 255, 255, 0.04);
  border-radius: 8px;
  padding: 8px 12px;
  line-height: 1.5;
}

/* Ações do card (footer) */
.sched-apt-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 6px;
  padding-top: 12px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}
.sched-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 11px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid rgba(255, 255, 255, 0.07);
  background: rgba(255, 255, 255, 0.04);
  color: #64748b;
  transition:
    background 0.13s,
    color 0.13s,
    border-color 0.13s;
  white-space: nowrap;
}
.sched-action-btn:disabled {
  opacity: 0.5;
  cursor: default;
}
.sched-action-btn:not(:disabled):hover {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}
.sched-action-btn--amber:not(:disabled):hover {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
  border-color: rgba(251, 191, 36, 0.2);
}
.sched-action-btn--danger:not(:disabled):hover {
  background: rgba(239, 68, 68, 0.08);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.15);
}

/* Fim da linha do tempo */
.sched-timeline-end {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 0;
  opacity: 0.35;
}
.sched-timeline-end-line {
  flex: 1;
  height: 1px;
  background: linear-gradient(to right, rgba(255, 255, 255, 0.06), transparent);
}
.sched-timeline-end-label {
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.18em;
  color: #334155;
  white-space: nowrap;
}

/* ============================================================
   TIMELINE TAB — tl-* design system
   ============================================================ */

/* Filtros de categoria */
.tl-filter-row {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}
.tl-filter-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 5px 14px;
  border-radius: 99px;
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  background: none;
  border: 1px solid rgba(255, 255, 255, 0.07);
  cursor: pointer;
  transition:
    background 0.15s,
    color 0.15s,
    border-color 0.15s;
}
.tl-filter-btn:hover {
  color: #94a3b8;
  background: rgba(255, 255, 255, 0.04);
}
.tl-filter-btn--active {
  background: rgba(59, 130, 246, 0.12);
  border-color: rgba(59, 130, 246, 0.25);
  color: #60a5fa;
}

/* Dropdown de ordenação */
.tl-sort-dropdown {
  position: absolute;
  right: 0;
  top: calc(100% + 6px);
  z-index: 50;
  background: #0f1118;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 10px;
  padding: 6px;
  min-width: 200px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
}
.tl-sort-option {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-radius: 7px;
  font-size: 13px;
  color: #94a3b8;
  background: none;
  border: none;
  cursor: pointer;
  width: 100%;
  text-align: left;
  transition:
    background 0.12s,
    color 0.12s;
}
.tl-sort-option:hover {
  background: rgba(255, 255, 255, 0.05);
  color: #e2e8f0;
}
.tl-sort-option--active {
  color: #60a5fa;
  background: rgba(59, 130, 246, 0.1);
}

/* Empty state */
.tl-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 80px 0;
  gap: 12px;
}
.tl-empty-icon {
  width: 56px;
  height: 56px;
  border-radius: 99px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  display: flex;
  align-items: center;
  justify-content: center;
  color: #475569;
}
.tl-empty-title {
  font-size: 15px;
  font-weight: 500;
  color: #94a3b8;
  margin: 0;
}
.tl-empty-hint {
  font-size: 13px;
  color: #475569;
  margin: 0;
  text-align: center;
}

/* Container principal */
.tl-timeline {
  display: flex;
  flex-direction: column;
  gap: 32px;
}
.tl-group {
  display: flex;
  flex-direction: column;
  gap: 0;
}

/* Separador de data */
.tl-date-divider {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 16px;
}
.tl-date-line {
  flex: 1;
  height: 1px;
  background: rgba(255, 255, 255, 0.05);
}
.tl-date-label {
  font-size: 11px;
  font-weight: 600;
  color: #475569;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  white-space: nowrap;
  padding: 3px 12px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 99px;
}

/* Container de eventos do grupo */
.tl-events {
  position: relative;
  padding-left: 44px;
  display: flex;
  flex-direction: column;
  gap: 0;
}
/* Linha vertical */
.tl-vline {
  position: absolute;
  left: 19px;
  top: 0;
  bottom: 0;
  width: 1px;
  background: rgba(255, 255, 255, 0.06);
}

/* Linha de evento */
.tl-event-row {
  position: relative;
  display: flex;
  align-items: flex-start;
  gap: 14px;
  padding: 8px 0;
}

/* Ícone circular — base */
.tl-event-icon {
  position: absolute;
  left: -44px;
  top: 12px;
  width: 36px;
  height: 36px;
  border-radius: 99px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  z-index: 2;
}

/* Variantes de ícone semântico (geradas de TIMELINE_COLOR_CLASSES) */
.tl-icon--indigo {
  background: #16183a;
  box-shadow: 0 0 0 1px #4f52a0;
  color: #a5b4fc;
}
.tl-icon--blue {
  background: #0f1f35;
  box-shadow: 0 0 0 1px #3b6ea8;
  color: #93c5fd;
}
.tl-icon--orange {
  background: #1e120a;
  box-shadow: 0 0 0 1px #8b5a2b;
  color: #fdba74;
}
.tl-icon--yellow {
  background: #1b1506;
  box-shadow: 0 0 0 1px #7c6516;
  color: #fde68a;
}
.tl-icon--emerald {
  background: #0a1f18;
  box-shadow: 0 0 0 1px #276c52;
  color: #6ee7b7;
}
.tl-icon--red {
  background: #1e0d0d;
  box-shadow: 0 0 0 1px #7f2020;
  color: #fca5a5;
}
.tl-icon--rose {
  background: #1e0d13;
  box-shadow: 0 0 0 1px #7f2040;
  color: #fda4af;
}
.tl-icon--cyan {
  background: #0a1e25;
  box-shadow: 0 0 0 1px #1e6e7e;
  color: #67e8f9;
}
.tl-icon--teal {
  background: #0a1e1d;
  box-shadow: 0 0 0 1px #1e6e68;
  color: #5eead4;
}
.tl-icon--violet {
  background: #140e25;
  box-shadow: 0 0 0 1px #5837a0;
  color: #c4b5fd;
}
.tl-icon--sky {
  background: #0b1c2c;
  box-shadow: 0 0 0 1px #1e5f8c;
  color: #7dd3fc;
}
.tl-icon--purple {
  background: #180d2a;
  box-shadow: 0 0 0 1px #6a2e9e;
  color: #d8b4fe;
}
.tl-icon--green {
  background: #0c1e12;
  box-shadow: 0 0 0 1px #235c34;
  color: #86efac;
}
.tl-icon--amber {
  background: #1c1106;
  box-shadow: 0 0 0 1px #7c4e12;
  color: #fcd34d;
}
.tl-icon--slate {
  background: #141820;
  box-shadow: 0 0 0 1px #3a4455;
  color: #94a3b8;
}
.tl-icon--lime {
  background: #111a06;
  box-shadow: 0 0 0 1px #4a6a14;
  color: #bef264;
}

/* Card do evento */
.tl-event-card {
  flex: 1;
  background: rgba(255, 255, 255, 0.025);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 12px;
  padding: 14px 16px;
  transition:
    background 0.15s,
    border-color 0.15s;
  min-width: 0;
}
.tl-event-card:hover {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.1);
}

/* Cabeçalho do card: badge + hora */
.tl-event-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 6px;
}

/* Badge de tipo de evento */
.tl-event-badge {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.07em;
  text-transform: uppercase;
  padding: 2px 8px;
  border-radius: 5px;
}

/* Variantes de badge (mesmas cores dos ícones, fundo mais escuro) */
.tl-badge--indigo {
  background: #1e2047;
  color: #a5b4fc;
}
.tl-badge--blue {
  background: #132440;
  color: #93c5fd;
}
.tl-badge--orange {
  background: #241508;
  color: #fdba74;
}
.tl-badge--yellow {
  background: #201a08;
  color: #fde68a;
}
.tl-badge--emerald {
  background: #0c2219;
  color: #6ee7b7;
}
.tl-badge--red {
  background: #220f0f;
  color: #fca5a5;
}
.tl-badge--rose {
  background: #220f16;
  color: #fda4af;
}
.tl-badge--cyan {
  background: #0c2229;
  color: #67e8f9;
}
.tl-badge--teal {
  background: #0c2221;
  color: #5eead4;
}
.tl-badge--violet {
  background: #170f2a;
  color: #c4b5fd;
}
.tl-badge--sky {
  background: #0d2033;
  color: #7dd3fc;
}
.tl-badge--purple {
  background: #1b0e2f;
  color: #d8b4fe;
}
.tl-badge--green {
  background: #0e2215;
  color: #86efac;
}
.tl-badge--amber {
  background: #211308;
  color: #fcd34d;
}
.tl-badge--slate {
  background: #171c25;
  color: #94a3b8;
}
.tl-badge--lime {
  background: #131e07;
  color: #bef264;
}

/* Hora */
.tl-event-time {
  font-size: 11px;
  color: #475569;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
  flex-shrink: 0;
}

/* Título do evento */
.tl-event-title {
  font-size: 13px;
  font-weight: 500;
  color: #cbd5e1;
  line-height: 1.45;
  margin: 0 0 0 0;
}

/* Metadados */
.tl-event-meta {
  margin-top: 10px;
  padding-top: 10px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px 24px;
}
.tl-meta-item {
  display: flex;
  align-items: baseline;
  gap: 4px;
  font-size: 12px;
}
.tl-meta-key {
  color: #475569;
  text-transform: capitalize;
  white-space: nowrap;
  flex-shrink: 0;
}
.tl-meta-key::after {
  content: ':';
}
.tl-meta-val {
  color: #94a3b8;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* Actor */
.tl-event-actor {
  display: flex;
  align-items: center;
  gap: 5px;
  margin-top: 8px;
  font-size: 11px;
  color: #334155;
}

/* Marcador de início do histórico */
.tl-history-end {
  display: flex;
  align-items: center;
  gap: 10px;
  padding-top: 8px;
}
.tl-history-line {
  flex: 1;
  height: 1px;
  background: rgba(255, 255, 255, 0.04);
}
.tl-history-dot {
  width: 6px;
  height: 6px;
  border-radius: 99px;
  background: #1e293b;
  border: 1px solid rgba(255, 255, 255, 0.1);
  flex-shrink: 0;
}
.tl-history-label {
  font-size: 11px;
  color: #334155;
  white-space: nowrap;
}

/* ============================================================
   AUDITORIA TAB — aud-* design system
   ============================================================ */

/* Barra de filtros */
.aud-filter-bar {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr auto;
  align-items: flex-end;
  gap: 12px;
  background: rgba(255, 255, 255, 0.02);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 12px;
  padding: 16px;
}
.aud-filter-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.aud-filter-label {
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  line-height: 1;
}
.aud-filter-actions {
  display: flex;
  align-items: flex-end;
  gap: 8px;
}
.aud-clear-btn {
  width: 38px;
  height: 38px;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

/* Tabela wrapper */
.aud-table-wrap {
  background: rgba(255, 255, 255, 0.02);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 12px;
  overflow: hidden;
}
.aud-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 48px;
  color: #475569;
  font-size: 14px;
}
.aud-table {
  width: 100%;
  text-align: left;
  font-size: 13px;
  border-collapse: collapse;
}

/* Thead */
.aud-thead-row {
  background: rgba(255, 255, 255, 0.025);
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}
.aud-th {
  padding: 11px 16px;
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: #475569;
  white-space: nowrap;
}
.aud-th--center {
  text-align: center;
}

/* Tbody rows */
.aud-row {
  border-bottom: 1px solid rgba(255, 255, 255, 0.04);
  transition: background 0.12s;
}
.aud-row:last-child {
  border-bottom: none;
}
.aud-row:hover {
  background: rgba(255, 255, 255, 0.025);
}

.aud-td {
  padding: 13px 16px;
  vertical-align: middle;
}
.aud-td--mono {
  font-family: ui-monospace, monospace;
  font-size: 11px;
}
.aud-td--dim {
  color: #475569;
}
.aud-td--center {
  text-align: center;
}
.aud-td--details {
  max-width: 280px;
}

/* Action badges */
.aud-action-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 2px 8px;
  border-radius: 5px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  border-width: 1px;
  border-style: solid;
  white-space: nowrap;
}

/* Avatar de usuário */
.aud-user-cell {
  display: flex;
  align-items: center;
  gap: 9px;
}
.aud-avatar {
  width: 28px;
  height: 28px;
  border-radius: 99px;
  background: rgba(59, 130, 246, 0.12);
  border: 1px solid rgba(59, 130, 246, 0.2);
  color: #60a5fa;
  font-size: 10px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.aud-user-name {
  font-size: 12px;
  font-weight: 500;
  color: #cbd5e1;
  line-height: 1.3;
}
.aud-user-role {
  font-size: 10px;
  color: #475569;
  text-transform: capitalize;
  line-height: 1.3;
}

/* Módulo & diff */
.aud-module-name {
  font-size: 12px;
  font-weight: 500;
  color: #e2e8f0;
}
.aud-module-id {
  font-size: 11px;
  color: #475569;
  margin-left: 3px;
}
.aud-diff {
  margin-top: 6px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.aud-diff-row {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
}
.aud-diff-field {
  color: #64748b;
  font-weight: 500;
}
.aud-diff-old {
  color: #475569;
  text-decoration: line-through;
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.aud-diff-new {
  color: #4ade80;
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.aud-snapshot {
  margin-top: 4px;
  font-size: 10px;
  color: #475569;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* Botão de detalhe */
.aud-detail-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 7px;
  background: none;
  border: none;
  color: #475569;
  cursor: pointer;
  transition:
    background 0.12s,
    color 0.12s;
}
.aud-detail-btn:hover {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
}

/* Linha expandida */
.aud-expanded-row {
  background: rgba(59, 130, 246, 0.04);
}
.aud-expanded-cell {
  padding: 14px 16px;
  border-left: 2px solid rgba(59, 130, 246, 0.3);
}
.aud-expanded-body {
  display: flex;
  align-items: flex-start;
  gap: 10px;
}
.aud-expanded-icon {
  color: #60a5fa;
  margin-top: 1px;
  flex-shrink: 0;
}
.aud-expanded-title {
  font-size: 13px;
  font-weight: 500;
  color: #e2e8f0;
  margin-bottom: 4px;
}
.aud-expanded-text {
  font-size: 12px;
  color: #94a3b8;
  line-height: 1.5;
}
.aud-expanded-diff {
  margin-top: 12px;
  background: rgba(0, 0, 0, 0.2);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 8px;
  padding: 12px 14px;
}
.aud-expanded-diff-title {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #475569;
  margin-bottom: 8px;
}
.aud-expanded-diff-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.aud-expanded-diff-item {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
}
.aud-diff-f {
  color: #64748b;
  font-family: ui-monospace, monospace;
  width: 96px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex-shrink: 0;
}
.aud-diff-o {
  color: #475569;
  text-decoration: line-through;
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.aud-diff-n {
  color: #4ade80;
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* Empty state */
.aud-empty-cell {
  padding: 48px 24px;
}
.aud-empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  color: #475569;
  text-align: center;
  font-size: 13px;
}
.aud-empty-hint {
  font-size: 11px;
  color: #334155;
}

/* Rodapé */
.aud-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}
.aud-footer-note {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  color: #334155;
}
.aud-footer-total {
  margin-left: 8px;
  color: #1e293b;
}
.aud-pagination {
  display: flex;
  align-items: center;
  gap: 12px;
}
.aud-page-info {
  font-size: 11px;
  color: #475569;
  white-space: nowrap;
}

/* ── Archived Patient Banner ────────────────────── */
.archived-banner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  background: rgba(245, 158, 11, 0.08);
  border: 1px solid rgba(245, 158, 11, 0.28);
  border-radius: 12px;
  padding: 14px 20px;
  margin-bottom: 16px;
}

.archived-banner-left {
  display: flex;
  align-items: center;
  gap: 12px;
  color: #fbbf24;
}

.archived-banner-title {
  font-size: 13px;
  font-weight: 600;
  color: #fbbf24;
  margin: 0;
  line-height: 1.3;
}

.archived-banner-sub {
  font-size: 12px;
  color: #d97706;
  margin: 2px 0 0;
  line-height: 1.3;
}

.archived-banner-btn {
  display: flex;
  align-items: center;
  gap: 7px;
  background: rgba(245, 158, 11, 0.12);
  border: 1px solid rgba(245, 158, 11, 0.3);
  border-radius: 7px;
  color: #fbbf24;
  font-size: 13px;
  font-weight: 500;
  padding: 7px 14px;
  cursor: pointer;
  transition: all 0.15s;
  white-space: nowrap;
  flex-shrink: 0;
}

.archived-banner-btn:hover {
  background: rgba(245, 158, 11, 0.2);
  border-color: rgba(245, 158, 11, 0.45);
}

/* ── Archived Read-Only Mode ─────────────────────── */
.is-archived .record-layout,
.is-archived .profile-banner {
  opacity: 0.75;
}

.is-archived .record-layout input,
.is-archived .record-layout textarea,
.is-archived .record-layout select,
.is-archived .record-layout .reg-toggle,
.is-archived .record-layout .reg-avatar-wrapper,
.is-archived .record-layout .tab-content-area button:not(.archived-banner-btn),
.is-archived .record-layout button:not(.vertical-tab-btn):not(.btn-back) {
  pointer-events: none;
  opacity: 0.5;
  cursor: not-allowed;
  filter: grayscale(0.4);
}

.is-archived .record-layout input,
.is-archived .record-layout textarea,
.is-archived .record-layout select {
  background: rgba(30, 30, 35, 0.6) !important;
  border-color: rgba(100, 116, 139, 0.2) !important;
  color: #64748b !important;
}

.is-archived .record-layout label,
.is-archived .record-layout .form-label {
  color: #475569;
}

.is-archived .archived-banner-btn {
  pointer-events: all;
  opacity: 1;
  cursor: pointer;
  filter: none;
}
</style>
