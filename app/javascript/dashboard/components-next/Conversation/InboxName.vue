<script setup>
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';

defineProps({
  inbox: {
    type: Object,
    default: () => {},
  },
});
</script>

<template>
  <div :title="inbox.name" class="flex items-center gap-1 min-w-0">
    <ChannelIcon :inbox="inbox" class="size-4 flex-shrink-0 text-n-slate-11" />
    <span class="truncate text-body-main text-n-slate-11">
      {{ inbox.name }}
    </span>
    <span
      v-if="inbox.active === false"
      class="shrink-0 rounded-md bg-n-ruby-3 px-1 py-0.5 text-xs font-medium text-n-ruby-11"
    >
      {{ $t('INBOX_MGMT.DISABLED') }}
    </span>
  </div>
</template>
