<script setup>
import { computed, ref, onMounted, provide } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { resolveStage } from 'dashboard/routes/dashboard/kanban/config/stages';
import { groupRecordsByContact } from 'dashboard/routes/dashboard/kanban/helper/grouping';
import {
  useKanbanViewState,
  KANBAN_VIEW_STATE_KEY,
} from 'dashboard/routes/dashboard/kanban/composables/useKanbanViewState';
import { useKanbanExport } from 'dashboard/routes/dashboard/kanban/composables/useKanbanExport';

import KanbanInboxFilter from '../components/KanbanInboxFilter.vue';
import KanbanToolbar from '../components/KanbanToolbar.vue';
import KanbanBoard from '../components/KanbanBoard.vue';
import KanbanExportMenu from '../components/KanbanExportMenu.vue';
import StageManagerDialog from '../components/StageManagerDialog.vue';
import KanbanHistoryView from '../components/KanbanHistoryView.vue';
import SdrDashboard from '../components/SdrDashboard.vue';
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
const currentRole = useMapGetter('getCurrentRole');
const currentUserId = useMapGetter('getCurrentUserID');

const isAdmin = computed(() => currentRole.value === 'administrator');
const hasSelection = computed(() => selectedInboxIds.value.length > 0);

// ---- Estado de trabalho persistido (por conta + usuário) -------------------
// Caixa, aba, filtros, ordenação, busca do histórico, rolagem e card âncora
// sobrevivem a abrir uma conversa e voltar (navegador ou menu). Os componentes
// filhos (board, card, histórico) recebem a API via provide/inject.
const viewState = useKanbanViewState({
  accountId: route.params.accountId,
  userId: currentUserId.value,
});
provide(KANBAN_VIEW_STATE_KEY, viewState);
const { state: view } = viewState;

// Board opera sobre UMA caixa (o funil é por caixa).
const activeInboxId = computed(() => selectedInboxIds.value[0] ?? null);
const stages = computed(() =>
  store.getters['kanban/getStagesForInbox'](activeInboxId.value)
);
const stageSlugs = computed(() => stages.value.map(stage => stage.slug));

// Classificação da caixa ativa: define a mecânica do board (comercial usa
// ganho/perdido; operacional sai ao resolver) e a visão padrão do dashboard.
const kanbanType = computed(() =>
  store.getters['kanban/getInboxType'](activeInboxId.value)
);

const inboxNames = computed(() => {
  const map = {};
  inboxes.value.forEach(inbox => {
    map[inbox.id] = inbox.name;
  });
  return map;
});

// ---- Abas (Board / Dashboard SDR / Histórico) -----------------------------
const activeTab = computed({
  get: () => view.activeTab,
  set: value => {
    view.activeTab = value;
  },
});
const tabs = computed(() => [
  { key: 'board', label: t('KANBAN.TABS.BOARD') },
  { key: 'dashboard', label: t('KANBAN.TABS.DASHBOARD') },
  { key: 'history', label: t('KANBAN.TABS.HISTORY') },
]);

// ---- Gerenciador de etapas (admin) ----------------------------------------
const stageManagerRef = ref(null);
const openStageManager = () => stageManagerRef.value?.open();

// ---- Filtros / ordenação (client-side, persistidos) -----------------------
const filters = computed(() => view.filters);
const sortBy = computed(() => view.sortBy);

