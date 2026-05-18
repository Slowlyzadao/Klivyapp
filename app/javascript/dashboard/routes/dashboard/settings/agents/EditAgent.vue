<script setup>
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import Auth from '../../../../api/auth';
import wootConstants from 'dashboard/constants/globals';
import AgendaServicesAPI from '@plugins/agenda/frontend/api/agendaServices';
import { onClickOutside } from '@vueuse/core';

const props = defineProps({
  id: {
    type: Number,
    required: true,
  },
  name: {
    type: String,
    required: true,
  },
  email: {
    type: String,
    default: '',
  },
  type: {
    type: String,
    default: '',
  },
  availability: {
    type: String,
    default: '',
  },
  provider: {
    type: String,
    default: '',
  },
  customRoleId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['close']);

const { AVAILABILITY_STATUS_KEYS } = wootConstants;

const store = useStore();
const { t } = useI18n();

const agentName = ref(props.name);
const agentAvailability = ref(props.availability);
const selectedRoleId = ref(props.customRoleId || props.type);
const agentCredentials = ref({ email: props.email });

// "Serviços oferecidos" — Bea só considera o profissional como elegível
// pra agendar um serviço se ele estiver listado aqui. Inicializa do
// próprio store (agente já carregado pelo Index) e fetcha o catálogo de
// serviços disponíveis pra renderizar os chips.
const allAgents = useMapGetter('agents/getAgents');
const initialServiceIds = computed(() => {
  const agent = allAgents.value?.find(a => a.id === props.id);
  return Array.isArray(agent?.agenda_service_ids) ? agent.agenda_service_ids : [];
});

const selectedServiceIds = ref([...initialServiceIds.value]);
const availableServices = ref([]);

onMounted(async () => {
  try {
    const { data } = await AgendaServicesAPI.get();
    availableServices.value = Array.isArray(data) ? data : [];
  } catch (_e) {
    availableServices.value = [];
  }
});

// Combobox state. `serviceSearch` é o termo digitado; o dropdown só aparece
// quando o input está focado E há algo pra mostrar. Selected services
// renderizam como chips removíveis abaixo do input.
//
// O dropdown é teleportado para <body> com posicionamento fixed pra (a)
// não estourar o modal e empurrar conteúdo, (b) não brigar com z-index
// dos botões do footer do modal. dropdownStyle é recalculado em scroll
// e resize pra acompanhar o input.
const serviceSearch = ref('');
const isServiceDropdownOpen = ref(false);
const searchInputWrap = ref(null);
const dropdownEl = ref(null);
const dropdownStyle = ref({});

const updateDropdownPosition = async () => {
  await nextTick();
  if (!searchInputWrap.value) return;
  const rect = searchInputWrap.value.getBoundingClientRect();
  dropdownStyle.value = {
    position: 'fixed',
    top: `${rect.bottom + 4}px`,
    left: `${rect.left}px`,
    width: `${rect.width}px`,
    zIndex: 9999,
  };
};

const openServiceDropdown = () => {
  isServiceDropdownOpen.value = true;
  updateDropdownPosition();
};

const closeServiceDropdown = () => {
  isServiceDropdownOpen.value = false;
  serviceSearch.value = '';
};

onClickOutside(
  searchInputWrap,
  () => {
    if (isServiceDropdownOpen.value) closeServiceDropdown();
  },
  { ignore: [dropdownEl] }
);

const onScrollOrResize = () => {
  if (isServiceDropdownOpen.value) updateDropdownPosition();
};

onMounted(() => {
  window.addEventListener('scroll', onScrollOrResize, true);
  window.addEventListener('resize', onScrollOrResize);
});

onBeforeUnmount(() => {
  window.removeEventListener('scroll', onScrollOrResize, true);
  window.removeEventListener('resize', onScrollOrResize);
});

const filteredServices = computed(() => {
  const term = serviceSearch.value.trim().toLowerCase();
  return availableServices.value
    .filter(s => !selectedServiceIds.value.includes(s.id))
    .filter(s => term === '' || (s.name || '').toLowerCase().includes(term))
    .slice(0, 50); // cap pra não renderizar listão se clínica tiver 1000+ serviços
});

const selectedServices = computed(() =>
  selectedServiceIds.value
    .map(id => availableServices.value.find(s => s.id === id))
    .filter(Boolean)
);

const addService = id => {
  if (!selectedServiceIds.value.includes(id)) {
    selectedServiceIds.value.push(id);
  }
  serviceSearch.value = '';
  // Mantém aberto pra usuário selecionar mais sem precisar clicar de novo
  isServiceDropdownOpen.value = true;
};

const removeService = id => {
  const idx = selectedServiceIds.value.indexOf(id);
  if (idx !== -1) selectedServiceIds.value.splice(idx, 1);
};

const rules = {
  agentName: { required, minLength: minLength(1) },
  selectedRoleId: { required },
  agentAvailability: { required },
};

const v$ = useVuelidate(rules, {
  agentName,
  selectedRoleId,
  agentAvailability,
});

const pageTitle = computed(
  () => `${t('AGENT_MGMT.EDIT.TITLE')} - ${props.name}`
);

const uiFlags = useMapGetter('agents/getUIFlags');
const getCustomRoles = useMapGetter('customRole/getCustomRoles');

const roles = computed(() => {
  const defaultRoles = [
    {
      id: 'administrator',
      name: 'administrator',
      label: t('AGENT_MGMT.AGENT_TYPES.ADMINISTRATOR'),
    },
    {
      id: 'agent',
      name: 'agent',
      label: t('AGENT_MGMT.AGENT_TYPES.AGENT'),
    },
  ];

  const customRoles = getCustomRoles.value.map(role => ({
    id: role.id,
    name: `custom_${role.id}`,
    label: role.name,
  }));

  return [...defaultRoles, ...customRoles];
});

const selectedRole = computed(() =>
  roles.value.find(
    role =>
      role.id === selectedRoleId.value || role.name === selectedRoleId.value
  )
);

const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

const availabilityStatuses = computed(() =>
  statusList.value.map((statusLabel, index) => ({
    label: statusLabel,
    value: AVAILABILITY_STATUS_KEYS[index],
    disabled: props.availability === AVAILABILITY_STATUS_KEYS[index],
  }))
);

const editAgent = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    const payload = {
      id: props.id,
      name: agentName.value,
      availability: agentAvailability.value,
      agenda_service_ids: [...selectedServiceIds.value],
    };

    if (selectedRole.value.name.startsWith('custom_')) {
      payload.custom_role_id = selectedRole.value.id;
    } else {
      payload.role = selectedRole.value.name;
      payload.custom_role_id = null;
    }

    await store.dispatch('agents/update', payload);
    useAlert(t('AGENT_MGMT.EDIT.API.SUCCESS_MESSAGE'));
    emit('close');
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.API.ERROR_MESSAGE'));
  }
};

