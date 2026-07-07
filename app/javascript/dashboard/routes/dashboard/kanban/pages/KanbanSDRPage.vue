<script setup>
import { computed, reactive, ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { resolveStage } from 'dashboard/routes/dashboard/kanban/config/stages';
import { downloadKanbanCsv } from 'dashboard/routes/dashboard/kanban/helper/csv';

import KanbanInboxFilter from '../components/KanbanInboxFilter.vue';
import KanbanToolbar from '../components/KanbanToolbar.vue';
import KanbanBoard from '../components/KanbanBoard.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');
const selectedInboxIds = useMapGetter('kanban/getSelectedInboxIds');
const uiFlags = useMapGetter('kanban/getUIFlags');
const records = useMapGetter('kanban/getRecords');

const hasSelection = computed(() => selectedInboxIds.value.length > 0);

const inboxNames = computed(() => {
  const map = {};
  inboxes.value.forEach(inbox => {
    map[inbox.id] = inbox.name;
  });
  return map;
});

// ---- Filtros / ordenação (client-side) ------------------------------------
const defaultFilters = () => ({
  query: '',
  product: '',
  stage: '',
  assigneeId: '',
  createdFrom: '',
  createdTo: '',
});
const filters = reactive(defaultFilters());
const sortBy = ref('last_activity_desc');

const hasActiveFilters = computed(() =>
  Object.values(filters).some(value => value !== '')
);

const products = computed(() =>
  [
    ...new Set(
      records.value
        .map(record => record.custom_attributes?.produto_interesse)
        .filter(Boolean)
    ),
  ].sort((a, b) => a.localeCompare(b))
);

const assignees = computed(() => {
  const map = new Map();
  records.value.forEach(record => {
    const assignee = record.meta?.assignee;
    if (assignee?.id) map.set(assignee.id, assignee.name);
  });
  return [...map.entries()]
    .map(([id, name]) => ({ id, name }))
    .sort((a, b) => (a.name || '').localeCompare(b.name || ''));
});

const toSeconds = (dateStr, endOfDay = false) => {
  if (!dateStr) return null;
  const date = new Date(`${dateStr}T${endOfDay ? '23:59:59' : '00:00:00'}`);
  return Math.floor(date.getTime() / 1000);
};

