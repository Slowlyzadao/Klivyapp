<script setup>
/**
 * UserPickerSelect — select padrão pra escolher um User com avatar + badge
 * inline (trigger e dropdown). Wrapper fino sobre `FormSelect` usando os
 * slots `selected` e `option`.
 *
 * Existe pra centralizar o pattern de "picker de pessoa com avatar" — antes
 * cada tela que precisava (templates de notificação, agenda, financeiro,
 * permissões) montava o select próprio ou usava `<FormSelect>` cru sem
 * avatar. Visual era inconsistente.
 *
 * Props:
 *   modelValue: id do user selecionado (number | string | null)
 *   users:      array de objetos com pelo menos { id, name }. Opcionais:
 *               - avatar_url: string (URL pra <img>). Avatar gera iniciais
 *                 quando ausente
 *               - badge: string (texto pequeno após o nome — ex.: "(você)",
 *                 "Admin", "Bea")
 *               - role: string (mostrado como `hint` à direita — ex.: "Recepção")
 *   placeholder: string
 *   searchable, auto-searchable, clearable, disabled, max-height: passthrough
 *     pro FormSelect
 *
 * Eventos:
 *   update:modelValue, change — propagados do FormSelect
 *
 * Uso:
 *   <UserPickerSelect
 *     v-model="form.assigned_user_id"
 *     :users="account.users"
 *     placeholder="Atribuir a…"
 *     auto-searchable
 *   />
 */
import { computed } from 'vue';
import FormSelect from './FormSelect.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  modelValue: { type: [String, Number], default: null },
  users: { type: Array, default: () => [] },
  placeholder: { type: String, default: 'Selecione uma pessoa…' },
  searchable: { type: Boolean, default: false },
  autoSearchable: { type: Boolean, default: true },
  clearable: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
  maxHeight: { type: Number, default: 280 },
  // Tamanho do avatar tanto no trigger quanto na lista.
  avatarSize: { type: Number, default: 24 },
});

const emit = defineEmits(['update:modelValue', 'change', 'search-change']);

const options = computed(() =>
  (props.users || []).map(u => ({
    value: u.id,
    label: u.name,
    badge: u.badge || null,
    hint: u.role || null,
    avatar_url: u.avatar_url || null,
    name: u.name,
  }))
);

const onUpdate = val => emit('update:modelValue', val);
const onChange = val => emit('change', val);
const onSearchChange = val => emit('search-change', val);
</script>

<template>
  <FormSelect
    :model-value="modelValue"
    :options="options"
    :placeholder="placeholder"
    :searchable="searchable"
    :auto-searchable="autoSearchable"
    :clearable="clearable"
    :disabled="disabled"
    :max-height="maxHeight"
    @update:model-value="onUpdate"
    @change="onChange"
    @search-change="onSearchChange"
  >
    <!-- IMPORTANTE: o FormSelect SEMPRE chama este slot, mesmo quando
         nada está selecionado (`option = null`). Sem o slot custom o
         FormSelect mostra o placeholder no `v-else` interno — quando
         sobrescrevemos o slot, precisamos cuidar do placeholder também.

         O badge de role usa as MESMAS classes que `Settings → Agentes`
         (Index.vue:243): `bg-woot-500/10 text-woot-500` pra consistência
         visual entre as duas telas. -->
    <template #selected="{ option }">
      <span v-if="option" class="up-row">
        <Avatar
          :name="option.name || option.label || ''"
          :src="option.avatar_url"
          :size="avatarSize"
          rounded-full
        />
        <span class="up-name">{{ option.label }}</span>
        <span v-if="option.badge" class="up-badge">{{ option.badge }}</span>
        <span
          v-if="option.hint"
          class="px-2 py-0.5 rounded-md bg-woot-500/10 text-[11px] font-medium text-woot-500 shrink-0"
        >
          {{ option.hint }}
        </span>
      </span>
      <span v-else class="up-placeholder">{{ placeholder }}</span>
    </template>

    <template #option="{ option }">
      <span v-if="option" class="up-row">
        <Avatar
          :name="option.name || option.label || ''"
          :src="option.avatar_url"
          :size="avatarSize"
          rounded-full
        />
        <span class="up-name">{{ option.label }}</span>
        <span v-if="option.badge" class="up-badge">{{ option.badge }}</span>
        <span
          v-if="option.hint"
          class="px-2 py-0.5 rounded-md bg-woot-500/10 text-[11px] font-medium text-woot-500 shrink-0"
        >
          {{ option.hint }}
        </span>
      </span>
    </template>
  </FormSelect>
</template>

<style scoped>
.up-row {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  flex: 1;
}
.up-name {
  flex: 1;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 13px;
  color: var(--color-n-slate-12, currentColor);
}
.up-badge {
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  padding: 1px 6px;
  font-size: 10px;
  font-weight: 500;
  border-radius: 4px;
  background: rgba(15, 23, 42, 0.06);
  color: rgba(71, 85, 105, 1);
  line-height: 1.4;
}
.up-placeholder {
  font-size: 13px;
  color: rgba(148, 163, 184, 1);
}
</style>
