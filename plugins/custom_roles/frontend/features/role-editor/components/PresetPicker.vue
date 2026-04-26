<script setup>
import { PRESETS } from '../../../shared/presets.js';
import { countActivePermissions } from '../../../shared/modules.js';

defineProps({
  selectedPresetId: { type: String, default: null },
});

const emit = defineEmits(['select']);

const totalFor = preset => countActivePermissions(preset.permissions);
</script>

<template>
  <div class="space-y-3">
    <p class="text-xs text-n-slate-11 uppercase tracking-wider font-medium">
      Selecione um perfil pronto para usar como ponto de partida. Você pode
      personalizar tudo depois.
    </p>
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
      <button
        v-for="preset in PRESETS"
        :key="preset.id"
        class="flex items-start gap-3 p-4 rounded-xl border text-left transition-all"
        :class="[
          selectedPresetId === preset.id
            ? preset.color + ' border-current'
            : 'border-n-weak hover:border-n-slate-7 bg-n-slate-2 hover:bg-n-slate-3',
        ]"
        @click="emit('select', preset.id)"
      >
        <i
          class="w-5 h-5 flex-shrink-0 mt-0.5"
          :class="[
            preset.icon,
            selectedPresetId === preset.id ? '' : 'text-n-slate-11',
          ]"
        />
        <div>
          <span class="flex items-center gap-2 text-sm font-semibold">
            {{ preset.label }}
            <span
              class="px-1.5 py-0.5 rounded-md bg-n-slate-3 text-[10px] font-medium text-n-slate-11"
            >
              {{ totalFor(preset) }} permissões
            </span>
          </span>
          <span class="text-xs text-n-slate-11 leading-relaxed mt-1 block">
            {{ preset.description }}
          </span>
        </div>
      </button>
    </div>
  </div>
</template>
