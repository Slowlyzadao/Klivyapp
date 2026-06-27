<script setup>
// FE-2 (auditoria 2026-05-18): extraído de GroupSettingsDrawer.vue (601 LOC).
// Hero do drawer: avatar grande + botão trocar imagem + nome com edição
// inline + contador de membros. Estilo WhatsApp.
//
// FE-6: `<Tooltip>` preservado em todos os botões com hint.
// O `<input type="file">` usa ref local (avatarInputRef) — o pai não
// precisa controlar abertura do file picker, basta ouvir `avatar-pick`.
//
// `editName` é v-model — pai gerencia o state da edição inline.
import { ref } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
// FE-8: BeclinicButton para o link "remover avatar". Demais botões (camera
// overlay, edit-name inline) ficam nativos por terem visual contextual com
// Tooltip wrapper + posicionamento absoluto sobre avatar.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  room: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  isUploadingAvatar: { type: Boolean, default: false },
  isEditingName: { type: Boolean, default: false },
  editName: { type: String, default: '' },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:editName',
  'avatar-pick',
  'remove-avatar',
  'start-edit-name',
  'save-name',
  'cancel-edit-name',
]);

const avatarInputRef = ref(null);

const onAvatarChange = e => emit('avatar-pick', e);

const onNameInput = e => emit('update:editName', e.target.value);

const memberCount = () => props.room.members?.length || 0;
</script>

<template>
  <section class="flex flex-col items-center gap-3 px-5 py-6 border-b border-n-weak">
    <div class="relative">
      <Avatar
        :key="room.avatar_updated_at || 'no-avatar'"
        :name="room.name || $t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.GROUP_FALLBACK_NAME')"
        :src="room.avatar_url || ''"
        :size="120"
        rounded-full
      />
      <!-- FE-6: Tooltip absorve `absolute bottom-0 right-0` pra
           preservar overlay sobre o avatar. -->
      <Tooltip
        v-if="canManage"
        :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.CHANGE_AVATAR_TOOLTIP')"
        class="absolute bottom-0 right-0"
      >
        <button
          type="button"
          class="inline-flex items-center justify-center w-9 h-9 rounded-full bg-n-brand text-white shadow hover:brightness-110 disabled:opacity-50"
          :disabled="isUploadingAvatar"
          @click="avatarInputRef.click()"
        >
          <span class="i-lucide-camera text-base" />
        </button>
      </Tooltip>
    </div>
    <input
      ref="avatarInputRef"
      type="file"
      accept="image/jpeg,image/png,image/gif,image/webp"
      class="hidden"
      @change="onAvatarChange"
    >
    <BeclinicButton
      v-if="canManage && room.avatar_url"
      :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.REMOVE_AVATAR')"
      variant="link"
      color="ruby"
      size="xs"
      :disabled="isUploadingAvatar"
      @click="$emit('remove-avatar')"
    />

    <!-- Nome — clica no lápis pra editar inline -->
    <!-- Nome — edição inline: input ocupa a largura disponível, alinhado à
         esquerda, mesma fonte do título, sem padding/borda/fundo/outline — só
         o texto e o cursor. Ícones de ação sem padding (maiores). -->
    <div
      class="flex items-center w-full gap-1 mt-2"
      :class="isEditingName ? 'justify-start' : 'justify-center'"
    >
      <template v-if="isEditingName">
        <!-- `reset-base` opta o input FORA da regra global do Chatwoot
             (_base.scss: input[type]:not(.reset-base) { @apply field-base h-10 }),
             que senão impõe fundo/borda/altura de formulário e vence o CSS do
             componente por especificidade. Com reset-base, fica só texto. -->
        <input
          :value="editName"
          type="text"
          class="reset-base flex-1 min-w-0 p-0 text-left text-xl font-semibold bg-transparent border-0 text-n-slate-12 focus:outline-none focus:ring-0"
          :disabled="isSaving"
          autofocus
          @input="onNameInput"
          @keydown.enter.prevent="$emit('save-name')"
          @keydown.escape.prevent="$emit('cancel-edit-name')"
        >
        <Tooltip :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.SAVE_TOOLTIP')">
          <button
            type="button"
            class="inline-flex items-center justify-center p-0 shrink-0 text-n-brand hover:text-n-brand/80 disabled:opacity-40"
            :disabled="isSaving || !editName.trim()"
            @click="$emit('save-name')"
          >
            <span class="i-lucide-check text-xl" />
          </button>
        </Tooltip>
        <Tooltip :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.CANCEL_TOOLTIP')">
          <button
            type="button"
            class="inline-flex items-center justify-center p-0 shrink-0 text-n-slate-11 hover:text-n-slate-12"
            :disabled="isSaving"
            @click="$emit('cancel-edit-name')"
          >
            <span class="i-lucide-x text-xl" />
          </button>
        </Tooltip>
      </template>
      <template v-else>
        <h2 class="text-xl font-semibold truncate text-n-slate-12">
          {{ room.name || $t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.GROUP_FALLBACK_NAME') }}
        </h2>
        <Tooltip v-if="canManage" :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.EDIT_NAME_TOOLTIP')">
          <button
            type="button"
            class="inline-flex items-center justify-center p-0 shrink-0 text-n-slate-11 hover:text-n-slate-12"
            @click="$emit('start-edit-name')"
          >
            <span class="i-lucide-pencil text-lg" />
          </button>
        </Tooltip>
      </template>
    </div>

    <p class="text-xs text-n-slate-10">
      {{
        memberCount() === 1
          ? $t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.MEMBERS_COUNT_ONE', { count: memberCount() })
          : $t('INTERNAL_CHAT.GROUP_SETTINGS.HERO.MEMBERS_COUNT_OTHER', { count: memberCount() })
      }}
    </p>
  </section>
</template>
