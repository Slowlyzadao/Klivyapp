<script setup>
/**
 * Toggle — switch on/off reutilizável.
 *
 * Refeito 2026-05-23 seguindo o padrão Tailwind do Switch nativo do Chatwoot
 * (`app/javascript/dashboard/components-next/switch/Switch.vue`). Mantém a API
 * estendida (label/hint/disabled/size) que o Toggle do beclinic_core trouxe.
 *
 * IMPORTANTE — cores:
 *   Cor ON = `n-brand` (azul Klivy canon — #2781F6). Decisão registrada em
 *   memory "Cor canônica do financeiro V2 é AZUL Klivy". O Tailwind do projeto
 *   substitui o palette padrão (override em tailwind.config.js#colors), então
 *   `emerald`/`green` não existem como `bg-*`. Para outras cores semânticas,
 *   passe via prop `color` que mapeamos só pras que EXISTEM no theme: brand
 *   (default), teal, ruby, amber. Classes inline (não via computed) pra
 *   garantir scan do Tailwind JIT.
 *
 * Uso:
 *   <Toggle v-model="ativo" />
 *   <Toggle v-model="status" label="Ativo" hint="Aparece nos selects" />
 *   <Toggle v-model="ativo" :disabled="loading" size="sm" />
 *   <Toggle v-model="ativo" color="teal" />
 *
 * Props:
 *   modelValue : boolean — estado atual
 *   label      : string  — texto à esquerda do switch (opcional)
 *   hint       : string  — texto pequeno embaixo do label (opcional)
 *   disabled   : boolean — bloqueia interação
 *   size       : 'sm' | 'md' (default md)
 *   color      : 'brand' | 'blue' | 'teal' | 'ruby' | 'amber' (default brand)
 *
 * Eventos:
 *   update:modelValue : disparado ao alternar (v-model padrão)
 */
const props = defineProps({
  modelValue: { type: Boolean, default: false },
  label: { type: String, default: '' },
  hint: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  size: { type: String, default: 'md', validator: v => ['sm', 'md'].includes(v) },
  color: {
    type: String,
    default: 'brand',
    // Aceita 'blue' e 'emerald' como aliases legados (mapeados pra brand/teal).
    validator: v => ['brand', 'blue', 'emerald', 'teal', 'ruby', 'amber'].includes(v),
  },
});

const emit = defineEmits(['update:modelValue']);

function toggle() {
  if (props.disabled) return;
  emit('update:modelValue', !props.modelValue);
}
</script>

<template>
  <!--
    SAFELIST (não remover) — strings literais pro Tailwind JIT detectar
    todas as variantes de cor ON em scan estático. Não renderiza visualmente
    porque hidden, mas garante que as classes sobrevivem ao build.
    bg-n-brand bg-n-teal-9 bg-n-ruby-9 bg-n-amber-9 bg-n-slate-6
  -->
  <label
    class="bc-toggle inline-flex items-center gap-3 select-none"
    :class="{ 'opacity-55 cursor-not-allowed': disabled, 'cursor-pointer': !disabled }"
  >
    <span v-if="label || hint" class="bc-toggle__info inline-flex flex-col gap-0.5 min-w-0">
      <span v-if="label" class="bc-toggle__label text-[13px] font-medium text-n-slate-12 leading-tight">{{ label }}</span>
      <span v-if="hint" class="bc-toggle__hint text-[11px] text-n-slate-9 leading-tight">{{ hint }}</span>
    </span>

    <!-- size=sm (h-4 w-7) — igual ao Switch nativo Chatwoot -->
    <button
      v-if="size === 'sm'"
      type="button"
      class="group relative h-4 w-7 rounded-full flex-shrink-0 select-none focus:outline-none focus:ring-1 focus:ring-n-brand focus:ring-offset-n-slate-2 focus:ring-offset-2 transition-colors duration-200 ease-in-out"
      :class="[
        modelValue
          ? (color === 'teal' ? 'bg-n-teal-9'
            : color === 'ruby' ? 'bg-n-ruby-9'
            : color === 'amber' ? 'bg-n-amber-9'
            : 'bg-n-brand')
          : 'bg-n-slate-6',
        { 'cursor-not-allowed': disabled }
      ]"
      role="switch"
      :aria-checked="modelValue"
      :disabled="disabled"
      @click.prevent="toggle"
    >
      <span class="sr-only">Alternar</span>
      <span
        class="absolute top-1/2 ltr:left-0.5 rtl:right-0.5 -translate-y-1/2 transition-transform duration-[350ms] ease-[cubic-bezier(0.34,1.56,0.64,1)]"
        :class="modelValue ? 'ltr:translate-x-3 rtl:-translate-x-3' : 'ltr:translate-x-0 rtl:translate-x-0'"
      >
        <span class="block h-3 w-3 rounded-full bg-n-background shadow-md transition-[width] duration-[180ms] ease-in-out" />
      </span>
    </button>

    <!-- size=md (h-5 w-9) — versão padrão pra formulários -->
    <button
      v-else
      type="button"
      class="group relative h-5 w-9 rounded-full flex-shrink-0 select-none focus:outline-none focus:ring-1 focus:ring-n-brand focus:ring-offset-n-slate-2 focus:ring-offset-2 transition-colors duration-200 ease-in-out"
      :class="[
        modelValue
          ? (color === 'teal' ? 'bg-n-teal-9'
            : color === 'ruby' ? 'bg-n-ruby-9'
            : color === 'amber' ? 'bg-n-amber-9'
            : 'bg-n-brand')
          : 'bg-n-slate-6',
        { 'cursor-not-allowed': disabled }
      ]"
      role="switch"
      :aria-checked="modelValue"
      :disabled="disabled"
      @click.prevent="toggle"
    >
      <span class="sr-only">Alternar</span>
      <span
        class="absolute top-1/2 ltr:left-0.5 rtl:right-0.5 -translate-y-1/2 transition-transform duration-[350ms] ease-[cubic-bezier(0.34,1.56,0.64,1)]"
        :class="modelValue ? 'ltr:translate-x-4 rtl:-translate-x-4' : 'ltr:translate-x-0 rtl:translate-x-0'"
      >
        <span class="block h-4 w-4 rounded-full bg-n-background shadow-md transition-[width] duration-[180ms] ease-in-out" />
      </span>
    </button>
  </label>
</template>
