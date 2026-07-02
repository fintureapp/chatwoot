<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import { getInboxIconByType } from 'dashboard/helper/inbox';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  inboxes: {
    type: Array,
    default: () => [],
  },
  selectedIds: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['update:selectedIds']);

const { t } = useI18n();

const isOpen = ref(false);

const allSelected = computed(
  () =>
    props.inboxes.length > 0 &&
    props.selectedIds.length === props.inboxes.length
);

const triggerLabel = computed(() => {
  if (!props.selectedIds.length) {
    return t('KANBAN.INBOX_FILTER.PLACEHOLDER');
  }
  if (allSelected.value) {
    return t('KANBAN.INBOX_FILTER.ALL');
  }
  return t('KANBAN.INBOX_FILTER.SELECTED', { count: props.selectedIds.length });
});

const isSelected = id => props.selectedIds.includes(id);

const toggleInbox = id => {
  const next = isSelected(id)
    ? props.selectedIds.filter(item => item !== id)
    : [...props.selectedIds, id];
  emit('update:selectedIds', next);
};

const toggleAll = () => {
  emit(
    'update:selectedIds',
    allSelected.value ? [] : props.inboxes.map(inbox => inbox.id)
  );
};

const iconFor = inbox => getInboxIconByType(inbox.channel_type, inbox.medium);
</script>

<template>
  <div v-on-click-outside="() => (isOpen = false)" class="relative">
    <Button
      color="slate"
      variant="outline"
      size="sm"
      icon="i-lucide-chevron-down"
      trailing-icon
      :label="triggerLabel"
      @click="isOpen = !isOpen"
    />
    <div
      v-if="isOpen"
      class="absolute z-40 flex flex-col gap-1 p-1 mt-1 border rounded-lg shadow-lg ltr:left-0 rtl:right-0 top-full w-72 bg-n-alpha-3 backdrop-blur-[100px] border-n-weak"
    >
      <button
        class="flex items-center gap-2 px-2.5 h-8 rounded-md text-sm text-n-slate-12 hover:bg-n-alpha-2"
        @click="toggleAll"
      >
        <Icon
          :icon="allSelected ? 'i-lucide-check-square' : 'i-lucide-square'"
          class="size-4 text-n-slate-11"
        />
        <span>{{ t('KANBAN.INBOX_FILTER.ALL') }}</span>
      </button>
      <div class="h-px my-1 bg-n-weak" />
      <div class="flex flex-col gap-1 overflow-y-auto max-h-64">
        <button
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="flex items-center gap-2 px-2.5 h-8 rounded-md text-sm text-n-slate-12 hover:bg-n-alpha-2"
          @click="toggleInbox(inbox.id)"
        >
          <span class="flex items-center justify-center size-4 shrink-0">
            <Icon
              v-if="isSelected(inbox.id)"
              icon="i-lucide-check"
              class="size-4 text-n-brand"
            />
          </span>
          <Icon :icon="iconFor(inbox)" class="size-4 shrink-0 text-n-slate-11" />
          <span class="truncate">{{ inbox.name }}</span>
        </button>
      </div>
    </div>
  </div>
</template>
