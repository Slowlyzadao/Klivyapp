<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import { usePermissions } from 'dashboard/composables/usePermissions';

const emit = defineEmits(['add', 'import', 'export']);

const { t } = useI18n();
const { isAdmin, can: klivyCan } = usePermissions();
const canCreateContact = computed(
  () => isAdmin.value || klivyCan('contacts', 'create')
);
const canImportExport = computed(
  () => isAdmin.value || klivyCan('contacts', 'import_export')
);

const contactMenuItems = computed(() =>
  [
    canCreateContact.value && {
      label: t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.ADD_CONTACT'),
      action: 'add',
      value: 'add',
      icon: 'i-lucide-plus',
    },
    canImportExport.value && {
      label: t(
        'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.EXPORT_CONTACT'
      ),
      action: 'export',
      value: 'export',
      icon: 'i-lucide-upload',
    },
    canImportExport.value && {
      label: t(
        'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.IMPORT_CONTACT'
      ),
      action: 'import',
      value: 'import',
      icon: 'i-lucide-download',
    },
  ].filter(Boolean)
);
const hasMenuItems = computed(() => contactMenuItems.value.length > 0);
const showActionsDropdown = ref(false);

const handleContactAction = ({ action }) => {
  if (action === 'add') {
    emit('add');
  } else if (action === 'import') {
    emit('import');
  } else if (action === 'export') {
    emit('export');
  }
};
</script>

<template>
  <div
    v-if="hasMenuItems"
    v-on-clickaway="() => (showActionsDropdown = false)"
    class="relative"
  >
    <Button
      icon="i-lucide-ellipsis-vertical"
      color="slate"
      variant="ghost"
      size="sm"
      :class="showActionsDropdown ? 'bg-n-alpha-2' : ''"
      @click="showActionsDropdown = !showActionsDropdown"
    />
    <DropdownMenu
      v-if="showActionsDropdown"
      :menu-items="contactMenuItems"
      class="ltr:right-0 rtl:left-0 mt-1 w-52 top-full"
      @action="handleContactAction($event)"
    />
  </div>
</template>
