<template>
  <component :is="tag" class="pp-list-item" :class="{ 'pp-list-item--interactive': interactive }" @click="$emit('click', $event)">
    <div v-if="$slots.leading" class="pp-list-item__leading"><slot name="leading" /></div>
    <div class="pp-list-item__body">
      <div class="pp-list-item__title">{{ title }}<slot name="title-suffix" /></div>
      <div v-if="subtitle || $slots.subtitle" class="pp-list-item__subtitle">
        <slot name="subtitle">{{ subtitle }}</slot>
      </div>
    </div>
    <div v-if="$slots.trailing" class="pp-list-item__trailing"><slot name="trailing" /></div>
  </component>
</template>

<script setup>
defineProps({
  title:       String,
  subtitle:    String,
  tag:         { type: String, default: 'div' },
  interactive: { type: Boolean, default: false }
});
defineEmits(['click']);
</script>

<style scoped>
.pp-list-item {
  display: flex; align-items: center; gap: 12px;
  padding: 12px 16px; background: #fff;
  border-bottom: 1px solid var(--pp-color-border);
  text-align: left; width: 100%;
}
.pp-list-item:last-child { border-bottom: none; }
.pp-list-item--interactive {
  cursor: pointer; transition: background 80ms ease, transform 80ms ease;
  border: none; font: inherit; color: inherit;
}
.pp-list-item--interactive:hover  { background: #f8fafc; }
.pp-list-item--interactive:active { transform: scale(0.995); }

.pp-list-item__leading { flex-shrink: 0; display: flex; align-items: center; justify-content: center; }
.pp-list-item__body    { flex: 1; min-width: 0; }
.pp-list-item__title   { font-size: 15px; font-weight: 600; color: var(--pp-color-text); }
.pp-list-item__subtitle { font-size: 13px; color: var(--pp-color-text-muted); margin-top: 2px; }
.pp-list-item__trailing { flex-shrink: 0; color: var(--pp-color-text-muted); }
</style>
