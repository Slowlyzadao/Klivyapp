<script setup>
import AsIcon from '../../../shared/AsIcon.vue';

defineProps({
  featureKey: { type: String, required: true },
  label:      { type: String, required: true },
  icon:       { type: String, default: 'checkbox' },
  checked:    { type: Boolean, default: false },
});

defineEmits(['toggle']);
</script>

<template>
  <button
    type="button"
    class="reset-base plan-feature-item"
    :class="{ 'plan-feature-item--checked': checked }"
    @click="$emit('toggle', featureKey)"
  >
    <span class="plan-feature-item__icon">
      <AsIcon :name="icon" :size="16" />
    </span>
    <span class="plan-feature-item__label">{{ label }}</span>
    <span class="plan-feature-item__check">
      <AsIcon :name="checked ? 'check' : 'add'" :size="16" />
    </span>
  </button>
</template>
