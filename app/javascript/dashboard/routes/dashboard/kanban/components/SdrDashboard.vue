<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';

// Dashboard SDR (Fase D): tempo médio por etapa, leads identificados, conversão
// e ticket médio. Filtro por caixa ou visão geral + período. Dados agregados no
// backend (Finture::SdrReportService) sobre finture_stage_transitions/quotes.
const props = defineProps({
  defaultInboxId: {
    type: [Number, String],
    default: null,
  },
});

const store = useStore();
const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');

const selectedInboxId = ref(
  props.defaultInboxId ? String(props.defaultInboxId) : ''
);
const period = ref('30');

const dashboard = computed(() => store.getters['kanban/getDashboard']);
const uiFlags = computed(() => store.getters['kanban/getDashboardUIFlags']);

const load = () => {
  const until = Math.floor(Date.now() / 1000);
  const since = until - Number(period.value) * 24 * 60 * 60;
  const params = { since, until };
  if (selectedInboxId.value) params.inbox_id = selectedInboxId.value;
  store.dispatch('kanban/fetchDashboard', params);
};

watch([selectedInboxId, period], load);
onMounted(load);

const currency = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

const conversionPct = computed(() =>
  dashboard.value ? Math.round((dashboard.value.conversion_rate || 0) * 100) : 0
);
const ticket = computed(() =>
  currency.format(dashboard.value?.ticket_medio || 0)
);

const cards = computed(() => [
  {
    key: 'leads',
    label: t('KANBAN.DASHBOARD.LEADS'),
    value: dashboard.value?.leads_identified ?? 0,
    icon: 'i-lucide-users',
  },
  {
    key: 'conversion',
    label: t('KANBAN.DASHBOARD.CONVERSION'),
    value: `${conversionPct.value}%`,
    icon: 'i-lucide-trending-up',
  },
  {
    key: 'ticket',
    label: t('KANBAN.DASHBOARD.TICKET'),
    value: ticket.value,
    icon: 'i-lucide-banknote',
  },
  {
    key: 'won',
    label: t('KANBAN.DASHBOARD.WON'),
    value: dashboard.value?.won ?? 0,
    icon: 'i-lucide-trophy',
  },
  {
    key: 'lost',
    label: t('KANBAN.DASHBOARD.LOST'),
    value: dashboard.value?.lost ?? 0,
    icon: 'i-lucide-circle-x',
  },
  {
    key: 'open',
    label: t('KANBAN.DASHBOARD.OPEN'),
    value: dashboard.value?.open ?? 0,
    icon: 'i-lucide-inbox',
  },
]);

const stageRows = computed(() => dashboard.value?.avg_time_per_stage || []);
const maxStageSeconds = computed(() =>
  Math.max(1, ...stageRows.value.map(row => row.avg_seconds))
);

const formatDuration = seconds => {
  if (!seconds) return '—';
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days) return `${days}d ${hours}h`;
  if (hours) return `${hours}h ${minutes}min`;
  return `${minutes}min`;
};

const inputClass =
  'h-8 px-2.5 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand';
</script>

<template>
  <div class="flex flex-col flex-1 min-h-0 gap-4 px-4 py-3 overflow-y-auto">
    <!-- Filtros -->
    <div class="flex flex-wrap items-center gap-2">
      <select v-model="selectedInboxId" :class="inputClass">
        <option value="">{{ t('KANBAN.DASHBOARD.ALL_INBOXES') }}</option>
        <option
          v-for="inbox in inboxes"
          :key="inbox.id"
          :value="String(inbox.id)"
        >
          {{ inbox.name }}
        </option>
      </select>
      <select v-model="period" :class="inputClass">
        <option value="7">{{ t('KANBAN.DASHBOARD.PERIOD_7') }}</option>
        <option value="30">{{ t('KANBAN.DASHBOARD.PERIOD_30') }}</option>
        <option value="90">{{ t('KANBAN.DASHBOARD.PERIOD_90') }}</option>
      </select>
      <span v-if="uiFlags.isFetching" class="text-xs text-n-slate-10">
        {{ t('KANBAN.DASHBOARD.LOADING') }}
      </span>
    </div>

    <!-- Cartões de métrica -->
    <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
      <div
        v-for="card in cards"
        :key="card.key"
        class="flex flex-col gap-1 p-3 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div class="flex items-center gap-1.5 text-n-slate-11">
          <Icon :icon="card.icon" class="size-4" />
          <span class="text-xs">{{ card.label }}</span>
        </div>
        <span class="text-xl font-medium text-n-slate-12">{{
          card.value
        }}</span>
      </div>
    </div>

    <!-- Tempo médio por etapa -->
    <div
      class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <h3 class="text-sm font-medium text-n-slate-12">
        {{ t('KANBAN.DASHBOARD.AVG_TIME_TITLE') }}
      </h3>
      <p v-if="!stageRows.length" class="text-sm text-n-slate-10">
        {{ t('KANBAN.DASHBOARD.AVG_TIME_EMPTY') }}
      </p>
      <div v-else class="flex flex-col gap-2">
        <div
          v-for="row in stageRows"
          :key="row.slug"
          class="flex flex-col gap-1"
        >
          <div class="flex items-center justify-between text-xs">
            <span class="text-n-slate-12">{{ row.name }}</span>
            <span class="text-n-slate-11">{{
              formatDuration(row.avg_seconds)
            }}</span>
          </div>
          <div class="h-2 rounded-full bg-n-alpha-2">
            <div
              class="h-2 rounded-full bg-n-brand"
              :style="{
                width: `${Math.max(4, (row.avg_seconds / maxStageSeconds) * 100)}%`,
              }"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
