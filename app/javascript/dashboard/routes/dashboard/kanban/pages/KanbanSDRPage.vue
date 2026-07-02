<script setup>
import { computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import KanbanInboxFilter from '../components/KanbanInboxFilter.vue';
import KanbanBoard from '../components/KanbanBoard.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');
const selectedInboxIds = useMapGetter('kanban/getSelectedInboxIds');
const uiFlags = useMapGetter('kanban/getUIFlags');

const hasSelection = computed(() => selectedInboxIds.value.length > 0);

const parseInboxIds = raw => {
  if (!raw) return [];
  const available = inboxes.value.map(inbox => inbox.id);
  return String(raw)
    .split(',')
    .map(Number)
    .filter(id => available.includes(id));
};

const applySelection = (ids, { updateQuery = true } = {}) => {
  store.dispatch('kanban/setSelectedInboxIds', ids);
  if (updateQuery) {
    router.replace({
      query: { ...route.query, inbox_ids: ids.join(',') || undefined },
    });
  }
  store.dispatch('kanban/fetchBoard');
};

const onSelectionUpdate = ids => applySelection(ids);

onMounted(async () => {
  if (!inboxes.value.length) {
    await store.dispatch('inboxes/get');
  }
  applySelection(parseInboxIds(route.query.inbox_ids), { updateQuery: false });
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center justify-between flex-shrink-0 gap-4 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('KANBAN.HEADER_TITLE') }}
      </h1>
      <KanbanInboxFilter
        :inboxes="inboxes"
        :selected-ids="selectedInboxIds"
        @update:selected-ids="onSelectionUpdate"
      />
    </header>

    <EmptyStateLayout
      v-if="!hasSelection"
      class="flex-1 min-h-0"
      :title="t('KANBAN.EMPTY_STATE.NO_INBOX_TITLE')"
      :subtitle="t('KANBAN.EMPTY_STATE.NO_INBOX_SUBTITLE')"
      :show-backdrop="false"
    />

    <div v-else-if="uiFlags.isFetching" class="flex items-center justify-center flex-1">
      <Spinner class="size-6" />
    </div>

    <KanbanBoard v-else class="flex-1 min-h-0" />
  </section>
</template>