const matchesQuery = record => {
  if (!filters.query) return true;
  const needle = filters.query.toLowerCase();
  const sender = record.meta?.sender || {};
  const haystack = [
    sender.name,
    sender.phone_number,
    sender.email,
    record.custom_attributes?.produto_interesse,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
  return haystack.includes(needle);
};

const volumeOf = record => Number(record.custom_attributes?.valor_potencial) || 0;

const sorters = {
  last_activity_desc: (a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0),
  created_desc: (a, b) => (b.created_at || 0) - (a.created_at || 0),
  created_asc: (a, b) => (a.created_at || 0) - (b.created_at || 0),
  volume_desc: (a, b) => volumeOf(b) - volumeOf(a),
};

const filteredRecords = computed(() => {
  const createdFrom = toSeconds(filters.createdFrom);
  const createdTo = toSeconds(filters.createdTo, true);
  const result = records.value.filter(record => {
    if (!matchesQuery(record)) return false;
    if (filters.product && record.custom_attributes?.produto_interesse !== filters.product) {
      return false;
    }
    if (filters.stage && resolveStage(record) !== filters.stage) return false;
    if (
      filters.assigneeId &&
      String(record.meta?.assignee?.id) !== filters.assigneeId
    ) {
      return false;
    }
    if (createdFrom && (record.created_at || 0) < createdFrom) return false;
    if (createdTo && (record.created_at || 0) > createdTo) return false;
    return true;
  });
  return result.sort(sorters[sortBy.value] || sorters.last_activity_desc);
});

const clearFilters = () => {
  Object.assign(filters, defaultFilters());
};

// v-model manual: `filters` é reactive (não ref), então mesclamos o objeto emitido
// em vez de reatribuir. `sortBy` é ref e pode ser atribuído direto.
const onFiltersUpdate = value => Object.assign(filters, value);
const onSortUpdate = value => {
  sortBy.value = value;
};

// ---- Seleção de inbox / carregamento --------------------------------------
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
const retry = () => store.dispatch('kanban/fetchBoard');

// ---- CSV ------------------------------------------------------------------
const exportCsv = scope => {
  const data = scope === 'all' ? records.value : filteredRecords.value;
  downloadKanbanCsv(data);
};

const skeletonColumns = 5;
const skeletonCards = [1, 2, 3];

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
      <div class="flex items-center gap-2">
        <Button
          v-if="hasSelection && records.length"
          color="slate"
          variant="outline"
          size="sm"
          icon="i-lucide-download"
          :label="
            hasActiveFilters
              ? t('KANBAN.CSV.EXPORT_FILTERED')
              : t('KANBAN.CSV.EXPORT')
          "
          @click="exportCsv('filtered')"
        />
        <Button
          v-if="hasSelection && records.length && hasActiveFilters"
          color="slate"
          variant="ghost"
          size="sm"
          :label="t('KANBAN.CSV.EXPORT_ALL')"
          @click="exportCsv('all')"
        />
        <KanbanInboxFilter
          :inboxes="inboxes"
          :selected-ids="selectedInboxIds"
          @update:selected-ids="onSelectionUpdate"
        />
      </div>
    </header>

    <KanbanToolbar
      v-if="hasSelection && !uiFlags.isFetching && !uiFlags.hasError && records.length"
      :filters="filters"
      :sort-by="sortBy"
      :products="products"
      :assignees="assignees"
      :has-active-filters="hasActiveFilters"
      @update:filters="onFiltersUpdate"
      @update:sortBy="onSortUpdate"
      @clear="clearFilters"
    />

    <!-- Sem inbox selecionada -->
    <EmptyStateLayout
      v-if="!hasSelection"
      class="flex-1 min-h-0"
      :title="t('KANBAN.EMPTY_STATE.NO_INBOX_TITLE')"
      :subtitle="t('KANBAN.EMPTY_STATE.NO_INBOX_SUBTITLE')"
      :show-backdrop="false"
    />

    <!-- Carregando: skeleton do board -->
    <div
      v-else-if="uiFlags.isFetching"
      class="flex flex-1 gap-4 px-6 py-4 overflow-hidden min-h-0"
    >
      <div
        v-for="col in skeletonColumns"
        :key="col"
        class="flex flex-col w-72 shrink-0 gap-2 p-2 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div class="h-6 mb-1 rounded-md bg-n-alpha-2 animate-pulse" />
        <div
          v-for="card in skeletonCards"
          :key="card"
          class="h-20 rounded-xl bg-n-alpha-1 animate-pulse"
        />
      </div>
    </div>

    <!-- Erro ao carregar -->
    <EmptyStateLayout
      v-else-if="uiFlags.hasError"
      class="flex-1 min-h-0"
      :title="t('KANBAN.EMPTY_STATE.ERROR_TITLE')"
      :subtitle="t('KANBAN.EMPTY_STATE.ERROR_SUBTITLE')"
      :show-backdrop="false"
    >
      <template #actions>
        <Button
          color="slate"
          variant="outline"
          size="sm"
          icon="i-lucide-refresh-cw"
          :label="t('KANBAN.EMPTY_STATE.RETRY')"
          @click="retry"
        />
      </template>
    </EmptyStateLayout>

    <!-- Filtros sem resultado -->
    <EmptyStateLayout
      v-else-if="records.length && !filteredRecords.length"
      class="flex-1 min-h-0"
      :title="t('KANBAN.EMPTY_STATE.NO_RESULTS_TITLE')"
      :subtitle="t('KANBAN.EMPTY_STATE.NO_RESULTS_SUBTITLE')"
      :show-backdrop="false"
    >
      <template #actions>
        <Button
          color="slate"
          variant="outline"
          size="sm"
          :label="t('KANBAN.TOOLBAR.CLEAR')"
          @click="clearFilters"
        />
      </template>
    </EmptyStateLayout>

    <!-- Board -->
    <KanbanBoard
      v-else
      class="flex-1 min-h-0"
      :records="filteredRecords"
      :inbox-names="inboxNames"
    />
  </section>
</template>
