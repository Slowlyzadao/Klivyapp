<script setup>
import { computed } from 'vue';
import PermissionToggle from './PermissionToggle.vue';
import PermissionGroup from './PermissionGroup.vue';
import {
  countActiveInModule,
  isModuleDisabled,
  flattenPermissions,
  moduleHasGroups,
} from '../../../shared/modules.js';

const props = defineProps({
  module: { type: Object, required: true },
  permissions: { type: Object, required: true },
  expanded: { type: Boolean, default: false },
});

const emit = defineEmits([
  'toggle-expanded',
  'toggle-permission',
  'toggle-module',
  'toggle-group',
]);

const totalCount = computed(() => flattenPermissions(props.module).length);
const activeCount = computed(() =>
  countActiveInModule(props.permissions, props.module.key)
);
const moduleOff = computed(() =>
  isModuleDisabled(props.permissions, props.module.key)
);
const allOn = computed(() => activeCount.value === totalCount.value);
const hasGroups = computed(() => moduleHasGroups(props.module));

const handleToggleAll = () => {
  emit('toggle-module', props.module.key, !allOn.value);
};
const handleHeaderClick = () => emit('toggle-expanded', props.module.key);
</script>

<template>
  <div
    class="border border-n-weak rounded-xl overflow-hidden"
    :class="{ 'opacity-70 border-dashed': moduleOff }"
  >
    <div
      class="flex items-center justify-between px-4 py-3 bg-n-slate-2 border-b border-n-weak transition-colors"
    >
      <button
        class="flex flex-1 items-center gap-2 text-left hover:text-woot-500 transition-colors"
        @click="handleHeaderClick"
      >
        <i class="w-4 h-4 text-n-slate-11" :class="module.icon" />
        <span class="text-sm font-semibold text-n-slate-12">
          {{ module.label }}
        </span>
        <span class="text-xs text-n-slate-11">
          ({{ activeCount }}/{{ totalCount }})
        </span>
        <span
          v-if="moduleOff"
          class="ml-2 text-[10px] font-medium tracking-wider uppercase px-1.5 py-0.5 rounded-md bg-n-slate-3 text-n-slate-11"
        >
          Oculto no menu
        </span>
      </button>
      <div class="flex items-center gap-4">
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
            :class="
              expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'
            "
          />
        </button>
      </div>
    </div>

    <div v-show="expanded">
      <template v-if="hasGroups">
        <PermissionGroup
          v-for="group in module.groups"
          :key="group.key"
          :module-key="module.key"
          :group="group"
          :permissions="permissions"
          @toggle-permission="
            (...args) => emit('toggle-permission', ...args)
          "
          @toggle-group="(...args) => emit('toggle-group', ...args)"
        />
      </template>
      <div v-else class="divide-y divide-n-weak">
        <PermissionToggle
          v-for="perm in module.permissions"
          :key="perm.key"
          :label="perm.label"
          :model-value="permissions[module.key]?.[perm.key] === true"
          @update:model-value="emit('toggle-permission', module.key, perm.key)"
        />
      </div>
    </div>
  </div>
</template>
