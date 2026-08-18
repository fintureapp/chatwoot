<script setup>
// Dashboard SDR repaginado: duas visões (Comercial / Operacional) num seletor
// segmentado, com barra de filtros nova. A visão COMERCIAL está completa —
// conversão, funil, mix, perdas, tendência e velocidade — sobre os dados
// agregados em Finture::SdrCommercialReportService (view=commercial). A visão
// Operacional entra na próxima fase.
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MetricTile from './dashboard/MetricTile.vue';
import TrendChart from './dashboard/TrendChart.vue';
import FunnelChart from './dashboard/FunnelChart.vue';
import BarList from './dashboard/BarList.vue';
import FollowUpList from './dashboard/FollowUpList.vue';
import { lostReasonLabel } from '../config/stages';

const props = defineProps({
  defaultInboxId: { type: [Number, String], default: null },
});

const store = useStore();
const { t } = useI18n();
const inboxes = useMapGetter('inboxes/getInboxes');

const activeView = ref('commercial'); // 'commercial' | 'operational'
const selectedInboxId = ref(
  props.defaultInboxId ? String(props.defaultInboxId) : ''
);
const period = ref('30'); // dias
const compareWith = ref('previous'); // 'previous' | 'year'

const dashboard = computed(() => store.getters['kanban/getDashboard']);
const uiFlags = computed(() => store.getters['kanban/getDashboardUIFlags']);

const compareLabel = computed(() =>
  compareWith.value === 'year'
    ? t('KANBAN.DASHBOARD.COMPARE_YEAR')
    : t('KANBAN.DASHBOARD.COMPARE_PREV')
);

const load = () => {
  const until = Math.floor(Date.now() / 1000);
  const since = until - Number(period.value) * 86400;
  const params = { view: activeView.value, since, until };
  if (selectedInboxId.value) params.inbox_id = selectedInboxId.value;
  if (activeView.value === 'commercial' && compareWith.value === 'year') {
    params.compare_since = since - 365 * 86400;
    params.compare_until = until - 365 * 86400;
  }
  store.dispatch('kanban/fetchDashboard', params);
};

watch([selectedInboxId, period, compareWith, activeView], load);
onMounted(load);

// ---- Formatação -----------------------------------------------------------
const nf = new Intl.NumberFormat('pt-BR');
const fmtNum = value => nf.format(value ?? 0);
const fmtDays = value =>
  (value ?? 0).toLocaleString('pt-BR', { maximumFractionDigits: 1 });

// Tom (good/bad/neutral) a partir do sinal de um número. positiveIsGood=false
// inverte a leitura (ex.: ciclo maior = pior).
const toneFromSign = (value, positiveIsGood = true) => {
  if (!value) return 'neutral';
  return value > 0 === positiveIsGood ? 'good' : 'bad';
};

const ppDelta = delta =>
  delta == null
    ? null
    : {
        text: `${delta > 0 ? '+' : ''}${Math.round(delta * 100)} pp`,
        tone: toneFromSign(delta),
        hint: compareLabel.value,
      };

const pctDelta = (current, previous) => {
  if (current == null || previous == null) return null;
  if (previous === 0) {
    return {
      text: current > 0 ? t('KANBAN.DASHBOARD.NEW') : '—',
      tone: current > 0 ? 'good' : 'neutral',
      hint: compareLabel.value,
    };
  }
  const pct = Math.round(((current - previous) / previous) * 100);
  return {
    text: `${pct > 0 ? '+' : ''}${pct}%`,
    tone: toneFromSign(pct),
    hint: compareLabel.value,
  };
};

// Ciclo: quanto MENOR, melhor. Dica textual explica se acelerou/desacelerou.
const cycleHint = delta => {
  if (delta < 0) return t('KANBAN.DASHBOARD.FASTER');
  if (delta > 0) return t('KANBAN.DASHBOARD.SLOWER');
  return compareLabel.value;
};

