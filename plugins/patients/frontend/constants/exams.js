/**
 * Constants do módulo Exames e Imagens.
 *
 * Extraído de ExamsTab.vue (Roadmap #11). Mantido em sync com:
 *   plugins/patients/app/models/exam_media.rb (SIZE_LIMITS, ACCEPTED_*).
 */

export const FOLDER_COLORS = [
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

export const DEFAULT_FOLDER_COLOR = '#60a5fa';

// Mantenha em sync com ExamMedia::SIZE_LIMITS no backend.
export const UPLOAD_LIMITS = {
  image: 5 * 1024 * 1024, // 5MB
  pdf: 10 * 1024 * 1024, // 10MB
  video: 20 * 1024 * 1024, // 20MB
};

export const ACCEPTED_MIME = {
  image: /^image\/(jpeg|png|gif|webp|heic|heif)$/i,
  pdf: /^application\/pdf$/i,
  video: /^video\/(mp4|quicktime|webm)$/i,
};

export const ACCEPTED_EXT = {
  image: /\.(jpe?g|png|gif|webp|heic|heif)$/i,
  pdf: /\.pdf$/i,
  video: /\.(mp4|mov|webm)$/i,
};

// Lista plana de mime types aceitos para o `accept` do <input type="file">.
export const FILE_INPUT_ACCEPT = [
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/heic',
  'image/heif',
  'application/pdf',
  'video/mp4',
  'video/webm',
  'video/quicktime',
].join(',');

// Filtros de tipo na barra superior do conteúdo.
export const MEDIA_TYPE_FILTERS = [
  { value: 'all', icon: null, labelKey: 'PATIENT_EXAMS.FILTERS.ALL' },
  { value: 'image', icon: 'i-lucide-image', labelKey: 'PATIENT_EXAMS.FILTERS.IMAGES' },
  { value: 'video', icon: 'i-lucide-video', labelKey: 'PATIENT_EXAMS.FILTERS.VIDEOS' },
  { value: 'pdf', icon: 'i-lucide-file-text', labelKey: 'PATIENT_EXAMS.FILTERS.PDFS' },
  {
    value: 'document',
    icon: 'i-lucide-file-code-2',
    labelKey: 'PATIENT_EXAMS.FILTERS.DOCUMENTS',
  },
];

export const ROOT_FOLDER_ID = 'root';
