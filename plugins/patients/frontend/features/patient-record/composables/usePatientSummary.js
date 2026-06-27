import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';

const blankPatient = () => ({
  id: null,
  name: '',
  social_name: '',
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
  notes: '',
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
  has_guardian: false,
  guardian: {
    name: '',
    cpf: '',
    phone: '',
    relationship: '',
  },
  insurance: {
    name: '',
    number: '',
    plan: '',
    validity: '',
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

export function usePatientSummary(patientId) {
  const patient = ref(blankPatient());
  const isLoading = ref(true);
  const lastConfirmedStatus = ref(null);
  const changeHistory = ref([]);
  const isHistoryLoading = ref(false);

  const fetchPatientSummary = async () => {
    try {
      isLoading.value = true;
      const response = await PatientsAPI.summary(patientId);

      const data = response.data?.payload || {};
      patient.value = {
        ...patient.value,
        ...data,
        address: { ...patient.value.address, ...(data.address || {}) },
        emergency_contact: {
          ...patient.value.emergency_contact,
          ...(data.emergency_contact || {}),
        },
        guardian: {
          ...patient.value.guardian,
          ...(data.guardian || {}),
        },
        has_guardian: Boolean(data.has_guardian),
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

      lastConfirmedStatus.value = patient.value.patient_status;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Patient] Falha ao carregar resumo', error);
      useAlert('Não foi possível carregar os dados do paciente.');
    } finally {
      isLoading.value = false;
    }
  };

  const fetchChangeHistory = async () => {
    try {
      isHistoryLoading.value = true;
      const response = await PatientsAPI.changeHistory(patientId);
      changeHistory.value = response.data?.payload || [];
    } catch (error) {
      // Histórico de mudanças é informativo (best-effort): só loga, não
      // alerta o usuário pra não atrapalhar o fluxo principal.
      // eslint-disable-next-line no-console
      console.error('[Patient] Falha ao carregar histórico de alterações', error);
    } finally {
      isHistoryLoading.value = false;
    }
  };

  // Optimistic update: BaseSelect/FormSelect já mutou patient.patient_status
  // via v-model antes de chamar handleStatusChange. Em falha de API, revertemos
  // para o último status confirmado pelo backend.
  const handleStatusChange = async newStatus => {
    const previous = lastConfirmedStatus.value;
    try {
      await PatientsAPI.updateStatus(patientId, newStatus);
      lastConfirmedStatus.value = newStatus;
    } catch (error) {
      if (previous !== null) patient.value.patient_status = previous;
      // eslint-disable-next-line no-console
      console.error('[Patient] Falha ao alterar status', error);
      useAlert('Erro ao alterar status do paciente. A mudança foi revertida.');
    }
  };

  return {
    patient,
    isLoading,
    lastConfirmedStatus,
    changeHistory,
    isHistoryLoading,
    fetchPatientSummary,
    fetchChangeHistory,
    handleStatusChange,
  };
}
