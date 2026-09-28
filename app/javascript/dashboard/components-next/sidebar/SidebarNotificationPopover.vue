<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { getUnixTime } from 'date-fns';
import camelcaseKeys from 'camelcase-keys';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import NotificationsAPI from 'dashboard/api/notifications';
import wootConstants from 'dashboard/constants/globals';
import { findSnoozeTime } from 'dashboard/helper/snoozeHelpers';

import Popover from 'dashboard/components-next/popover/Popover.vue';
import InboxCard from 'dashboard/components-next/Inbox/InboxCard.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CustomSnoozeModal from 'dashboard/components/CustomSnoozeModal.vue';

const props = defineProps({
  isCollapsed: { type: Boolean, default: false },
});

const HISTORY_DAYS = 7;
const PAGE_SIZE = 15;
const SNOOZE_PRESETS = [
  wootConstants.SNOOZE_OPTIONS.AN_HOUR_FROM_NOW,
  wootConstants.SNOOZE_OPTIONS.UNTIL_TOMORROW,
  wootConstants.SNOOZE_OPTIONS.UNTIL_NEXT_WEEK,
];

const { t } = useI18n();
const router = useRouter();
const store = useStore();

const popoverRef = ref(null);
const accountId = useMapGetter('getCurrentAccountId');
const unreadCountValue = useMapGetter('notifications/getUnreadCount');
const meta = useMapGetter('notifications/getMeta');
const liveRecords = useMapGetter('notifications/getNotifications');
const inboxById = useMapGetter('inboxes/getInboxById');

// Local list, independent from the full page store pagination/filters.
const items = ref([]);
const page = ref(1);
const isFetching = ref(false);
const hasMore = ref(false);
const snoozeMenuFor = ref(null);
const customSnoozeFor = ref(null);

const unreadCount = computed(() => {
  if (!unreadCountValue.value) return '';
  return unreadCountValue.value < 100 ? `${unreadCountValue.value}` : '99+';
});

const historyCutoff = () =>
  Math.floor(Date.now() / 1000) - HISTORY_DAYS * 24 * 60 * 60;

const toItem = record => camelcaseKeys(record, { deep: true });

const sortedItems = computed(() =>
  [...items.value].sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0))
);
const unreadItems = computed(() => sortedItems.value.filter(i => !i.readAt));
const historyItems = computed(() => sortedItems.value.filter(i => i.readAt));

const stateInbox = inboxId => inboxById.value(inboxId);

const mergeRecords = records => {
  const cutoff = historyCutoff();
  const byId = new Map(items.value.map(i => [i.id, i]));
  records.forEach(record => {
    const item = toItem(record);
    if ((item.createdAt || 0) < cutoff) return;
    byId.set(item.id, { ...(byId.get(item.id) || {}), ...item });
  });
  items.value = Array.from(byId.values());
};

const fetchPage = async () => {
  if (isFetching.value) return;
  isFetching.value = true;
  try {
    const { data } = await NotificationsAPI.get({
      page: page.value,
      status: wootConstants.INBOX_DISPLAY_BY.SNOOZED,
      type: wootConstants.INBOX_DISPLAY_BY.READ,
      sortOrder: wootConstants.INBOX_SORT_BY.NEWEST,
    });
    const payload = data?.data?.payload || [];
    mergeRecords(payload);
    const cutoff = historyCutoff();
    const oldest = payload[payload.length - 1];
    hasMore.value =
      payload.length >= PAGE_SIZE && (oldest?.created_at || 0) >= cutoff;
  } catch {
    hasMore.value = false;
  } finally {
    isFetching.value = false;
  }
};

const reload = () => {
  items.value = [];
  page.value = 1;
  snoozeMenuFor.value = null;
  fetchPage();
};

const loadMore = () => {
  page.value += 1;
  fetchPage();
};

// Keep the popover in sync with live ActionCable events while it is open.
watch(liveRecords, records => {
  if (!items.value.length && !records.length) return;
  mergeRecords(records);
});

const patchItem = (id, patch) => {
  items.value = items.value.map(item =>
    item.id === id ? { ...item, ...patch } : item
  );
};

const removeItem = id => {
  items.value = items.value.filter(item => item.id !== id);
};

const markAsRead = async item => {
  try {
    await store.dispatch('notifications/read', {
      id: item.id,
      primaryActorId: item.primaryActorId,
      primaryActorType: item.primaryActorType,
      unreadCount: meta.value.unreadCount,
    });
    items.value = items.value.map(i =>
      i.primaryActorId === item.primaryActorId && !i.readAt
        ? { ...i, readAt: getUnixTime(new Date()) }
        : i
    );
    useAlert(t('INBOX.ALERTS.MARK_AS_READ'));
    store.dispatch('notifications/unReadCount');
  } catch {
    // error
  }
};