const hasActiveFilters = computed(() =>
  Object.values(view.filters).some(value => value !== '')
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
  if (!view.filters.query) return true;
  const needle = view.filters.query.toLowerCase();
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

const volumeOf = record =>
  Number(record.custom_attributes?.valor_potencial) || 0;

const sorters = {
  last_activity_desc: (a, b) =>
    (b.last_activity_at || 0) - (a.last_activity_at || 0),
  created_desc: (a, b) => (b.created_at || 0) - (a.created_at || 0),
  created_asc: (a, b) => (a.created_at || 0) - (b.created_at || 0),
  volume_desc: (a, b) => volumeOf(b) - volumeOf(a),
};

// Filtros por conversa que NÃO dependem de etapa (aplicados antes de agrupar,
// para que o histórico do card não seja recortado pelo filtro de etapa).
const passesBaseFilters = record => {
  const current = view.filters;
  if (!matchesQuery(record)) return false;
  if (
    current.product &&
    record.custom_attributes?.produto_interesse !== current.product
  ) {
    return false;
  }
  if (
    current.assigneeId &&
    String(record.meta?.assignee?.id) !== current.assigneeId
  ) {
    return false;
  }
  const createdFrom = toSeconds(current.createdFrom);
  const createdTo = toSeconds(current.createdTo, true);
  if (createdFrom && (record.created_at || 0) < createdFrom) return false;
  if (createdTo && (record.created_at || 0) > createdTo) return false;
  return true;
};

// Nome da etapa por slug (para rotular o histórico do card).
const stageNameBySlug = computed(() => {
  const map = {};
  stages.value.forEach(stage => {
    map[stage.slug] = stage.name;
  });
  return map;
});

const historyDateFmt = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: '2-digit',
});

// Rótulo de cada atendimento anterior: "18/08 - Ganho" / "18/08 - Reunião".
const historyEntryLabel = entry => {
  const datePart = entry.at
    ? historyDateFmt.format(new Date(entry.at * 1000))
    : '';
  let statusPart;
  if (entry.outcome === 'won') statusPart = t('KANBAN.OUTCOME.WON');
  else if (entry.outcome === 'lost') statusPart = t('KANBAN.OUTCOME.LOST');
  else {
    statusPart =
      stageNameBySlug.value[entry.stage] ||
      entry.stage ||
      t('KANBAN.CARD.HISTORY_OPEN');
  }
  return [datePart, statusPart].filter(Boolean).join(' · ');
};

const decorateGroup = record => {
  if (!record.groupHistory?.length) return record;
  return {
    ...record,
    groupHistory: record.groupHistory.map(entry => ({
      ...entry,
      label: historyEntryLabel(entry),
    })),
  };
};

// Cards do board: 1 por contato. Agrupa após os filtros base e só então aplica
// o filtro de etapa (pela conversa primária, a mais recente), preservando o
// histórico completo do número no card.
const boardRecords = computed(() => {
  const slugs = stageSlugs.value;
  const grouped = groupRecordsByContact(
    records.value.filter(passesBaseFilters)
  ).map(decorateGroup);
  return grouped
    .filter(
      record =>
        !view.filters.stage ||
        resolveStage(record, slugs) === view.filters.stage
    )
    .sort(sorters[view.sortBy] || sorters.last_activity_desc);
});

const clearFilters = () => viewState.resetFilters();

const onFiltersUpdate = value => Object.assign(view.filters, value);
const onSortUpdate = value => {
  view.sortBy = value;
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
  // Board por caixa: mantém no máximo uma caixa selecionada.
  const single = ids.slice(0, 1);
  if (single[0] !== view.inboxId) {
    // Troca de caixa = outro contexto: rolagem e âncora antigas não valem.
    view.scroll = { boardLeft: 0, historyTop: 0 };
    view.anchor = { kind: '', id: null, at: 0 };
  }
  view.inboxId = single[0] ?? null;
  store.dispatch('kanban/setSelectedInboxIds', single);
  if (updateQuery) {
    router.replace({
      query: { ...route.query, inbox_ids: single.join(',') || undefined },
    });
  }
  store.dispatch('kanban/fetchBoard');
  if (single.length) {
    store.dispatch('kanban/fetchStages', { inboxId: single[0] });
    store.dispatch('kanban/fetchInboxConfig', { inboxId: single[0] });
  }
};

const onSelectionUpdate = ids => applySelection(ids);
const retry = () => store.dispatch('kanban/fetchBoard');

