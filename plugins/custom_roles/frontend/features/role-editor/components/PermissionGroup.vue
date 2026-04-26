<script setup>
import { computed, ref } from 'vue';
import PermissionToggle from './PermissionToggle.vue';
import { countActiveInGroup } from '../../../shared/modules.js';

const props = defineProps({
  moduleKey: { type: String, required: true },
  group: { type: Object, required: true },
  permissions: { type: Object, required: true },
  defaultExpanded: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle-permission', 'toggle-group']);

const expanded = ref(props.defaultExpanded);

const totalCount = computed(() => props.group.permissions.length);
const activeCount = computed(() =>
  countActiveInGroup(props.permissions, props.moduleKey, props.group.key)
);
const allOn = computed(() => activeCount.value === totalCount.value);

const handleToggleAll = () => {
  emit('toggle-group', props.moduleKey, props.group.key, !allOn.value);
};
const handleHeaderClick = () => {
  expanded.value = !expanded.value;
};
</script>

<template>
  <div class="bg-n-slate-1">
    <div
      class="flex items-center justify-between px-4 py-2.5 bg-n-slate-1 border-b border-n-weak"
    >
      <button
        class="flex flex-1 items-center gap-2 text-left hover:text-woot-500 transition-colors"
        @click="handleHeaderClick"
      >
        <i
          v-if="group.icon"
          class="w-4 h-4 text-n-slate-11 flex-shrink-0"
          :class="group.icon"
        />
        <span class="text-sm font-medium text-n-slate-12">
          {{ group.label }}
        </span>
        <span class="text-xs text-n-slate-11">
          ({{ activeCount }}/{{ totalCount }})
        </span>
      </button>
      <div class="flex items-center gap-3">
        <button
          class="text-[11px] font-semibold px-2.5 py-1 rounded-[6px] border hover:bg-n-slate-3 transition-colors"
          :class="
            allOn
              ? 'text-woot-500 border-woot-500/30 bg-woot-500/10'
              : 'text-n-slate-9 border-n-slate-4'
          "
          @click="handleToggleAll"
        >
          {{ allOn ? 'Desmarcar todos' : 'Marcar todos' }}
        </button>
        <button @click="handleHeaderClick">
          <i
            class="w-4 h-4 text-n-slate-11 block transition-transform"
            :class="expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          />
        </button>
      </div>
    </div>

    <div v-show="expanded" class="divide-y divide-n-weak pl-6">
      <PermissionToggle
        v-for="perm in group.permissions"
        :key="perm.key"
        :label="perm.label"
        :model-value="permissions[moduleKey]?.[perm.key] === true"
        @update:model-value="emit('toggle-permission', moduleKey, perm.key)"
      />
    </div>
  </div>
</template>
