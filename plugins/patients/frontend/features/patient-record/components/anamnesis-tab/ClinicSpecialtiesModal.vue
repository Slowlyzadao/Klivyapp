<script setup>
/**
 * ClinicSpecialtiesModal — configura as especialidades atendidas pela clínica
 * e qual delas é o padrão para novas anamneses.
 *
 * Acessível inline pelo header da Anamnese ("Configurar especialidades"). Em
 * vez de criar uma tela de Configurações dedicada agora, deixamos o ajuste
 * acontecer onde o atrito é sentido. Em PR futuro pode migrar pra um menu
 * "Perfil da Clínica" centralizado.
 *
 * Backend: PATCH /api/v1/accounts/:id/clinic_profile
 *   body: { default_specialty, enabled_specialties: [] }
 */
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import { useClinicProfile } from '@plugins/beclinic_core/frontend/composables/useClinicProfile';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { SPECIALTY_OPTIONS } from '@plugins/patients/frontend/constants/anamnesis';

const props = defineProps({
  open: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const { profile, isSaving, ensureLoaded, save } = useClinicProfile();

const enabledMap = ref({});
const defaultSpecialty = ref(null);

const allOptions = computed(() => {
  // União das opções padrão + qualquer que já esteja salva no perfil mas
  // não exista mais em SPECIALTY_OPTIONS (ex.: futuras opções customizadas).
  const out = [...SPECIALTY_OPTIONS];
  (profile.value.enabled_specialties || []).forEach(label => {
    if (!out.some(o => o.value === label)) out.push({ value: label, label });
  });
  return out;
});

const enabledList = computed(() =>
  Object.entries(enabledMap.value)
    .filter(([, on]) => on)
    .map(([k]) => k)
);

const defaultOptions = computed(() => {
  const list = enabledList.value;
  if (list.length === 0) return allOptions.value;
  return allOptions.value.filter(o => list.includes(o.value));
});

const syncFromProfile = () => {
  const enabled = profile.value.enabled_specialties || [];
  enabledMap.value = allOptions.value.reduce((acc, opt) => {
    acc[opt.value] = enabled.length === 0 || enabled.includes(opt.value);
    return acc;
  }, {});
  defaultSpecialty.value = profile.value.default_specialty || null;
};

watch(
  () => props.open,
  async isOpen => {
    if (!isOpen) return;
    await ensureLoaded();
    syncFromProfile();
  },
  { immediate: true }
);

// Se o usuário desmarca a especialidade que estava como default, escolhemos
// a primeira habilitada (ou null) automaticamente — evita salvar um default
// "fantasma" que não está mais na lista enabled.
watch(enabledList, list => {
  if (defaultSpecialty.value && !list.includes(defaultSpecialty.value)) {
    defaultSpecialty.value = list[0] || null;
  }
});

const onSave = async () => {
  const enabled_specialties = enabledList.value;
  // Se nada foi marcado, salvamos lista vazia → significa "atende todas".
  // Comportamento espelha o backend: array vazio = sem filtro.
  const result = await save({
    default_specialty: defaultSpecialty.value || null,
    enabled_specialties,
  });
  if (result.ok) {
    useNotification.success(
      t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.SAVE_SUCCESS')
    );
    emit('close');
  } else {
    useNotification.error(t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.SAVE_ERROR'));
  }
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md p-0 sm:p-4"
  >
    <div
      class="bg-n-background sm:border sm:border-n-strong sm:rounded-xl shadow-2xl w-full h-full sm:max-w-lg sm:h-auto sm:max-h-[90vh] flex flex-col overflow-hidden"
    >
      <div
        class="flex items-center justify-between px-5 py-4 border-b border-n-strong flex-shrink-0"
      >
        <div class="flex items-center gap-3">
          <i class="i-lucide-stethoscope w-5 h-5 text-n-blue-9" />
          <div>
            <h3 class="text-base font-semibold text-n-slate-12">
              {{ t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.TITLE') }}
            </h3>
            <p class="text-xs text-n-slate-9 mt-0.5">
              {{ t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.SUBTITLE') }}
            </p>
          </div>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div class="flex-1 overflow-y-auto px-5 py-4 flex flex-col gap-5">
        <section>
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-9 mb-2">
            {{ t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.ENABLED_LABEL') }}
          </p>
          <p class="text-xs text-n-slate-9 mb-3">
            {{ t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.ENABLED_HINT') }}
          </p>
          <div class="flex flex-col gap-2">
            <Checkbox
              v-for="opt in allOptions"
              :key="opt.value"
              v-model="enabledMap[opt.value]"
              :label="opt.label"
              class="!flex w-full px-3 py-2 rounded-lg border border-n-strong bg-n-slate-2 hover:border-n-blue-9 transition-colors"
            />
          </div>
        </section>

        <section>
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-9 mb-2">
            {{ t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.DEFAULT_LABEL') }}
          </p>
          <p class="text-xs text-n-slate-9 mb-3">
            {{ t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.DEFAULT_HINT') }}
          </p>
          <FormSelect
            v-model="defaultSpecialty"
            :options="defaultOptions"
            clearable
            :placeholder="t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.DEFAULT_PLACEHOLDER')"
          />
        </section>
      </div>

      <div
        class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-strong flex-shrink-0"
      >
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-check"
          :label="t('PATIENT_ANAMNESIS.CLINIC_SPECIALTIES.SAVE')"
          :is-loading="isSaving"
          :disabled="isSaving"
          @click="onSave"
        />
      </div>
    </div>
  </div>
</template>
