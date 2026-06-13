import { ref, computed } from 'vue';
import AnamnesisAPI from '@plugins/patients/frontend/api/patients/anamnesis';

export function useClinicalTags(patientId, patient) {
  const currentAnamnesis = ref({});

  const fetchAnamnesisForTags = async () => {
    try {
      const response = await AnamnesisAPI.get(patientId);
      const list = response.data?.payload || response.data || [];
      currentAnamnesis.value = list[0] || {};
    } catch (error) {
      // Best-effort: tags clínicas são derivadas da anamnese. Se o fetch
      // falhar, deixamos as tags vazias (a aba Anamnese mostrará o alerta
      // proper quando o usuário abrir). Só logamos pra debug.
      currentAnamnesis.value = {};
      // eslint-disable-next-line no-console
      console.error('[Patient] Falha ao carregar anamnese para tags clínicas', error);
    }
  };

  const computedClinicalTags = computed(() => {
    const tags = [];
    (patient.value.critical_alerts || []).forEach(alert => {
      tags.push({
        type: 'danger',
        icon: 'i-lucide-triangle-alert',
        label: alert.title || alert.message,
      });
    });

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
        tags.push({
          type: 'danger',
          icon: 'i-lucide-ban',
          label: getString(c),
        });
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
        tags.push({
          type: 'warning',
          icon: 'i-lucide-baby',
          label: 'Grávida',
        });
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

  return { currentAnamnesis, fetchAnamnesisForTags, computedClinicalTags };
}