const cycleDelta = delta =>
  delta == null
    ? null
    : {
        text: `${delta > 0 ? '+' : ''}${fmtDays(delta)} d`,
        tone: toneFromSign(delta, false),
        hint: cycleHint(delta),
      };

// ---- KPIs -----------------------------------------------------------------
const kpis = computed(() => {
  const k = dashboard.value?.kpis;
  if (!k || !k.conversion) return []; // guarda contra o shape da outra visão
  return [
    {
      key: 'conversion',
      label: t('KANBAN.DASHBOARD.CONVERSION'),
      icon: 'i-lucide-trending-up',
      value: `${Math.round((k.conversion.value || 0) * 100)}%`,
      delta: ppDelta(k.conversion.delta),
    },
    {
      key: 'leads',
      label: t('KANBAN.DASHBOARD.LEADS'),
      icon: 'i-lucide-users',
      value: fmtNum(k.leads.value),
      delta: pctDelta(k.leads.value, k.leads.previous),
    },
    {
      key: 'won',
      label: t('KANBAN.DASHBOARD.WON'),
      icon: 'i-lucide-trophy',
      value: fmtNum(k.won.value),
      delta: pctDelta(k.won.value, k.won.previous),
    },
    {
      key: 'cycle',
      label: t('KANBAN.DASHBOARD.CYCLE'),
      icon: 'i-lucide-clock',
      value: `${fmtDays(k.cycle_days.value)} d`,
      delta: cycleDelta(k.cycle_days.delta),
    },
  ];
});

// ---- Blocos ---------------------------------------------------------------
const funnelNodes = computed(() => dashboard.value?.funnel || []);
const trendSeries = computed(() => dashboard.value?.trend || null);
const overallCycle = computed(() => dashboard.value?.velocity?.overall_days);

const mixTotal = computed(() =>
  (dashboard.value?.mix || []).reduce((sum, row) => sum + row.count, 0)
);
const mixRows = computed(() =>
  (dashboard.value?.mix || []).map(row => ({
    label: row.product,
    value: row.count,
    display: fmtNum(row.count),
    sub: mixTotal.value
      ? `${Math.round((row.count / mixTotal.value) * 100)}%`
      : '',
  }))
);

const lossTotal = computed(() =>
  (dashboard.value?.loss_reasons || []).reduce((sum, row) => sum + row.count, 0)
);
const lossRows = computed(() =>
  (dashboard.value?.loss_reasons || []).map(row => ({
    label: lostReasonLabel(row.reason),
    value: row.count,
    display: fmtNum(row.count),
    sub: lossTotal.value
      ? `${Math.round((row.count / lossTotal.value) * 100)}%`
      : '',
  }))
);

const velocityRows = computed(() =>
  (dashboard.value?.velocity?.by_product || []).map(row => ({
    label: row.product,
    value: row.days,
    display: `${fmtDays(row.days)} d`,
  }))
);

const hasData = computed(() => Boolean(dashboard.value?.kpis?.conversion));

// ---- Operacional ----------------------------------------------------------
const fmtMinutes = value => {
  if (value == null) return '—';
  if (value < 60) return `${value} min`;
  const hours = Math.floor(value / 60);
  const minutes = value % 60;
  return minutes ? `${hours}h ${minutes}min` : `${hours}h`;
};

const formatDuration = seconds => {
  if (!seconds) return '—';
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days) return `${days}d ${hours}h`;
  if (hours) return `${hours}h ${minutes}min`;
  return `${minutes}min`;
};

const hasOpData = computed(() => Boolean(dashboard.value?.follow_ups));
const opFollowUps = computed(() => dashboard.value?.follow_ups || null);
const opStalled = computed(() => dashboard.value?.stalled || []);
const opSlaAvg = computed(() => dashboard.value?.sla?.avg_minutes);
const opSlaTarget = computed(() => dashboard.value?.sla?.target_minutes ?? 45);
// Verde quando a média bate a meta, vermelho quando estoura; neutro sem dado.
const opSlaTone = computed(() => {
  if (opSlaAvg.value == null) return 'text-n-slate-12';
  return opSlaAvg.value <= opSlaTarget.value
    ? 'text-n-teal-11'
    : 'text-n-ruby-11';
});