const markAsUnread = async item => {
  try {
    await store.dispatch('notifications/unread', { id: item.id });
    patchItem(item.id, { readAt: null });
    useAlert(t('INBOX.ALERTS.MARK_AS_UNREAD'));
    store.dispatch('notifications/unReadCount');
  } catch {
    // error
  }
};

const deleteItem = async item => {
  try {
    await store.dispatch('notifications/delete', {
      notification: item,
      unread_count: meta.value.unreadCount,
      count: meta.value.count,
    });
    removeItem(item.id);
    useAlert(t('INBOX.ALERTS.DELETE'));
  } catch {
    // error
  }
};

const markAllRead = async () => {
  try {
    await store.dispatch('notifications/readAll');
    const now = getUnixTime(new Date());
    items.value = items.value.map(i => (i.readAt ? i : { ...i, readAt: now }));
    useAlert(t('INBOX.ALERTS.MARK_ALL_READ'));
  } catch {
    // error
  }
};

const snooze = async (item, snoozedUntil) => {
  snoozeMenuFor.value = null;
  try {
    await store.dispatch('notifications/snooze', {
      id: item.id,
      snoozedUntil,
    });
    patchItem(item.id, { snoozedUntil });
    useAlert(t('INBOX.ALERTS.SNOOZE'));
  } catch {
    // error
  }
};

const snoozePreset = (item, option) => {
  const snoozedUntil = findSnoozeTime(option) || null;
  snooze(item, snoozedUntil);
};

const openCustomSnooze = item => {
  snoozeMenuFor.value = null;
  customSnoozeFor.value = item;
};

const closeCustomSnooze = () => {
  customSnoozeFor.value = null;
};

const scheduleCustomSnooze = customSnoozeTime => {
  const item = customSnoozeFor.value;
  customSnoozeFor.value = null;
  if (!item || !customSnoozeTime) return;
  snooze(item, getUnixTime(customSnoozeTime) || null);
};

const toggleSnoozeMenu = (event, item) => {
  event.stopPropagation();
  snoozeMenuFor.value = snoozeMenuFor.value === item.id ? null : item.id;
};

const openConversation = async (item, hide) => {
  const { inboxId, id: conversationId } = item.primaryActor || {};
  if (!item.readAt) {
    await markAsRead(item);
  }
  hide();
  if (!conversationId) return;
  router.push({
    name: 'inbox_view_conversation',
    params: {
      accountId: accountId.value,
      inboxId,
      type: 'conversation',
      id: conversationId,
    },
  });
};

const viewAll = hide => {
  hide();
  router.push({ name: 'inbox_view', params: { accountId: accountId.value } });
};

defineExpose({ reload, items });
</script>

