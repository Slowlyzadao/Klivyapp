<script setup>
// FE-2 (auditoria 2026-05-18): extraído de GroupSettingsDrawer.vue (601 LOC).
// Seção de membros: contador + botões "Adicionar membro" / "Adicionar
// Beatriz (IA)" + dropdown de busca de candidatos + lista de membros com
// hover-actions (promover/rebaixar/remover).
//
// FE-6: `<Tooltip>` preservado em todos os hover-actions.
// FE-16/17 (auditoria 2026-05-19): strings PT-BR movidas para
// `INTERNAL_CHAT.GROUP_SETTINGS.*` via i18n. `useI18n()` é usado pra
// resolver labels de role/badge dinamicamente em helpers JS.
// State (search, showAddMember) vive no pai via v-model + boolean prop.
// `candidates` chega pronto do pai (já filtrado por search + memberIds).
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

const props = defineProps({
  room: { type: Object, required: true },
  canManage: { type: Boolean, default: false },
  currentUserId: { type: [Number, String], default: null },
  hasBea: { type: Boolean, default: false },
  showAddMember: { type: Boolean, default: false },
  search: { type: String, default: '' },
  candidates: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'update:search',
  'toggle-add-member',
  'add-bea',
  'add-member',
  'promote',
  'remove-member',
]);

const { t } = useI18n();

const onSearchInput = e => emit('update:search', e.target.value);

const memberCount = () => props.room.members?.length || 0;

const memberRole = m => {
  if (m.is_ai) return t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.ROLE_AI');
  if (m.role === 'owner') return t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.ROLE_OWNER');
  if (m.role === 'admin') return t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.ROLE_ADMIN');
  return t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.ROLE_MEMBER');
};
</script>

<template>
  <section class="border-b border-n-weak">
    <p class="px-5 pt-4 pb-2 text-xs font-medium text-n-slate-11">
      {{
        memberCount() === 1
          ? $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.COUNT_ONE', { count: memberCount() })
          : $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.COUNT_OTHER', { count: memberCount() })
      }}
    </p>

    <button
      v-if="canManage"
      type="button"
      class="flex items-center w-full gap-3 px-5 py-2.5 text-start hover:bg-n-alpha-1 transition"
      @click="$emit('toggle-add-member')"
    >
      <span class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-brand/10 text-n-brand">
        <span class="i-lucide-user-plus text-base" />
      </span>
      <span class="text-sm font-medium text-n-brand">{{ $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.ADD_MEMBER') }}</span>
    </button>

    <button
      v-if="canManage && !hasBea"
      type="button"
      class="flex items-center w-full gap-3 px-5 py-2.5 text-start hover:bg-n-alpha-1 transition"
      @click="$emit('add-bea')"
    >
      <span class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-brand/10 text-n-brand">
        <span class="i-lucide-sparkles text-base" />
      </span>
      <span class="text-sm font-medium text-n-brand">{{ $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.ADD_BEA') }}</span>
    </button>

    <!-- Search dropdown pra adicionar membro -->
    <div v-if="showAddMember && canManage" class="px-5 py-2">
      <input
        :value="search"
        type="text"
        :placeholder="$t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.SEARCH_PLACEHOLDER')"
        class="w-full px-3 py-2 text-sm rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
        @input="onSearchInput"
      >
      <ul class="mt-2 max-h-[200px] overflow-y-auto ic-thread-scroll">
        <li v-if="candidates.length === 0" class="px-3 py-3 text-xs text-center text-n-slate-11">
          {{ $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.NO_CANDIDATES') }}
        </li>
        <li v-for="agent in candidates" :key="agent.id">
          <button
            type="button"
            class="flex items-center w-full gap-2 px-3 py-2 text-start rounded-md hover:bg-n-alpha-1"
            @click="$emit('add-member', agent.id)"
          >
            <!-- Chatwoot agent serializer expõe avatar como `thumbnail`,
                 não `avatar_url`. Fallback pra avatar_url se o backend
                 mudar no futuro. -->
            <Avatar :name="agent.name" :src="agent.thumbnail || agent.avatar_url || ''" :size="28" rounded-full />
            <span class="text-sm truncate text-n-slate-12">{{ agent.name }}</span>
          </button>
        </li>
      </ul>
    </div>

    <!-- Lista de membros -->
    <ul class="pb-2">
      <li
        v-for="m in room.members"
        :key="m.id"
        class="flex items-center gap-3 px-5 py-2 hover:bg-n-alpha-1 group transition"
      >
        <Avatar
          :name="m.name || $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.USER_FALLBACK_NAME')"
          :src="m.avatar_url || ''"
          :size="40"
          :icon-name="m.is_ai ? 'i-lucide-sparkles' : null"
          rounded-full
        />
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium truncate text-n-slate-12 flex items-center gap-1.5">
            <span class="truncate">{{ m.name }}</span>
            <span v-if="m.user_id === currentUserId" class="text-xs font-normal text-n-slate-10">{{ $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.YOU_LABEL') }}</span>
            <span
              v-if="m.is_ai"
              class="text-[9px] font-bold uppercase tracking-wide px-1 rounded bg-n-brand text-white shrink-0"
            >
              {{ $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.AI_BADGE') }}
            </span>
          </p>
          <p class="text-xs text-n-slate-10 truncate">{{ memberRole(m) }}</p>
        </div>
        <span
          v-if="!m.is_ai && (m.role === 'owner' || m.role === 'admin')"
          class="text-[10px] font-semibold uppercase tracking-wide px-2 py-0.5 rounded text-n-brand bg-n-brand/10 shrink-0"
        >
          {{ m.role === 'owner' ? $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.BADGE_OWNER') : $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.BADGE_ADMIN') }}
        </span>
        <!-- Hover actions de gestão -->
        <div
          v-if="canManage && m.user_id !== currentUserId && m.role !== 'owner'"
          class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition shrink-0"
        >
          <Tooltip v-if="!m.is_ai && m.role === 'member'" :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.PROMOTE_TOOLTIP')">
            <button
              type="button"
              class="inline-flex items-center justify-center p-0 shrink-0 text-n-slate-11 hover:text-n-slate-12"
              @click="$emit('promote', m.id, 'admin')"
            >
              <span class="i-lucide-shield text-lg" />
            </button>
          </Tooltip>
          <Tooltip v-else-if="!m.is_ai && m.role === 'admin'" :label="$t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.DEMOTE_TOOLTIP')">
            <button
              type="button"
              class="inline-flex items-center justify-center p-0 shrink-0 text-n-slate-11 hover:text-n-slate-12"
              @click="$emit('promote', m.id, 'member')"
            >
              <span class="i-lucide-shield-off text-lg" />
            </button>
          </Tooltip>
          <Tooltip
            :label="m.is_ai ? $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.REMOVE_BEA_TOOLTIP') : $t('INTERNAL_CHAT.GROUP_SETTINGS.MEMBERS.REMOVE_TOOLTIP')"
          >
            <button
              type="button"
              class="inline-flex items-center justify-center p-0 shrink-0 text-n-ruby-9 hover:text-n-ruby-10"
              @click="$emit('remove-member', m.id)"
            >
              <span class="i-lucide-x text-lg" />
            </button>
          </Tooltip>
        </div>
      </li>
    </ul>
  </section>
</template>
