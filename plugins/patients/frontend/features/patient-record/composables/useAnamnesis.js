/**
 * useAnamnesis — fetch + mutations + dirty tracking da aba Anamnese.
 *
 *   fetch()                        → carrega lista + aplica primeira ao state
 *   saveAnamnesis(finalize=false)  → cria/atualiza; com finalize=true grava
 *                                    e finaliza (registro fica imutável + PDF)
 *   startNew()                     → reseta state pra EMPTY_ANAMNESIS
 *   flushAllergyInput()            → push da string solta no input para o array
 *   flushMedicationInput()         → idem para medicamentos
 *   removeAllergy(idx)             → remove por índice (gated por status)
 *   removeMedication(idx)          → idem
 *
 * Dirty tracking: anamnese é registro clínico — qualquer edição não salva
 * gera prompt nativo no fechar de aba e route guard SPA. Ver setup do guard
 * no caller (precisa de onBeforeRouteLeave).
 */

import { ref, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useClinicProfile } from '@plugins/beclinic_core/frontend/composables/useClinicProfile';
import { useI18n } from 'vue-i18n';
import AnamnesisAPI from '@plugins/patients/frontend/api/patients/anamnesis';
import {
  EMPTY_ANAMNESIS,
  deepCloneAnamnesis,
  applyAnamnesisState,
} from '@plugins/patients/frontend/features/patient-record/utils/anamnesisNormalizer';
import { UNPERMITTED_ANAMNESIS_KEYS } from '@plugins/patients/frontend/constants/anamnesis';

export function useAnamnesis(patientIdRef) {
  const { t } = useI18n();
  const { profile: clinicProfile, ensureLoaded: ensureClinicProfile } =
    useClinicProfile();

  // Carrega o perfil em background — quando chegar, novas anamneses passam
  // a pré-preencher `specialty` com `default_specialty` da clínica.
  ensureClinicProfile();

  const anamneses = ref([]);
  const currentAnamnesis = ref(EMPTY_ANAMNESIS());
  const allergyInput = ref('');
  const medicationInput = ref('');
  const isSaving = ref(false);

  const isDirty = ref(false);
  let suppressDirtyWatch = true;

  const buildDefaults = () => ({
    specialty: clinicProfile.value?.default_specialty || undefined,
  });

  const markDirty = () => {
    if (suppressDirtyWatch) return;
    if (currentAnamnesis.value.status === 'finalized') return;
    isDirty.value = true;
  };

  const resetDirty = () => {
    isDirty.value = false;
  };

  watch(currentAnamnesis, markDirty, { deep: true });
  watch(allergyInput, markDirty);
  watch(medicationInput, markDirty);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  // ── Helpers ────────────────────────────────────────────────
  const setStateSilently = source => {
    suppressDirtyWatch = true;
    applyAnamnesisState(currentAnamnesis.value, source, buildDefaults());
    setTimeout(() => {
      suppressDirtyWatch = false;
      resetDirty();
    }, 0);
  };

  const startNew = () => {
    setStateSilently(null);
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
    currentAnamnesis.value.allergies = (
      currentAnamnesis.value.allergies || []
    ).filter((_, i) => i !== idx);
  };

  const removeMedication = idx => {
    if (currentAnamnesis.value.status === 'finalized') return;
    currentAnamnesis.value.current_medications = (
      currentAnamnesis.value.current_medications || []
    ).filter((_, i) => i !== idx);
  };

  // ── Fetch ──────────────────────────────────────────────────
  const fetch = async () => {
    try {
      suppressDirtyWatch = true;
      const response = await AnamnesisAPI.get(resolveId());
      anamneses.value = response.data?.payload || response.data || [];
      applyAnamnesisState(
        currentAnamnesis.value,
        anamneses.value[0] || null,
        buildDefaults()
      );
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Anamnesis] Falha ao carregar', error);
      useNotification.error(t('PATIENT_ANAMNESIS.MESSAGES.LOAD_ERROR'));
    } finally {
      // Espera Vue propagar antes de reabilitar o tracking, senão o próprio
      // applyAnamnesisState dispara o watcher e marca dirty.
      setTimeout(() => {
        suppressDirtyWatch = false;
        resetDirty();
      }, 0);
    }
  };

  // ── Save / Finalize ────────────────────────────────────────
  const saveAnamnesis = async (finalize = false) => {
    if (isSaving.value) return { ok: false };
    try {
      isSaving.value = true;

      // Flush inputs soltos antes de montar o payload.
      flushAllergyInput();
      flushMedicationInput();

      const payload = deepCloneAnamnesis(currentAnamnesis.value);
      UNPERMITTED_ANAMNESIS_KEYS.forEach(key => delete payload[key]);

      let response;
      if (currentAnamnesis.value.id) {
        response = await AnamnesisAPI.update(
          resolveId(),
          currentAnamnesis.value.id,
          payload
        );
      } else {
        response = await AnamnesisAPI.create(resolveId(), payload);
      }

      const persisted = response.data?.payload || response.data;
      const savedId = persisted?.id || currentAnamnesis.value.id;

      if (finalize && savedId) {
        // Finalize delega o sync do state ao fetch final — evita duplo-sync
        // reativo entre save → finalize.
        await AnamnesisAPI.finalize(resolveId(), savedId);
        await fetch();
        useNotification.success(
          t('PATIENT_ANAMNESIS.MESSAGES.SAVE_FINALIZED_SUCCESS')
        );
      } else {
        if (persisted) {
          setStateSilently(persisted);
        } else {
          resetDirty();
        }
        useNotification.success(
          t('PATIENT_ANAMNESIS.MESSAGES.SAVE_DRAFT_SUCCESS')
        );
      }
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Anamnesis] Falha ao salvar', error);
      useNotification.error(
        error?.response?.data?.error || t('PATIENT_ANAMNESIS.MESSAGES.SAVE_ERROR')
      );
      return { ok: false };
    } finally {
      isSaving.value = false;
    }
  };

  return {
    anamneses,
    currentAnamnesis,
    clinicProfile,
    allergyInput,
    medicationInput,
    isSaving,
    isDirty,
    fetch,
    saveAnamnesis,
    startNew,
    flushAllergyInput,
    flushMedicationInput,
    removeAllergy,
    removeMedication,
  };
}
