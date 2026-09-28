<script setup>
import SidebarNotificationPopover from './SidebarNotificationPopover.vue';

const props = defineProps({
  isCollapsed: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <SidebarNotificationPopover :is-collapsed="props.isCollapsed" />
</template>
