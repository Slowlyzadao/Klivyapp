/**
 * useExamMedias — fetch + mutations das mídias de exame.
 *
 * Extraído de ExamsTab.vue (Roadmap #11/#12).
 *
 *   fetch()              → carrega array
 *   upload(file)         → valida tipo/tamanho → POST com progress
 *   move(mediaId, fid)   → drag → atualiza folder com rollback otimista
 *   rename(mediaId, n)   → in-place rename otimista
 *   toggleLock(mediaId)  → lock/unlock otimista
 *   remove(mediaId)      → delete + refetch (gate por lock no caller)
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import ExamMediasAPI from '@plugins/patients/frontend/api/patients/examMedias';
import {
  classifyUpload,
  detectMediaCategory,
  formatMb,
} from '@plugins/patients/frontend/features/patient-record/utils/examClassifiers';
import { UPLOAD_LIMITS } from '@plugins/patients/frontend/constants/exams';

export function useExamMedias(patientIdRef) {
  const { t } = useI18n();

  const examMedias = ref([]);
  const isUploading = ref(false);
  const uploadProgress = ref(0);
  const isDeleting = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const fetch = async () => {
    try {
      const res = await ExamMediasAPI.get(resolveId());
      examMedias.value = res.data?.data || res.data || [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Exams] Falha ao carregar mídias', error);
      useNotification.error(t('PATIENT_EXAMS.MESSAGES.LOAD_MEDIA_ERROR'));
    }
  };

  const upload = async file => {
    if (!file) return { ok: false };

    const kind = classifyUpload(file);
    if (!kind) {
      useNotification.warning(t('PATIENT_EXAMS.MESSAGES.UPLOAD_INVALID_FORMAT'));
      return { ok: false };
    }
    const limit = UPLOAD_LIMITS[kind];
    if (file.size > limit) {
      const kindKey = `PATIENT_EXAMS.MESSAGES.UPLOAD_KIND_${kind.toUpperCase()}`;
      useNotification.warning(
        t('PATIENT_EXAMS.MESSAGES.UPLOAD_TOO_LARGE', {
          limit: formatMb(limit),
          kind: t(kindKey),
        })
      );
      return { ok: false };
    }

    try {
      isUploading.value = true;
      uploadProgress.value = 0;
      await ExamMediasAPI.create(resolveId(), {
        file,
        category: detectMediaCategory(file),
        onUploadProgress: e => {
          if (!e.total) return;
          uploadProgress.value = Math.round((e.loaded * 100) / e.total);
        },
      });
      useNotification.success(t('PATIENT_EXAMS.MESSAGES.UPLOAD_SUCCESS'));
      await fetch();
      return { ok: true };
    } catch (error) {
      const errs = error?.response?.data?.errors;
      const msg = Array.isArray(errs)
        ? errs.join('. ')
        : errs || t('PATIENT_EXAMS.MESSAGES.UPLOAD_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      isUploading.value = false;
      uploadProgress.value = 0;
    }
  };

  const move = async (mediaId, targetFolderId) => {
    const media = examMedias.value.find(m => m.id === mediaId);
    if (!media) return { ok: false };
    if ((media.folder_id || null) === targetFolderId) return { ok: true };

    const previous = media.folder_id;
    media.folder_id = targetFolderId;
    media.exam_folder_id = targetFolderId;
    try {
      await ExamMediasAPI.update(resolveId(), mediaId, {
        exam_folder_id: targetFolderId,
      });
      useNotification.success(t('PATIENT_EXAMS.MESSAGES.MOVE_SUCCESS'));
      return { ok: true };
    } catch (error) {
      media.folder_id = previous;
      media.exam_folder_id = previous;
      useNotification.error(t('PATIENT_EXAMS.MESSAGES.MOVE_ERROR'));
      return { ok: false };
    }
  };

  const rename = async (mediaId, newName) => {
    const name = String(newName || '').trim();
    if (!name) return { ok: false };
    const media = examMedias.value.find(m => m.id === mediaId);
    if (!media) return { ok: false };
    const previous = media.file_name;
    media.file_name = name;
    try {
      await ExamMediasAPI.update(resolveId(), mediaId, { file_name: name });
      return { ok: true };
    } catch (error) {
      media.file_name = previous;
      useNotification.error(t('PATIENT_EXAMS.MESSAGES.RENAME_MEDIA_ERROR'));
      return { ok: false };
    }
  };

  const toggleLock = async (mediaId, desiredLocked) => {
    const media = examMedias.value.find(m => m.id === mediaId);
    if (!media) return { ok: false };
    const previous = media.locked;
    media.locked = desiredLocked;
    try {
      await ExamMediasAPI.update(resolveId(), mediaId, {
        locked: desiredLocked,
      });
      useNotification.success(
        t(
          desiredLocked
            ? 'PATIENT_EXAMS.MESSAGES.LOCK_SUCCESS'
            : 'PATIENT_EXAMS.MESSAGES.UNLOCK_SUCCESS'
        )
      );
      return { ok: true };
    } catch (error) {
      media.locked = previous;
      useNotification.error(t('PATIENT_EXAMS.MESSAGES.LOCK_ERROR'));
      return { ok: false };
    }
  };

  const remove = async mediaId => {
    isDeleting.value = true;
    try {
      await ExamMediasAPI.delete(resolveId(), mediaId);
      useNotification.success(t('PATIENT_EXAMS.MESSAGES.DELETE_MEDIA_SUCCESS'));
      await fetch();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Exams] Falha ao excluir mídia', error);
      const errs = error?.response?.data?.errors;
      useNotification.error(
        Array.isArray(errs)
          ? errs.join('. ')
          : t('PATIENT_EXAMS.MESSAGES.DELETE_MEDIA_ERROR')
      );
      return { ok: false };
    } finally {
      isDeleting.value = false;
    }
  };

  return {
    examMedias,
    isUploading,
    uploadProgress,
    isDeleting,
    fetch,
    upload,
    move,
    rename,
    toggleLock,
    remove,
  };
}
