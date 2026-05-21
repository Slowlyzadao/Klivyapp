<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AssignRoleModal from './AssignRoleModal.vue';

defineProps({
  user: { type: Object, required: true },
});

const emit = defineEmits(['assigned']);

const showModal = ref(false);

const open = () => {
  showModal.value = true;
};

const close = () => {
  showModal.value = false;
};

const handleAssigned = role => {
  emit('assigned', role);
  close();
};
</script>

<template>
  <span>
    <Button
      v-tooltip.top="`Atribuir função a ${user.name}`"
      icon="i-lucide-shield-plus"
      slate
      sm
      @click="open"
    />
    <woot-modal v-model:show="showModal" :on-close="close">
      <AssignRoleModal
        v-if="showModal"
        :user="user"
        @close="close"
        @assigned="handleAssigned"
      />
    </woot-modal>
  </span>
</template>
