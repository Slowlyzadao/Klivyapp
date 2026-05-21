<script setup>
defineProps({
  label: { type: String, required: true },
  active: { type: Boolean, default: false },
});
defineEmits(['click']);
</script>

<template>
  <span
    class="sidebar-all-pill"
    :class="{ 'is-active': active }"
    @click.stop="$emit('click')"
  >
    {{ label }}
  </span>
</template>

<style scoped>
.sidebar-all-pill {
  font-size: 10px;
  font-weight: 600;
  text-transform: none;
  letter-spacing: 0;
  padding: 1px 6px;
  border-radius: 8px;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
  border: 1px solid rgb(var(--slate-5));
  cursor: pointer;
  transition: background 0.12s, color 0.12s, border-color 0.12s;
}

.sidebar-all-pill:hover {
  background: rgb(var(--slate-4));
}

.sidebar-all-pill.is-active {
  background: rgb(var(--blue-9));
  color: #fff;
  border-color: rgb(var(--blue-9));
}
</style>
