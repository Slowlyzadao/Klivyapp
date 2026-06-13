/**
 * useTreatmentPlans — fetch + mutations da aba Plano de Tratamento.
 *
 *   fetch()                                   → lista
 *   create({title, description})              → cria + refresh, retorna newId
 *   updatePlan(plan)                          → grava (com lock_version #13)
 *   approvePlan(planId)                       → aprova plano + gera Financial::Budget rascunho (recepção aprova depois no Financial Tab)
 *   deletePlan(planId)                        → remove
 *   saveItem(planId, item, override?)         → cria/atualiza item + #16 guard
 *   deleteItem(planId, itemId)                → remove item
 *
 * Lock version: trata 409 com `code: 'version_conflict'` recarregando lista.
 *
 * Clinical guard (Roadmap #16): caller faz o check com
 * `usePatientClinicalGuards` antes de chamar `saveItem` — se houver
 * conflito, abre modal e ao confirmar passa `clinicalOverrideReason`.
 * Override é registrado em PatientAuditLog pelo treatment_items_controller.
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import TreatmentPlansAPI from '@plugins/patients/frontend/api/patients/treatmentPlans';

export function useTreatmentPlans(patientIdRef) {
  const { t } = useI18n();

  const treatmentPlans = ref([]);
  const isSavingItem = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const isVersionConflict = error =>
    error?.response?.status === 409 &&
    error?.response?.data?.code === 'version_conflict';

  const fetch = async () => {
    try {
      const { data } = await TreatmentPlansAPI.get(resolveId());
      treatmentPlans.value = data?.data || data || [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[TreatmentPlan] Falha ao carregar planos', error);
      useNotification.error(t('PATIENT_TREATMENT_PLAN.MESSAGES.LOAD_ERROR'));
    }
  };

  const create = async ({ title, description }) => {
    try {
      const res = await TreatmentPlansAPI.create(resolveId(), {
        title,
        description,
      });
      useNotification.success(t('PATIENT_TREATMENT_PLAN.MESSAGES.CREATE_SUCCESS'));
      await fetch();
      const newId = res.data?.payload?.id || res.data?.id;
      return { ok: true, id: newId };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[TreatmentPlan] Falha ao criar plano', error);
      useNotification.error(t('PATIENT_TREATMENT_PLAN.MESSAGES.CREATE_ERROR'));
      return { ok: false };
    }
  };

  const updatePlan = async plan => {
    try {
      await TreatmentPlansAPI.update(resolveId(), plan.id, {
        title: plan.title,
        description: plan.description,
        estimated_duration: plan.estimated_duration,
        lock_version: plan.lock_version,
      });
      useNotification.success(t('PATIENT_TREATMENT_PLAN.MESSAGES.UPDATE_SUCCESS'));
      await fetch();
      return { ok: true };
    } catch (error) {
      if (isVersionConflict(error)) {
        useNotification.warning(
          t('PATIENT_TREATMENT_PLAN.MESSAGES.VERSION_CONFLICT')
        );
        await fetch();
        return { ok: false, conflict: true };
      }
      // eslint-disable-next-line no-console
      console.error('[TreatmentPlan] Falha ao atualizar plano', error);
      useNotification.error(t('PATIENT_TREATMENT_PLAN.MESSAGES.UPDATE_ERROR'));
      return { ok: false };
    }
  };

  // Variant: salva sem alert de sucesso, usado antes de abrir modal de item
  // (para flush de edits pendentes). Trata version_conflict diferente.
  const updatePlanSilent = async plan => {
    try {
      await TreatmentPlansAPI.update(resolveId(), plan.id, {
        title: plan.title,
        description: plan.description,
        estimated_duration: plan.estimated_duration,
        lock_version: plan.lock_version,
      });
      return { ok: true };
    } catch (error) {
      if (isVersionConflict(error)) {
        useNotification.warning(
          t('PATIENT_TREATMENT_PLAN.MESSAGES.VERSION_CONFLICT_BEFORE_ITEM')
        );
        await fetch();
        return { ok: false, conflict: true };
      }
      // eslint-disable-next-line no-console
      console.error('[TreatmentPlan] Falha ao atualizar plano', error);
      return { ok: false };
    }
  };

  const approvePlan = async planId => {
    try {
      await TreatmentPlansAPI.approve(resolveId(), planId);
      useNotification.success(
        t('PATIENT_TREATMENT_PLAN.MESSAGES.APPROVE_SUCCESS')
      );
      await fetch();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[TreatmentPlan] Falha ao aprovar plano', error);
      useNotification.error(t('PATIENT_TREATMENT_PLAN.MESSAGES.APPROVE_ERROR'));
      return { ok: false };
    }
  };

  // Canon Regra 3 — exclusão de PT com Budget v2 vinculado:
  //   • 409 + cascade_required → caller deve abrir modal de confirmação dupla
  //     e re-chamar com confirmCascade=true (envia header X-Confirm-Cascade).
  //   • 422 → bloqueado por parcela paga, mensagem do backend é mostrada como erro.
  //   • 200/204 → sucesso normal.
  const deletePlan = async (planId, { confirmCascade = false } = {}) => {
    try {
      await TreatmentPlansAPI.destroy(resolveId(), planId, { confirmCascade });
      useNotification.success(t('PATIENT_TREATMENT_PLAN.MESSAGES.DELETE_SUCCESS'));
      await fetch();
      return { ok: true };
    } catch (error) {
      const status = error?.response?.status;
      const data = error?.response?.data || {};

      if (status === 409 && data?.cascade_required) {
        return { ok: false, cascade: true, budget: data.budget };
      }

      if (status === 422 && data?.error) {
        useNotification.error(data.error);
        return { ok: false, blocked: true };
      }

      // eslint-disable-next-line no-console
      console.error('[TreatmentPlan] Falha ao excluir plano', error);
      useNotification.error(t('PATIENT_TREATMENT_PLAN.MESSAGES.DELETE_ERROR'));
      return { ok: false };
    }
  };

  const saveItem = async (planId, item, { clinicalOverrideReason = null } = {}) => {
    if (!item.procedure_name?.trim()) {
      useNotification.warning(
        t('PATIENT_TREATMENT_PLAN.MESSAGES.ITEM_MISSING_PROCEDURE')
      );
      return { ok: false };
    }
    if (!item.unit_price || item.unit_price <= 0) {
      useNotification.warning(
        t('PATIENT_TREATMENT_PLAN.MESSAGES.ITEM_INVALID_PRICE')
      );
      return { ok: false };
    }

    isSavingItem.value = true;
    try {
      const payload = { ...item };
      if (clinicalOverrideReason) {
        payload.clinical_override_reason = clinicalOverrideReason;
        // Auditoria forense é gravada pelo backend em PatientAuditLog
        // (action `clinical_override`). Console é só pra debug local.
        // eslint-disable-next-line no-console
        console.warn('[ClinicalGuard] Override registrado em item de plano', {
          patient_id: resolveId(),
          reason: clinicalOverrideReason,
        });
      }
      if (item.id) {
        await TreatmentPlansAPI.updateItem(resolveId(), planId, item.id, payload);
        useNotification.success(t('PATIENT_TREATMENT_PLAN.MESSAGES.ITEM_UPDATED'));
      } else {
        await TreatmentPlansAPI.createItem(resolveId(), planId, payload);
        useNotification.success(t('PATIENT_TREATMENT_PLAN.MESSAGES.ITEM_CREATED'));
      }
      await fetch();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[TreatmentPlan] Falha ao salvar procedimento', error);
      useNotification.error(t('PATIENT_TREATMENT_PLAN.MESSAGES.ITEM_SAVE_ERROR'));
      return { ok: false };
    } finally {
      isSavingItem.value = false;
    }
  };

  const deleteItem = async (planId, itemId) => {
    try {
      await TreatmentPlansAPI.deleteItem(resolveId(), planId, itemId);
      useNotification.success(t('PATIENT_TREATMENT_PLAN.MESSAGES.ITEM_REMOVED'));
      await fetch();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[TreatmentPlan] Falha ao remover procedimento', error);
      useNotification.error(
        t('PATIENT_TREATMENT_PLAN.MESSAGES.ITEM_REMOVE_ERROR')
      );
      return { ok: false };
    }
  };

  return {
    treatmentPlans,
    isSavingItem,
    fetch,
    create,
    updatePlan,
    updatePlanSilent,
    approvePlan,
    deletePlan,
    saveItem,
    deleteItem,
  };
}
