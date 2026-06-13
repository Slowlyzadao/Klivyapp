/**
 * useRegistrationActions — mutações da aba Cadastro (Roadmap #12).
 *
 *   updateAvatar(file)    → faz upload + atualiza patient.avatar_url
 *   saveRegistration()    → valida CPF + monta payload + grava + emit('saved')
 *
 * Encapsula serialização do payload (CPF/phone digit-only, +55 prefix,
 * guardian zerado se has_guardian=false) que estava inline.
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import { isValidCPF } from '@plugins/beclinic_core/frontend/helpers/cpfHelpers';
import {
  isValidEmail,
  isValidBrazilianPhone,
} from '@plugins/beclinic_core/frontend/helpers/contactValidators';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';

const onlyDigits = v => (v ? String(v).replace(/\D/g, '') : '');
const phoneE164 = v => {
  const digits = onlyDigits(v).replace(/^55/, '');
  return digits ? `+55${digits}` : '';
};

export function useRegistrationActions(patientIdRef, { onSaved } = {}) {
  const { t } = useI18n();

  const isLoading = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const updateAvatar = async (file, patient) => {
    if (!file) return { ok: false };
    isLoading.value = true;
    try {
      const { data } = await PatientsAPI.updateAvatar(resolveId(), file);
      // Mutate patient prop directly: parent passa por ref, então mantém o
      // pattern existente do componente e o header re-renderiza imediato.
      // eslint-disable-next-line no-param-reassign
      patient.avatar_url =
        data.payload?.avatar_url || data.avatar_url || '';
      useNotification.success(t('PATIENT_REGISTRATION.MESSAGES.AVATAR_SUCCESS'));
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Registration] Falha ao atualizar avatar', error);
      useNotification.error(t('PATIENT_REGISTRATION.MESSAGES.AVATAR_ERROR'));
      return { ok: false };
    } finally {
      isLoading.value = false;
    }
  };

  const saveRegistration = async (patient, { original = null } = {}) => {
    if (patient.cpf && !isValidCPF(patient.cpf)) {
      useNotification.warning(t('PATIENT_REGISTRATION.MESSAGES.INVALID_CPF'));
      return { ok: false };
    }
    if (
      patient.has_guardian &&
      patient.guardian?.cpf &&
      !isValidCPF(patient.guardian.cpf)
    ) {
      useNotification.warning(
        t('PATIENT_REGISTRATION.MESSAGES.INVALID_GUARDIAN_CPF')
      );
      return { ok: false };
    }
    // Grandfathering: valida e-mail/telefone só quando o valor MUDOU em relação
    // ao carregado — espelha a regra on-change do backend (Patient#email_changed?),
    // pra não travar o save de registro legado com contato inválido que o
    // operador nem tocou. Sem `original` (ex.: outro caller), valida sempre.
    const changedFrom = (cur, orig) =>
      original == null || String(cur ?? '') !== String(orig ?? '');

    if (
      changedFrom(patient.email, original?.email) &&
      patient.email &&
      !isValidEmail(patient.email)
    ) {
      useNotification.warning(t('PATIENT_REGISTRATION.MESSAGES.INVALID_EMAIL'));
      return { ok: false };
    }
    if (
      changedFrom(patient.phone, original?.phone) &&
      patient.phone &&
      !isValidBrazilianPhone(patient.phone)
    ) {
      useNotification.warning(t('PATIENT_REGISTRATION.MESSAGES.INVALID_PHONE'));
      return { ok: false };
    }
    if (
      changedFrom(patient.emergency_contact?.phone, original?.altPhone) &&
      patient.emergency_contact?.phone &&
      !isValidBrazilianPhone(patient.emergency_contact.phone)
    ) {
      useNotification.warning(
        t('PATIENT_REGISTRATION.MESSAGES.INVALID_ALT_PHONE')
      );
      return { ok: false };
    }

    isLoading.value = true;
    try {
      const payload = {
        name: patient.name,
        social_name: patient.social_name || '',
        cpf: onlyDigits(patient.cpf),
        rg: patient.rg
          ? String(patient.rg).replace(/[^a-zA-Z0-9]/g, '').toUpperCase()
          : '',
        birthdate: patient.birthdate,
        sex: patient.sex,
        marital_status: patient.marital_status,
        phone: phoneE164(patient.phone),
        email: patient.email,
        notes: patient.notes || '',
        address: patient.address,
        emergency_contact: {
          ...patient.emergency_contact,
          phone: phoneE164(patient.emergency_contact?.phone),
        },
        has_guardian: Boolean(patient.has_guardian),
        guardian: patient.has_guardian
          ? {
              name: patient.guardian?.name || '',
              cpf: onlyDigits(patient.guardian?.cpf),
              phone: patient.guardian?.phone || '',
              relationship: patient.guardian?.relationship || '',
            }
          : { name: '', cpf: '', phone: '', relationship: '' },
        insurance: patient.insurance,
        communication_opt_ins: patient.communication_opt_ins,
        lgpd_consent: patient.lgpd_consent,
        contact_id: patient.contact_id,
      };
      await PatientsAPI.update(resolveId(), payload);
      if (typeof onSaved === 'function') await onSaved();
      useNotification.success(t('PATIENT_REGISTRATION.MESSAGES.SAVE_SUCCESS'));
      return { ok: true };
    } catch (error) {
      const backendErrors = error?.response?.data?.errors;
      if (Array.isArray(backendErrors) && backendErrors.length > 0) {
        useNotification.error(
          t('PATIENT_REGISTRATION.MESSAGES.SAVE_ERROR_PREFIX', {
            errors: backendErrors.join('; '),
          })
        );
      } else {
        useNotification.error(t('PATIENT_REGISTRATION.MESSAGES.SAVE_ERROR'));
      }
      return { ok: false };
    } finally {
      isLoading.value = false;
    }
  };

  return {
    isLoading,
    updateAvatar,
    saveRegistration,
  };
}