// ---- Exportação Excel (servidor) --------------------------------------------
const { isExporting, exportCsv } = useKanbanExport();
const exportBoard = () =>
  exportCsv({
    inboxId: activeInboxId.value,
    scope: 'board',
    filters: {
      q: view.filters.query,
      product: view.filters.product,
      stage: view.filters.stage,
      assignee_id: view.filters.assigneeId,
      created_from: view.filters.createdFrom,
      created_to: view.filters.createdTo,
    },
  });

const skeletonColumns = 5;
const skeletonCards = [1, 2, 3];

onMounted(async () => {
  if (!inboxes.value.length) {
    await store.dispatch('inboxes/get');
  }
  // Prioridade: caixa da URL → última caixa usada (estado salvo) → 1ª caixa.
  let ids = parseInboxIds(route.query.inbox_ids);
  if (!ids.length && view.inboxId) ids = parseInboxIds(view.inboxId);
  if (!ids.length && inboxes.value.length) {
    ids = [inboxes.value[0].id];
  }
  applySelection(ids, { updateQuery: !route.query.inbox_ids });
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex items-center justify-between flex-shrink-0 gap-4 px-6 py-2.5 border-b border-n-weak"
    >
      <h1 class="text-lg font-medium text-n-slate-12">
        {{ t('KANBAN.HEADER_TITLE') }}
      </h1>
      <div class="flex items-center gap-2">
        <Button
          v-if="activeTab === 'board' && isAdmin && hasSelection"
          color="slate"
          variant="ghost"
          size="sm"
          icon="i-lucide-settings-2"
          :label="t('KANBAN.STAGE_MANAGER.MANAGE')"
          @click="openStageManager"
        />
        <KanbanExportMenu
          v-if="activeTab === 'board' && hasSelection && records.length"
          :has-active-filters="hasActiveFilters"
          :is-exporting="isExporting"
          @export="exportBoard"
        />
        <KanbanInboxFilter
          :inboxes="inboxes"
          :selected-ids="selectedInboxIds"
          @update:selected-ids="onSelectionUpdate"
        />
      </div>
    </header>

    <!-- Abas -->
    <nav
      class="flex items-center flex-shrink-0 gap-1 px-4 border-b border-n-weak"
    >
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        class="relative flex items-center gap-1.5 px-3 -mb-px text-sm font-medium transition-colors border-b-2 h-9"
        :class="
          activeTab === tab.key
            ? 'border-n-brand text-n-slate-12'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        @click="activeTab = tab.key"
      >
        {{ tab.label }}
      </button>
    </nav>

    <!-- Aba: Board -->
    <template v-if="activeTab === 'board'">
      <KanbanToolbar
        v-if="
          hasSelection &&
          !uiFlags.isFetching &&
          !uiFlags.hasError &&
          records.length
        "
        :filters="filters"
        :sort-by="sortBy"
        :products="products"
        :assignees="assignees"
        :stages="stages"
        :has-active-filters="hasActiveFilters"
        @update:filters="onFiltersUpdate"
        @update:sort-by="onSortUpdate"
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
        class="flex flex-1 gap-3 px-3 py-3 overflow-hidden min-h-0"
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
        v-else-if="records.length && !boardRecords.length"
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
        :records="boardRecords"
        :stages="stages"
        :inbox-names="inboxNames"
        :kanban-type="kanbanType"
      />
    </template>

    <!-- Aba: Dashboard SDR -->
    <SdrDashboard
      v-else-if="activeTab === 'dashboard'"
      :default-inbox-id="activeInboxId"
    />

    <!-- Aba: Histórico -->
    <KanbanHistoryView
      v-else
      :inbox-id="activeInboxId"
      :kanban-type="kanbanType"
    />

    <StageManagerDialog
      ref="stageManagerRef"
      :inbox-id="activeInboxId"
      :stages="stages"
    />
  </section>
</template>