// Follow-ups do agente logado — presente nas duas visões (comercial/operacional).
const myFollowUps = computed(() => dashboard.value?.my_follow_ups || []);
const opOnTimePct = computed(() =>
  opFollowUps.value?.on_time_pct == null
    ? '—'
    : `${Math.round(opFollowUps.value.on_time_pct * 100)}%`
);

const opKpis = computed(() => {
  const k = dashboard.value?.kpis;
  if (!k || !('overdue_followups' in k)) return [];
  return [
    {
      key: 'overdue',
      label: t('KANBAN.DASHBOARD.OP_OVERDUE'),
      icon: 'i-lucide-alarm-clock',
      value: fmtNum(k.overdue_followups),
      emphasis: 'crit',
      delta: { text: t('KANBAN.DASHBOARD.OP_ACTION_NOW'), tone: 'neutral' },
    },
    {
      key: 'today',
      label: t('KANBAN.DASHBOARD.OP_TODAY'),
      icon: 'i-lucide-calendar-clock',
      value: fmtNum(k.followups_today),
    },
    {
      key: 'unassigned',
      label: t('KANBAN.DASHBOARD.OP_UNASSIGNED'),
      icon: 'i-lucide-user-x',
      value: fmtNum(k.unassigned),
      emphasis: 'warn',
    },
    {
      key: 'stalled',
      label: t('KANBAN.DASHBOARD.OP_STALLED'),
      icon: 'i-lucide-timer-off',
      value: fmtNum(k.stalled),
      emphasis: 'warn',
    },
    {
      key: 'sla',
      label: t('KANBAN.DASHBOARD.OP_SLA'),
      icon: 'i-lucide-timer',
      value: fmtMinutes(k.sla_minutes),
    },
  ];
});

const loadRows = computed(() =>
  (dashboard.value?.load || []).map(row => ({
    label: row.name,
    value: row.count,
    display: fmtNum(row.count),
  }))
);
const slaRows = computed(() =>
  (dashboard.value?.sla?.by_product || []).map(row => ({
    label: row.product,
    value: row.minutes || 0,
    display: fmtMinutes(row.minutes),
  }))
);
const stageTimeRows = computed(() =>
  (dashboard.value?.stage_time || []).map(row => ({
    label: row.name,
    value: row.seconds,
    display: formatDuration(row.seconds),
  }))
);

// Select compacto com largura própria. O CSS global do app força width:100% e um
// margin-bottom nos selects — w-auto + max-w + !my-0 neutralizam ambos (senão os
// campos ficam gigantes/empilhados e desalinhados na vertical).
const selectClass =
  'h-8 w-auto max-w-[15rem] !my-0 pl-3 pr-8 text-[13px] rounded-lg bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak cursor-pointer transition-colors hover:outline-n-slate-6 focus:outline-n-brand';

const periodOptions = computed(() => [
  { value: '7', label: t('KANBAN.DASHBOARD.PERIOD_7_SHORT') },
  { value: '30', label: t('KANBAN.DASHBOARD.PERIOD_30_SHORT') },
  { value: '90', label: t('KANBAN.DASHBOARD.PERIOD_90_SHORT') },
]);

const views = computed(() => [
  { key: 'commercial', label: t('KANBAN.DASHBOARD.VIEW_COMMERCIAL') },
  { key: 'operational', label: t('KANBAN.DASHBOARD.VIEW_OPERATIONAL') },
]);
</script>

