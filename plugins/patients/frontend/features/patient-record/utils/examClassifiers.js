/**
 * Helpers de classificação de mídia por mime/extensão.
 *
 * Extraído de ExamsTab.vue (Roadmap #11). Funções puras — recebem o objeto
 * media (com mime_type + file_name) ou um File, retornam booleano/categoria.
 */

import {
  ACCEPTED_MIME,
  ACCEPTED_EXT,
} from '@plugins/patients/frontend/constants/exams';

const lowerExt = name =>
  String(name || '').toLowerCase().split('.').pop() || '';

export const isVideo = m =>
  (m?.mime_type || '').startsWith('video/') ||
  /\.(mp4|mov|webm|avi|mkv|m4v)$/i.test(m?.file_name || '');

export const isPdf = m =>
  (m?.mime_type || '').includes('pdf') ||
  /\.pdf$/i.test(m?.file_name || '');

export const isImage = m =>
  (m?.mime_type || '').startsWith('image/') ||
  /\.(jpe?g|png|gif|webp|heic|heif)$/i.test(m?.file_name || '');

export const isDocumentLike = m => {
  const mime = (m?.mime_type || '').toLowerCase();
  const ext = lowerExt(m?.file_name);
  return (
    mime.includes('document') ||
    mime.includes('msword') ||
    mime.includes('excel') ||
    mime.includes('csv') ||
    mime.includes('presentation') ||
    ['doc', 'docx', 'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'rtf', 'txt'].includes(ext)
  );
};

// Classifica um File para upload (image/pdf/video) ou null se não suportado.
export const classifyUpload = file => {
  const name = file?.name || '';
  const type = file?.type || '';
  for (const kind of ['image', 'pdf', 'video']) {
    if (ACCEPTED_MIME[kind].test(type) || ACCEPTED_EXT[kind].test(name)) {
      return kind;
    }
  }
  return null;
};

// Categoria semântica enviada ao backend ao subir um File.
export const detectMediaCategory = file => {
  const kind = classifyUpload(file);
  if (kind === 'image') return 'foto_clinica';
  if (kind === 'video') return 'video';
  if (kind === 'pdf') return 'laudo';
  return 'outro';
};

export const formatMb = bytes => `${Math.round(bytes / 1024 / 1024)}MB`;

// Aplica filtro de tipo num array de medias.
export const matchesTypeFilter = (media, filter) => {
  if (filter === 'all') return true;
  if (filter === 'image') return isImage(media);
  if (filter === 'video') return isVideo(media);
  if (filter === 'pdf') return isPdf(media);
  if (filter === 'document') return isDocumentLike(media);
  return true;
};
