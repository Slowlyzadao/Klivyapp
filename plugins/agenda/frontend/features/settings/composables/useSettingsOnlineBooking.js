import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';

export function useSettingsOnlineBooking(props, emit) {
  const onlineConfig = ref({
    enabled: true,
    allow_new_patients: true,
    require_whatsapp_verification: false,
    require_email_verification: false,
    min_lead_time_minutes: 180,
    future_limit_days: 60,
    form_fields: [],
  });

  const onlineConfigLoading = ref(false);
  const onlineSaving = ref(false);
  const selectedAgentId = ref(null);

  // Computed public link and selected agent matching original behavior
  const selectedAgent = computed(() => {
    if (selectedAgentId.value) {
      return (
        props.agents.find(a => a.id === selectedAgentId.value) ||
        props.currentUser
      );
    }
    return props.currentUser;
  });

  const publicUrl = computed(() => {
    const publicId = selectedAgent.value?.agenda_public_id || 'link-indisponivel';
    return `${window.location.origin}/agenda/${publicId}`;
  });

  const fetchOnlineConfig = async () => {
    onlineConfigLoading.value = true;
    try {
      const { data } = await window.axios.get(
        `/api/v1/accounts/${props.accountId}/agenda_online_config`
      );
      if (data) {
        // Deep merge ou assignment
        onlineConfig.value = { ...onlineConfig.value, ...data };
      }
    } catch (_e) {
      // Falha silenciosa - usa defaults
    } finally {
      onlineConfigLoading.value = false;
    }
  };

  const saveOnlineConfig = async () => {
    onlineSaving.value = true;
    try {
      await Promise.all([
        window.axios.patch(
          `/api/v1/accounts/${props.accountId}/agenda_online_config`,
          { agenda_online_config: onlineConfig.value }
        ),
        // Chama evento que fará o trigger do this.persistSettings() do pai
        emit('persist-settings')
      ]);
      useAlert('Configurações salvas com sucesso!');
    } catch (_e) {
      useAlert('Falha ao salvar as configurações.');
    } finally {
      onlineSaving.value = false;
    }
  };

  const copyPublicUrl = () => {
    try {
      navigator.clipboard.writeText(publicUrl.value);
      useAlert('Link copiado para a área de transferência!');
    } catch (_e) {
      // fallback silencioso
    }
  };

  return {
    onlineConfig,
    onlineConfigLoading,
    onlineSaving,
    selectedAgentId,
    selectedAgent,
    publicUrl,
    fetchOnlineConfig,
    saveOnlineConfig,
    copyPublicUrl
  };
}
