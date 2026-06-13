<script setup>
// FE-2 (auditoria 2026-05-18): extraído de GroupSettingsDrawer.vue (601 LOC).
// Seção de descrição do grupo — view + edição inline (textarea + botões
// Salvar/Cancelar). State da edição vive no pai; aqui só renderizamos e
// emitimos eventos.
// FE-8: BeclinicButton para "Editar" (link com icon) e Cancelar/Salvar.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

defineProps({
  room: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  isEditingDescription: { type: Boolean, default: false },
  editDescription: { type: String, default: '' },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:editDescription',
  'start-edit-description',
  'save-description',
  'cancel-edit-description',
]);

const onInput = e => emit('update:editDescription', e.target.value);
</script>

<template>
  <section class="px-5 py-4 border-b border-n-weak">
    <div class="flex items-center justify-between mb-1.5">
      <p class="text-xs font-medium text-n-brand uppercase tracking-wide">
        {{ $t('INTERNAL_CHAT.GROUP_SETTINGS.DESCRIPTION.TITLE') }}
      </p>
      <BeclinicButton
        v-if="canManage && !isEditingDescription"
        :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.DESCRIPTION.EDIT')"
        icon="i-lucide-pencil"
        variant="ghost"
        color="slate"
        size="xs"
        @click="$emit('start-edit-description')"
      />
    </div>
    <template v-if="isEditingDescription">
      <textarea
        :value="editDescription"
        rows="3"
        class="w-full px-3 py-2 text-sm rounded-md resize-none bg-n-alpha-1 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
        :disabled="isSaving"
        autofocus
        :placeholder="$t('INTERNAL_CHAT.GROUP_SETTINGS.DESCRIPTION.PLACEHOLDER')"
        @input="onInput"
      />
      <div class="flex justify-end gap-2 mt-2">
        <BeclinicButton
          :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.DESCRIPTION.CANCEL')"
          variant="ghost"
          color="slate"
          size="xs"
          :disabled="isSaving"
          @click="$emit('cancel-edit-description')"
        />
        <BeclinicButton
          :label="isSaving ? $t('INTERNAL_CHAT.GROUP_SETTINGS.DESCRIPTION.SAVING') : $t('INTERNAL_CHAT.GROUP_SETTINGS.DESCRIPTION.SAVE')"
          :is-loading="isSaving"
          size="xs"
          :disabled="isSaving"
          @click="$emit('save-description')"
        />
      </div>
    </template>
    <p
      v-else
      class="text-sm whitespace-pre-wrap"
      :class="room.description ? 'text-n-slate-12' : 'text-n-slate-10 italic'"
    >
      {{ room.description || $t('INTERNAL_CHAT.GROUP_SETTINGS.DESCRIPTION.EMPTY') }}
    </p>
  </section>
</template>
