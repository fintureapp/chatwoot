<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  isCollapsed: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const unreadCountValue = useMapGetter('notifications/getUnreadCount');

const unreadCount = computed(() => {
  if (!unreadCountValue.value) {
    return '';
  }

  return unreadCountValue.value < 100 ? `${unreadCountValue.value}` : '99+';
});

function openNotifications() {
  if (route.name === 'inbox_view') {
    return;
  }

  router.push({ name: 'inbox_view', params: { accountId: accountId.value } });
}
</script>

<template>
  <button
    class="relative grid rounded-lg size-8 hover:bg-n-alpha-1 flex-shrink-0 place-content-center"
    :class="{
      'outline outline-1 outline-n-weak bg-n-button-color': props.isCollapsed,
    }"
    :title="t('SIDEBAR.NOTIFICATIONS')"
    :aria-label="t('SIDEBAR.NOTIFICATIONS')"
    @click="openNotifications"
  >
    <span class="i-lucide-bell size-4 text-n-slate-11" />
    <span
      v-if="unreadCount"
      class="min-h-2 min-w-2 p-0.5 px-1 bg-n-ruby-9 rounded-lg absolute -top-1 -right-1.5 grid place-items-center text-[9px] leading-none text-n-ruby-3"
    >
      {{ unreadCount }}
    </span>
  </button>
</template>