<template>
  <Popover
    ref="popoverRef"
    align="start"
    :show-content-border="false"
    @show="reload"
  >
    <template #default="{ isOpen }">
      <button
        class="relative grid rounded-lg size-8 hover:bg-n-alpha-1 flex-shrink-0 place-content-center"
        :class="{
          'outline outline-1 outline-n-weak bg-n-button-color':
            props.isCollapsed,
          'bg-n-alpha-2': isOpen,
        }"
        :title="t('SIDEBAR.NOTIFICATIONS')"
        :aria-label="t('SIDEBAR.NOTIFICATIONS')"
        :aria-expanded="isOpen"
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

    <template #content="{ hide }">
      <div
        class="flex flex-col w-[380px] max-w-[calc(100vw-2rem)] max-h-[70vh] bg-n-solid-1 rounded-xl"
        data-testid="notification-popover"
      >
        <header
          class="flex items-center justify-between gap-2 px-4 py-3 border-b border-n-weak"
        >
          <h3 class="mb-0 text-sm font-semibold text-n-slate-12">
            {{ t('INBOX.POPOVER.TITLE') }}
          </h3>
          <div class="flex items-center gap-3">
            <button
              class="text-xs font-medium text-n-slate-11 hover:text-n-slate-12 disabled:opacity-50"
              :disabled="!unreadCountValue"
              data-testid="mark-all-read"
              @click="markAllRead"
            >
              {{ t('INBOX.POPOVER.MARK_ALL_READ') }}
            </button>
            <button
              class="text-xs font-medium text-n-blue-11 hover:underline"
              data-testid="view-all"
              @click="viewAll(hide)"
            >
              {{ t('INBOX.POPOVER.VIEW_ALL') }}
            </button>
          </div>
        </header>

        <div class="flex-1 min-h-0 overflow-y-auto">
          <section>
            <h4
              class="px-4 pt-3 pb-1 mb-0 text-[11px] font-semibold tracking-wide uppercase text-n-ruby-11 bg-n-ruby-2/60"
            >
              {{ t('INBOX.POPOVER.UNREAD') }}
            </h4>
            <p
              v-if="!unreadItems.length && !isFetching"
              class="px-4 py-3 mb-0 text-sm text-n-slate-10"
            >
              {{ t('INBOX.POPOVER.EMPTY_UNREAD') }}
            </p>
            <div
              v-for="item in unreadItems"
              :key="item.id"
              class="relative border-b border-n-weak"
            >
              <InboxCard
                :inbox-item="item"
                :state-inbox="stateInbox(item.primaryActor?.inboxId)"
                class="hover:bg-n-alpha-1"
                @mark-notification-as-read="markAsRead"
                @mark-notification-as-un-read="markAsUnread"
                @delete-notification="deleteItem"
                @click="openConversation(item, hide)"
              />
              <button
                class="absolute grid rounded-md top-2 ltr:right-2 rtl:left-2 size-6 place-content-center hover:bg-n-alpha-2 text-n-slate-11"
                :title="t('INBOX.POPOVER.SNOOZE')"
                data-testid="snooze-trigger"
                @click="toggleSnoozeMenu($event, item)"
              >
                <Icon icon="i-lucide-alarm-clock-plus" class="size-4" />
              </button>
              <ul
                v-if="snoozeMenuFor === item.id"
                class="absolute z-10 grid gap-1 p-1 text-sm list-none shadow-lg top-8 ltr:right-2 rtl:left-2 min-w-48 rounded-lg bg-n-solid-1 border border-n-weak"
              >
                <li v-for="option in SNOOZE_PRESETS" :key="option">
                  <button
                    class="w-full px-2 py-1 text-left rounded-md hover:bg-n-alpha-2 text-n-slate-12"
                    @click.stop="snoozePreset(item, option)"
                  >
                    {{ t(`COMMAND_BAR.COMMANDS.${option.toUpperCase()}`) }}
                  </button>
                </li>
                <li>
                  <button
                    class="w-full px-2 py-1 text-left rounded-md hover:bg-n-alpha-2 text-n-slate-12"
                    @click.stop="openCustomSnooze(item)"
                  >
                    {{ t('COMMAND_BAR.COMMANDS.UNTIL_CUSTOM_TIME') }}
                  </button>
                </li>
              </ul>
            </div>
          </section>

          <section>
            <h4
              class="px-4 pt-3 pb-1 mb-0 text-[11px] font-semibold tracking-wide uppercase text-n-slate-11 bg-n-alpha-1"
            >
              {{ t('INBOX.POPOVER.HISTORY') }}
            </h4>
            <p
              v-if="!historyItems.length && !isFetching"
              class="px-4 py-3 mb-0 text-sm text-n-slate-10"
            >
              {{ t('INBOX.POPOVER.EMPTY_HISTORY') }}
            </p>
            <div
              v-for="item in historyItems"
              :key="item.id"
              class="border-b border-n-weak"
            >
              <InboxCard
                :inbox-item="item"
                :state-inbox="stateInbox(item.primaryActor?.inboxId)"
                class="hover:bg-n-alpha-1"
                @mark-notification-as-read="markAsRead"
                @mark-notification-as-un-read="markAsUnread"
                @delete-notification="deleteItem"
                @click="openConversation(item, hide)"
              />
            </div>
          </section>

          <div v-if="isFetching" class="flex justify-center py-3">
            <Spinner class="text-n-brand" />
          </div>
          <button
            v-else-if="hasMore"
            class="w-full py-2 text-xs font-medium text-n-blue-11 hover:bg-n-alpha-1"
            data-testid="load-more"
            @click="loadMore"
          >
            {{ t('INBOX.POPOVER.LOAD_MORE') }}
          </button>
        </div>
      </div>

      <Teleport to="body">
        <div v-if="customSnoozeFor" data-popover-content>
          <woot-modal
            :show="true"
            :on-close="closeCustomSnooze"
            @close="closeCustomSnooze"
          >
            <CustomSnoozeModal
              @close="closeCustomSnooze"
              @choose-time="scheduleCustomSnooze"
            />
          </woot-modal>
        </div>
      </Teleport>
    </template>
  </Popover>
</template>