const resetPassword = async () => {
  try {
    await Auth.resetPassword(agentCredentials.value);
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('AGENT_MGMT.EDIT.PASSWORD_RESET.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="pageTitle" />
    <form class="w-full" @submit.prevent="editAgent">
      <div class="w-full">
        <label :class="{ error: v$.agentName.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.NAME.LABEL') }}
          <input
            v-model="agentName"
            type="text"
            :placeholder="$t('AGENT_MGMT.EDIT.FORM.NAME.PLACEHOLDER')"
            @input="v$.agentName.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.selectedRoleId.$error }">
          {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.LABEL') }}
          <select v-model="selectedRoleId" @change="v$.selectedRoleId.$touch">
            <option v-for="role in roles" :key="role.id" :value="role.id">
              {{ role.label }}
            </option>
          </select>
          <span v-if="v$.selectedRoleId.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_TYPE.ERROR') }}
          </span>
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.agentAvailability.$error }">
          {{ $t('PROFILE_SETTINGS.FORM.AVAILABILITY.LABEL') }}
          <select
            v-model="agentAvailability"
            @change="v$.agentAvailability.$touch"
          >
            <option
              v-for="status in availabilityStatuses"
              :key="status.value"
              :value="status.value"
            >
              {{ status.label }}
            </option>
          </select>
          <span v-if="v$.agentAvailability.$error" class="message">
            {{ $t('AGENT_MGMT.EDIT.FORM.AGENT_AVAILABILITY.ERROR') }}
          </span>
        </label>
      </div>

      <div v-if="availableServices.length > 0" class="w-full mb-2">
        <span class="block text-sm font-medium text-n-slate-12">
          Serviços oferecidos (opcional)
        </span>
        <p class="mt-1 mb-2 text-xs text-n-slate-11">
          Comece a digitar para buscar um procedimento e clique para adicioná-lo.
          A Beatriz só vai oferecer agendamento com esse profissional para os
          serviços listados abaixo. Se nenhum estiver marcado, a Beatriz não
          considera esse profissional para nenhum serviço.
        </p>

        <div ref="searchInputWrap" class="relative">
          <input
            v-model="serviceSearch"
            type="text"
            placeholder="Buscar serviço..."
            class="w-full px-3 py-2 text-sm border rounded-md border-n-slate-5 bg-n-alpha-black2 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-teal-9"
            @focus="openServiceDropdown"
            @input="openServiceDropdown"
          />
        </div>

        <Teleport to="body">
          <div
            v-if="isServiceDropdownOpen && filteredServices.length > 0"
            ref="dropdownEl"
            :style="dropdownStyle"
            class="overflow-y-auto bg-white border rounded-md shadow-lg max-h-60 border-n-slate-5"
          >
            <button
              v-for="service in filteredServices"
              :key="service.id"
              type="button"
              class="block w-full px-3 py-2 text-sm text-left hover:bg-n-slate-3 text-n-slate-12"
              @click="addService(service.id)"
            >
              {{ service.name }}
            </button>
          </div>
          <div
            v-else-if="
              isServiceDropdownOpen && serviceSearch.trim().length > 0
            "
            ref="dropdownEl"
            :style="dropdownStyle"
            class="px-3 py-2 text-sm bg-white border rounded-md shadow-lg border-n-slate-5 text-n-slate-11"
          >
            Nenhum serviço encontrado.
          </div>
        </Teleport>

        <div
          v-if="selectedServices.length > 0"
          class="flex flex-wrap gap-2 mt-3"
        >
          <span
            v-for="service in selectedServices"
            :key="service.id"
            class="inline-flex items-center gap-1 pl-3 pr-1 py-1 text-xs font-medium text-white rounded-full bg-n-teal-9"
          >
            {{ service.name }}
            <button
              type="button"
              class="flex items-center justify-center w-5 h-5 rounded-full hover:bg-n-teal-10"
              :title="`Remover ${service.name}`"
              @click="removeService(service.id)"
            >
              ×
            </button>
          </span>
        </div>
      </div>

      <div class="flex flex-row justify-start w-full gap-2 px-0 py-2">
        <div class="w-[50%] ltr:text-left rtl:text-right">
          <Button
            v-if="provider !== 'saml'"
            ghost
            type="button"
            icon="i-lucide-lock-keyhole"
            class="!px-2"
            :label="$t('AGENT_MGMT.EDIT.PASSWORD_RESET.ADMIN_RESET_BUTTON')"
            @click.prevent="resetPassword"
          />
        </div>
        <div class="w-[50%] flex justify-end items-center gap-2">
          <Button
            faded
            slate
            type="reset"
            :label="$t('AGENT_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
            @click.prevent="emit('close')"
          />
          <Button
            type="submit"
            :label="$t('AGENT_MGMT.EDIT.FORM.SUBMIT')"
            :disabled="v$.$invalid || uiFlags.isUpdating"
            :is-loading="uiFlags.isUpdating"
          />
        </div>
      </div>
    </form>
  </div>
</template>