<template>
  <div class="flex flex-col flex-1 min-h-0 gap-4 px-4 py-3 overflow-y-auto">
    <!-- Seletor de visão + nota -->
    <div class="flex flex-wrap items-center gap-3">
      <div
        class="inline-flex gap-0.5 p-0.5 rounded-lg bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak"
        role="tablist"
      >
        <button
          v-for="view in views"
          :key="view.key"
          type="button"
          role="tab"
          :aria-selected="activeView === view.key"
          class="px-3.5 py-1.5 text-[13px] font-medium rounded-md transition-colors"
          :class="
            activeView === view.key
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          @click="activeView = view.key"
        >
          {{ view.label }}
        </button>
      </div>
      <span class="text-[12.5px] text-n-slate-11">
        {{
          activeView === 'commercial'
            ? t('KANBAN.DASHBOARD.VIEW_COMMERCIAL_NOTE')
            : t('KANBAN.DASHBOARD.VIEW_OPERATIONAL_NOTE')
        }}
      </span>
    </div>

    <!-- Filtros -->
    <div
      class="flex flex-wrap items-center gap-2.5 p-2 rounded-xl bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak"
    >
      <!-- Caixa -->
      <div class="relative inline-flex items-center">
        <span
          class="absolute -translate-y-1/2 left-2.5 top-1/2 text-base pointer-events-none i-lucide-inbox text-n-slate-10"
        />
        <select
          v-model="selectedInboxId"
          :class="selectClass"
          class="!pl-8"
          :aria-label="t('KANBAN.DASHBOARD.FILTER_INBOX')"
        >
          <option value="">{{ t('KANBAN.DASHBOARD.ALL_INBOXES') }}</option>
          <option
            v-for="inbox in inboxes"
            :key="inbox.id"
            :value="String(inbox.id)"
          >
            {{ inbox.name }}
          </option>
        </select>
      </div>

      <!-- Período (segmentado) -->
      <div
        class="inline-flex gap-0.5 p-0.5 rounded-lg bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
        role="group"
      >
        <button
          v-for="opt in periodOptions"
          :key="opt.value"
          type="button"
          class="px-3 py-1 text-[13px] font-medium rounded-md transition-colors"
          :class="
            period === opt.value
              ? 'bg-n-brand text-white shadow-sm'
              : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1'
          "
          @click="period = opt.value"
        >
          {{ opt.label }}
        </button>
      </div>

      <!-- Comparação (só comercial) -->
      <div
        v-if="activeView === 'commercial'"
        class="inline-flex items-center gap-1.5 ml-auto"
      >
        <span class="text-[12.5px] text-n-slate-11">
          {{ t('KANBAN.DASHBOARD.COMPARE_LABEL') }}
        </span>
        <select v-model="compareWith" :class="selectClass">
          <option value="previous">
            {{ t('KANBAN.DASHBOARD.COMPARE_PREV') }}
          </option>
          <option value="year">
            {{ t('KANBAN.DASHBOARD.COMPARE_YEAR') }}
          </option>
        </select>
      </div>

      <span
        v-if="uiFlags.isFetching"
        class="text-xs text-n-slate-10"
        :class="{ 'ml-auto': activeView !== 'commercial' }"
      >
        {{ t('KANBAN.DASHBOARD.LOADING') }}
      </span>
    </div>

    <!-- ===================== VISÃO COMERCIAL ===================== -->
    <template v-if="activeView === 'commercial'">
      <div
        v-if="!hasData && !uiFlags.isFetching"
        class="flex flex-col items-center justify-center flex-1 gap-2 py-16 text-center"
      >
        <Icon icon="i-lucide-inbox" class="size-8 text-n-slate-9" />
        <p class="text-sm text-n-slate-11">
          {{ t('KANBAN.DASHBOARD.EMPTY') }}
        </p>
      </div>

      <template v-else>
        <!-- KPIs -->
        <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
          <MetricTile
            v-for="kpi in kpis"
            :key="kpi.key"
            :label="kpi.label"
            :value="kpi.value"
            :icon="kpi.icon"
            :delta="kpi.delta"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-12">
          <!-- Tendência -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-8 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div>
              <div
                class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
              >
                {{ t('KANBAN.DASHBOARD.TREND_EYEBROW') }}
              </div>
              <h3 class="text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.DASHBOARD.TREND_TITLE') }}
              </h3>
            </div>
            <TrendChart
              v-if="trendSeries"
              :series="trendSeries"
              :compare-label="compareLabel"
            />
          </div>

          <!-- Velocidade -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-4 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div>
              <div
                class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
              >
                {{ t('KANBAN.DASHBOARD.VELOCITY_EYEBROW') }}
              </div>
              <h3 class="text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.DASHBOARD.VELOCITY_TITLE') }}
              </h3>
            </div>
            <BarList
              v-if="velocityRows.length"
              :rows="velocityRows"
              tone="brand"
            />
            <p v-else class="text-sm text-n-slate-10">
              {{ t('KANBAN.DASHBOARD.EMPTY_BLOCK') }}
            </p>
            <p
              v-if="overallCycle != null"
              class="flex items-center gap-1.5 mt-auto text-xs text-n-slate-11"
            >
              <Icon icon="i-lucide-clock" class="size-3.5 text-n-slate-9" />
              {{ t('KANBAN.DASHBOARD.VELOCITY_OVERALL') }}
              <b class="text-n-slate-12">{{
                t('KANBAN.DASHBOARD.DAYS_SHORT', {
                  count: fmtDays(overallCycle),
                })
              }}</b>
            </p>
          </div>

          <!-- Funil -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-6 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div class="flex items-baseline justify-between gap-3">
              <div>
                <div
                  class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('KANBAN.DASHBOARD.CONVERSION') }}
                </div>
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.DASHBOARD.FUNNEL_TITLE') }}
                </h3>
              </div>
              <span class="text-xs text-n-slate-11">{{
                t('KANBAN.DASHBOARD.FUNNEL_NOTE')
              }}</span>
            </div>
            <FunnelChart v-if="funnelNodes.length" :nodes="funnelNodes" />
            <p v-else class="text-sm text-n-slate-10">
              {{ t('KANBAN.DASHBOARD.EMPTY_BLOCK') }}
            </p>
          </div>

          <!-- Mix -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-6 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div class="flex items-baseline justify-between gap-3">
              <div>
                <div
                  class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('KANBAN.DASHBOARD.MIX_EYEBROW') }}
                </div>
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.DASHBOARD.MIX_TITLE') }}
                </h3>
              </div>
              <span class="text-xs text-n-slate-11 tabular-nums">
                {{
                  t('KANBAN.DASHBOARD.MIX_NOTE', { count: fmtNum(mixTotal) })
                }}
              </span>
            </div>
            <BarList v-if="mixRows.length" :rows="mixRows" tone="brand" />
            <p v-else class="text-sm text-n-slate-10">
              {{ t('KANBAN.DASHBOARD.EMPTY_BLOCK') }}
            </p>
          </div>

          <!-- Perdas -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-12 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div class="flex items-baseline justify-between gap-3">
              <div>
                <div
                  class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('KANBAN.DASHBOARD.LOSS_EYEBROW') }}
                </div>
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.DASHBOARD.LOSS_TITLE') }}
                </h3>
              </div>
              <span class="text-xs text-n-slate-11 tabular-nums">
                {{
                  t('KANBAN.DASHBOARD.LOSS_NOTE', { count: fmtNum(lossTotal) })
                }}
              </span>
            </div>
            <BarList v-if="lossRows.length" :rows="lossRows" tone="ruby" />
            <p v-else class="text-sm text-n-slate-10">
              {{ t('KANBAN.DASHBOARD.LOSS_EMPTY') }}
            </p>
          </div>

          <!-- Meus follow-ups -->
          <div class="md:col-span-12">
            <FollowUpList :items="myFollowUps" />
          </div>
        </div>
      </template>
    </template>

    <!-- ===================== VISÃO OPERACIONAL ===================== -->
    <template v-else>
      <div
        v-if="!hasOpData && !uiFlags.isFetching"
        class="flex flex-col items-center justify-center flex-1 gap-2 py-16 text-center"
      >
        <Icon icon="i-lucide-inbox" class="size-8 text-n-slate-9" />
        <p class="text-sm text-n-slate-11">{{ t('KANBAN.DASHBOARD.EMPTY') }}</p>
      </div>

      <template v-else>
        <!-- KPIs de alerta -->
        <div class="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
          <MetricTile
            v-for="kpi in opKpis"
            :key="kpi.key"
            :label="kpi.label"
            :value="kpi.value"
            :icon="kpi.icon"
            :emphasis="kpi.emphasis"
            :delta="kpi.delta"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-12">
          <!-- Carga do funil -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-8 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div class="flex items-baseline justify-between gap-3">
              <div>
                <div
                  class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('KANBAN.DASHBOARD.CARGA_EYEBROW') }}
                </div>
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.DASHBOARD.CARGA_TITLE') }}
                </h3>
              </div>
              <span class="text-xs text-n-slate-11">{{
                t('KANBAN.DASHBOARD.CARGA_NOTE')
              }}</span>
            </div>
            <BarList v-if="loadRows.length" :rows="loadRows" tone="brand" />
            <p v-else class="text-sm text-n-slate-10">
              {{ t('KANBAN.DASHBOARD.EMPTY_BLOCK') }}
            </p>
          </div>

          <!-- Follow-ups -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-4 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div>
              <div
                class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
              >
                {{ t('KANBAN.DASHBOARD.FOLLOWUPS_EYEBROW') }}
              </div>
              <h3 class="text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.DASHBOARD.FOLLOWUPS_TITLE') }}
              </h3>
            </div>
            <div class="grid grid-cols-2 gap-2.5">
              <div class="p-3 rounded-lg bg-n-alpha-1">
                <div class="text-xl font-semibold text-n-slate-12 tabular-nums">
                  {{ opFollowUps?.open ?? 0 }}
                </div>
                <div class="mt-1 text-xs text-n-slate-11">
                  {{ t('KANBAN.DASHBOARD.FU_OPEN') }}
                </div>
              </div>
              <div class="p-3 rounded-lg bg-n-ruby-3">
                <div class="text-xl font-semibold text-n-ruby-11 tabular-nums">
                  {{ opFollowUps?.overdue ?? 0 }}
                </div>
                <div class="mt-1 text-xs text-n-slate-11">
                  {{ t('KANBAN.DASHBOARD.FU_OVERDUE') }}
                </div>
              </div>
              <div class="p-3 rounded-lg bg-n-alpha-1">
                <div class="text-xl font-semibold text-n-slate-12 tabular-nums">
                  {{ opFollowUps?.completed ?? 0 }}
                </div>
                <div class="mt-1 text-xs text-n-slate-11">
                  {{ t('KANBAN.DASHBOARD.FU_DONE') }}
                </div>
              </div>
              <div class="p-3 rounded-lg bg-n-teal-3">
                <div class="text-xl font-semibold text-n-teal-11 tabular-nums">
                  {{ opOnTimePct }}
                </div>
                <div class="mt-1 text-xs text-n-slate-11">
                  {{ t('KANBAN.DASHBOARD.FU_ONTIME') }}
                </div>
              </div>
            </div>
          </div>

          <!-- Gargalo -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-6 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div class="flex items-baseline justify-between gap-3">
              <div>
                <div
                  class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('KANBAN.DASHBOARD.GARGALO_EYEBROW') }}
                </div>
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.DASHBOARD.GARGALO_TITLE') }}
                </h3>
              </div>
              <span class="text-xs text-n-slate-11">{{
                t('KANBAN.DASHBOARD.GARGALO_NOTE')
              }}</span>
            </div>
            <BarList
              v-if="stageTimeRows.length"
              :rows="stageTimeRows"
              tone="ruby"
            />
            <p v-else class="text-sm text-n-slate-10">
              {{ t('KANBAN.DASHBOARD.EMPTY_BLOCK') }}
            </p>
          </div>

          <!-- SLA por área -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-6 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div>
              <div
                class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
              >
                {{ t('KANBAN.DASHBOARD.SLA_EYEBROW') }}
              </div>
              <h3 class="text-sm font-medium text-n-slate-12">
                {{ t('KANBAN.DASHBOARD.SLA_BYPRODUCT_TITLE') }}
              </h3>
            </div>
            <div class="flex items-baseline gap-2">
              <span
                class="text-3xl font-semibold tabular-nums leading-none"
                :class="opSlaTone"
              >
                {{ fmtMinutes(opSlaAvg) }}
              </span>
              <span class="text-xs text-n-slate-11">{{
                t('KANBAN.DASHBOARD.SLA_META', { count: opSlaTarget })
              }}</span>
            </div>
            <BarList v-if="slaRows.length" :rows="slaRows" tone="brand" />
          </div>

          <!-- Leads parados -->
          <div
            class="flex flex-col gap-4 p-4 md:col-span-12 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <div class="flex items-baseline justify-between gap-3">
              <div>
                <div
                  class="text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                >
                  {{ t('KANBAN.DASHBOARD.STALLED_EYEBROW') }}
                </div>
                <h3 class="text-sm font-medium text-n-slate-12">
                  {{ t('KANBAN.DASHBOARD.STALLED_TITLE') }}
                </h3>
              </div>
              <span class="text-xs text-n-slate-11">{{
                t('KANBAN.DASHBOARD.STALLED_NOTE')
              }}</span>
            </div>
            <div v-if="opStalled.length" class="overflow-x-auto -mx-1">
              <table class="w-full text-[13px] min-w-[440px]">
                <thead>
                  <tr class="text-left">
                    <th
                      class="pb-2 pl-1 text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                    >
                      {{ t('KANBAN.DASHBOARD.COL_CONTACT') }}
                    </th>
                    <th
                      class="pb-2 text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                    >
                      {{ t('KANBAN.DASHBOARD.COL_PRODUCT') }}
                    </th>
                    <th
                      class="pb-2 text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                    >
                      {{ t('KANBAN.DASHBOARD.COL_STAGE') }}
                    </th>
                    <th
                      class="pb-2 text-right text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                    >
                      {{ t('KANBAN.DASHBOARD.COL_STALLED') }}
                    </th>
                    <th
                      class="pb-2 text-[10.5px] font-bold uppercase tracking-wider text-n-slate-10"
                    >
                      {{ t('KANBAN.DASHBOARD.COL_ASSIGNEE') }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="lead in opStalled"
                    :key="lead.id"
                    class="border-t border-n-weak"
                  >
                    <td class="py-2.5 pl-1 font-medium text-n-slate-12">
                      {{ lead.contact || t('KANBAN.DASHBOARD.NOT_INFORMED') }}
                    </td>
                    <td class="text-n-slate-11">
                      {{ lead.product || t('KANBAN.DASHBOARD.NOT_INFORMED') }}
                    </td>
                    <td class="text-n-slate-11">{{ lead.stage }}</td>
                    <td
                      class="font-semibold text-right tabular-nums"
                      :class="
                        lead.days >= 10 ? 'text-n-ruby-11' : 'text-n-amber-11'
                      "
                    >
                      {{ t('KANBAN.DASHBOARD.DAYS', { count: lead.days }) }}
                    </td>
                    <td class="text-n-slate-11">
                      {{
                        lead.assignee || t('KANBAN.DASHBOARD.UNASSIGNED_TAG')
                      }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p v-else class="text-sm text-n-slate-10">
              {{ t('KANBAN.DASHBOARD.STALLED_EMPTY') }}
            </p>
          </div>

          <!-- Meus follow-ups -->
          <div class="md:col-span-12">
            <FollowUpList :items="myFollowUps" />
          </div>
        </div>
      </template>
    </template>
  </div>
</template>
