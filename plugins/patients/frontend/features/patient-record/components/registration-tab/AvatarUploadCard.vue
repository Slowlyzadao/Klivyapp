<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

defineProps({
  avatarUrl: { type: String, default: '' },
  patientName: { type: String, default: '' },
});

const emit = defineEmits(['file-selected', 'open-camera']);

const { t } = useI18n();
const avatarInputRef = ref(null);

const triggerUpload = () => avatarInputRef.value?.click();

const handleChange = event => {
  const file = event.target.files?.[0];
  if (file) emit('file-selected', file);
  if (avatarInputRef.value) avatarInputRef.value.value = '';
};
</script>

<template>
  <div class="reg-avatar-row">
    <div class="reg-avatar-wrapper" @click="triggerUpload">
      <!-- Usa o Avatar canônico pra herdar o mesmo hash de cor/iniciais
           que aparece na lista e no banner do prontuário. -->
      <Avatar
        :src="avatarUrl"
        :name="patientName || ''"
        :size="80"
        rounded-full
      />
      <div class="reg-avatar-overlay">
        <i class="i-lucide-camera w-5 h-5" />
      </div>
    </div>
    <div class="reg-avatar-info">
      <p class="text-sm font-medium text-slate-200">
        {{ t('PATIENT_REGISTRATION.AVATAR.TITLE') }}
      </p>
      <p class="text-xs text-slate-500 mt-0.5">
        {{ t('PATIENT_REGISTRATION.AVATAR.HINT') }}
      </p>
      <div class="flex gap-2 mt-3">
        <BeclinicButton
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-camera"
          :label="t('PATIENT_REGISTRATION.AVATAR.CAMERA')"
          @click.stop="emit('open-camera')"
        />
        <BeclinicButton
          size="sm"
          variant="faded"
          color="slate"
          icon="i-lucide-upload"
          :label="t('PATIENT_REGISTRATION.AVATAR.UPLOAD')"
          @click.stop="triggerUpload"
        />
      </div>
      <input
        ref="avatarInputRef"
        type="file"
        class="hidden"
        accept="image/jpeg, image/png, image/gif"
        @change="handleChange"
      />
    </div>
  </div>
</template>
