<script setup>
// Home, a primeira tela de todo usuário, com os números da conta inteira para
// qualquer papel (o backend não recorta por caixa). No topo, os números do período
// (chegaram, resolvidas, volume ganho — comparados ao período anterior) e o retrato de agora (funil em
// aberto e IA); depois o gráfico de chegadas x resoluções, a carga por equipe
// com os mesmos times do wallboard, o 1º contato humano e os motivos de perda.
// Todo número abre a lista que o compõe (HomeDrilldownDialog).
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import FintureHomeAPI from 'dashboard/api/fintureHome';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import HomeKpi from '../components/HomeKpi.vue';
import HomeSection from '../components/HomeSection.vue';
import HomeTrendChart from '../components/HomeTrendChart.vue';
import HomeDrilldownDialog from '../components/HomeDrilldownDialog.vue';
import { lostReasonLabel } from '../../kanban/config/stages';
import { fmtDateTime, fmtElapsed, fmtTime } from '../helpers';

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();
const inboxes = useMapGetter('inboxes/getInboxes');
const teams = useMapGetter('teams/getTeams');

// ---- Filtros (espelhados na URL) -------------------------------------------
const inboxId = ref(route.query.inbox_id || '');
const purpose = ref(route.query.purpose || '');
const teamId = ref(route.query.team_id || '');
const period = ref(route.query.period || '7');

const filters = computed(() => {
  const params = { period: period.value };
  if (inboxId.value) params.inbox_id = inboxId.value;
  if (purpose.value) params.purpose = purpose.value;
  if (teamId.value) params.team_id = teamId.value;
  return params;
});

// ---- Dados ------------------------------------------------------------------
const data = ref(null);
const isLoading = ref(false);
const hasError = ref(false);

const load = async () => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const response = await FintureHomeAPI.get(filters.value);
    data.value = response.data;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

watch(filters, value => {
  router.replace({ query: value });
  load();
});

onMounted(() => {
  store.dispatch('teams/get');
  load();
});

// ---- Drill-down -------------------------------------------------------------
const drilldownRef = ref(null);
const openList = (metric, title, extra = {}) => {
  drilldownRef.value?.open({
    metric,
    title,
    filters: { ...filters.value, ...extra },
  });
};

// ---- Resumo -----------------------------------------------------------------
const nf = new Intl.NumberFormat('pt-BR');
const generatedAt = computed(() => data.value?.generated_at || 0);
const updatedLabel = computed(() =>
  generatedAt.value
    ? t('FINTURE_HOME.UPDATED_AT', { time: fmtTime(generatedAt.value) })
    : ''
);
const highlights = computed(() => data.value?.highlights || {});
const previous = computed(() => data.value?.previous || {});
const won = computed(() => highlights.value.won);
const pipeline = computed(() => highlights.value.pipeline);

// Com quem o período é comparado: "hoje" contra ontem até a mesma hora.
const compareLabel = computed(() =>
  t(`FINTURE_HOME.KPI.VS_${(data.value?.period?.key || '7').toUpperCase()}`)
);

// "3 ganhas · 1 sem valor": o volume só soma quem tem valor_potencial.
const dealHint = (key, deals) => {
  if (!deals) return '';
  const count = t(
    `FINTURE_HOME.HIGHLIGHTS.${key}_COUNT`,
    { count: nf.format(deals.count) },
    deals.count
  );
  if (!deals.without_value) return count;
  const missing = t(
    'FINTURE_HOME.HIGHLIGHTS.WITHOUT_VALUE',
    { count: deals.without_value },
    deals.without_value
  );
  return `${count} · ${missing}`;
};

// ---- 1º contato humano ------------------------------------------------------
// Escala comum a todas as barras, sempre com folga para a linha da meta caber.
const sla = computed(() => data.value?.sla || {});
const slaScale = computed(() => {
  const target = sla.value.target_minutes || 0;
  const minutes = (sla.value.by_product || []).map(row => row.minutes || 0);
  return Math.max(target * 1.25, ...minutes, 1);
});
const slaTargetPct = computed(() =>
  Math.round(((sla.value.target_minutes || 0) / slaScale.value) * 100)
);
const slaRows = computed(() =>
  (sla.value.by_product || []).map(row => ({
    ...row,
    width:
      row.minutes == null
        ? 0
        : Math.max(2, Math.round((row.minutes / slaScale.value) * 100)),
    late: row.minutes > sla.value.target_minutes,
  }))
);
const hasSlaSample = computed(() =>
  slaRows.value.some(row => row.minutes != null)
);
const slaLate = computed(
  () => sla.value.avg_minutes > sla.value.target_minutes
);

// ---- Motivos de perda -------------------------------------------------------
const lost = computed(() => data.value?.lost);
const lostRows = computed(() => {
  const total = lost.value?.total || 0;
  const rows = lost.value?.reasons || [];
  const max = Math.max(1, ...rows.map(row => row.count));
  return rows.map(row => ({
    label: row.reason
      ? lostReasonLabel(row.reason)
      : t('FINTURE_HOME.LOST.NO_REASON'),
    count: row.count,
    pct: total ? Math.round((row.count / total) * 100) : 0,
    width: Math.round((row.count / max) * 100),
  }));
});

// ---- Carga por equipe -------------------------------------------------------
const teamColumns = computed(() => [
  { key: 'online', label: t('FINTURE_HOME.TEAMS.ONLINE') },
  {
    key: 'attending',
    metric: 'attending',
    label: t('FINTURE_HOME.TEAMS.ATTENDING'),
    bar: true,
  },
  {
    key: 'unassigned',
    metric: 'unassigned',
    label: t('FINTURE_HOME.TEAMS.UNASSIGNED'),
    tone: 'crit',
  },
  {
    key: 'waiting_reply',
    metric: 'waiting_reply',
    label: t('FINTURE_HOME.TEAMS.WAITING'),
    tone: 'warn',
  },
  {
    key: 'entered',
    metric: 'entered',
    label: t('FINTURE_HOME.TEAMS.ENTERED'),
    inPeriod: true,
  },
  {
    key: 'resolved',
    metric: 'resolved',
    label: t('FINTURE_HOME.TEAMS.RESOLVED'),
    inPeriod: true,
  },
]);

const teamTotals = computed(() =>
  Object.fromEntries(
    teamColumns.value.map(column => [
      column.key,
      (data.value?.teams || []).reduce((sum, row) => sum + row[column.key], 0),
    ])
  )
);

// Barra de carga: comprimento em escala comum (a equipe mais carregada = 100%).
const maxAttending = computed(() =>
  Math.max(1, ...(data.value?.teams || []).map(row => row.attending))
);
const attendingWidth = row =>
  `${Math.round((row.attending / maxAttending.value) * 100)}%`;

// ---- Opções dos filtros -----------------------------------------------------
// O CSS global força width:100% e margin-bottom nos selects (ver SdrDashboard).
const selectClass =
  'h-8 w-auto max-w-[15rem] !my-0 pl-3 pr-8 text-[13px] rounded-lg bg-n-solid-1 text-n-slate-12 outline outline-1 -outline-offset-1 outline-n-weak cursor-pointer transition-colors hover:outline-n-slate-6 focus:outline-n-brand';

const periodOptions = computed(() => [
  { value: 'today', label: t('FINTURE_HOME.FILTERS.PERIOD_TODAY') },
  { value: '7', label: t('FINTURE_HOME.FILTERS.PERIOD_7') },
  { value: '30', label: t('FINTURE_HOME.FILTERS.PERIOD_30') },
]);

const cardClass =
  'flex flex-col gap-3 p-4 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak';
const groupLabelClass =
  'text-[11px] font-medium tracking-wide uppercase text-n-slate-10';
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header
      class="flex flex-wrap items-center justify-between flex-shrink-0 gap-3 px-6 py-2.5 border-b border-n-weak"
    >
      <div class="flex flex-col">
        <h1 class="text-lg font-medium text-n-slate-12">
          {{ t('FINTURE_HOME.HEADER_TITLE') }}
        </h1>
        <span class="text-xs text-n-slate-11">
          {{ t('FINTURE_HOME.HEADER_SUBTITLE') }}
        </span>
      </div>
      <div class="flex items-center gap-3">
        <span v-if="updatedLabel" class="text-xs text-n-slate-11">
          {{ updatedLabel }}
        </span>
        <Button
          icon="i-lucide-refresh-cw"
          :label="t('FINTURE_HOME.REFRESH')"
          size="sm"
          variant="faded"
          color="slate"
          :is-loading="isLoading"
          @click="load"
        />
      </div>
    </header>

    <div class="flex flex-col flex-1 min-h-0 gap-6 px-6 py-5 overflow-y-auto">
      <!-- Filtros -->
      <div class="flex flex-wrap items-center gap-2">
        <select v-model="inboxId" :class="selectClass">
          <option value="">{{ t('FINTURE_HOME.FILTERS.ALL_INBOXES') }}</option>
          <option
            v-for="inbox in inboxes"
            :key="inbox.id"
            :value="String(inbox.id)"
          >
            {{ inbox.name }}
          </option>
        </select>
        <select v-model="purpose" :class="selectClass">
          <option value="">
            {{ t('FINTURE_HOME.FILTERS.ALL_PURPOSES') }}
          </option>
          <option value="comercial">
            {{ t('FINTURE_HOME.FILTERS.PURPOSE_COMMERCIAL') }}
          </option>
          <option value="operacional">
            {{ t('FINTURE_HOME.FILTERS.PURPOSE_OPERATIONAL') }}
          </option>
        </select>
        <select v-model="teamId" :class="selectClass">
          <option value="">{{ t('FINTURE_HOME.FILTERS.ALL_TEAMS') }}</option>
          <option v-for="team in teams" :key="team.id" :value="String(team.id)">
            {{ team.name }}
          </option>
          <option value="none">{{ t('FINTURE_HOME.FILTERS.NO_TEAM') }}</option>
        </select>
        <div
          class="inline-flex gap-0.5 p-0.5 ml-auto rounded-lg bg-n-alpha-1 outline outline-1 -outline-offset-1 outline-n-weak"
          role="tablist"
        >
          <button
            v-for="option in periodOptions"
            :key="option.value"
            type="button"
            role="tab"
            :aria-selected="period === option.value"
            class="px-3 py-1 text-[13px] font-medium rounded-md transition-colors"
            :class="
              period === option.value
                ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                : 'text-n-slate-11 hover:text-n-slate-12'
            "
            @click="period = option.value"
          >
            {{ option.label }}
          </button>
        </div>
      </div>

      <!-- Estados: carregando (1ª vez) / erro sem dados -->
      <div v-if="!data && isLoading" class="flex justify-center py-16">
        <Spinner class="size-6" />
      </div>
      <div
        v-else-if="!data && hasError"
        class="flex flex-col items-center gap-3 py-16 text-sm text-n-slate-11"
      >
        <Icon icon="i-lucide-cloud-off" class="size-6 text-n-slate-10" />
        {{ t('FINTURE_HOME.ERROR') }}
        <Button
          :label="t('FINTURE_HOME.RETRY')"
          size="sm"
          variant="faded"
          color="slate"
          @click="load"
        />
      </div>

      <div
        v-else-if="data"
        class="flex flex-col gap-8 transition-opacity"
        :class="{ 'opacity-60': isLoading }"
      >
        <p
          v-if="hasError"
          class="px-3 py-2 text-xs rounded-lg text-n-ruby-11 bg-n-ruby-3"
        >
          {{ t('FINTURE_HOME.ERROR') }}
        </p>

        <!-- 1. Resumo: período (comparado ao anterior) | agora -->
        <HomeSection
          :title="t('FINTURE_HOME.HIGHLIGHTS.TITLE')"
          :note="
            t('FINTURE_HOME.HIGHLIGHTS.NOTE', {
              since: fmtDateTime(data.period.since),
            })
          "
        >
          <div class="grid gap-x-6 gap-y-4 xl:grid-cols-[3fr_2fr]">
            <div class="flex flex-col gap-2">
              <span :class="groupLabelClass">
                {{ t('FINTURE_HOME.HIGHLIGHTS.GROUP_PERIOD') }}
              </span>
              <div class="grid flex-1 gap-3 sm:grid-cols-3">
                <HomeKpi
                  :label="t('FINTURE_HOME.HIGHLIGHTS.ENTERED')"
                  :value="highlights.entered"
                  icon="i-lucide-message-square-plus"
                  :hint="t('FINTURE_HOME.HIGHLIGHTS.ENTERED_HINT')"
                  :previous="previous.entered"
                  :compare-label="compareLabel"
                  @open="
                    openList('entered', t('FINTURE_HOME.HIGHLIGHTS.ENTERED'))
                  "
                />
                <HomeKpi
                  :label="t('FINTURE_HOME.HIGHLIGHTS.RESOLVED')"
                  :value="highlights.resolved"
                  icon="i-lucide-circle-check"
                  :hint="t('FINTURE_HOME.HIGHLIGHTS.RESOLVED_HINT')"
                  :previous="previous.resolved"
                  :compare-label="compareLabel"
                  @open="
                    openList('resolved', t('FINTURE_HOME.HIGHLIGHTS.RESOLVED'))
                  "
                />
                <HomeKpi
                  :label="t('FINTURE_HOME.HIGHLIGHTS.WON')"
                  :value="won ? won.value : null"
                  format="currency"
                  icon="i-lucide-trophy"
                  :hint="dealHint('WON', won)"
                  :previous="previous.won_value"
                  :compare-label="compareLabel"
                  :unavailable-reason="
                    t('FINTURE_HOME.HIGHLIGHTS.NOT_COMMERCIAL')
                  "
                  @open="openList('won', t('FINTURE_HOME.HIGHLIGHTS.WON_LIST'))"
                />
              </div>
            </div>
            <div class="flex flex-col gap-2">
              <span :class="groupLabelClass">
                {{ t('FINTURE_HOME.HIGHLIGHTS.GROUP_NOW') }}
              </span>
              <div class="grid flex-1 gap-3 sm:grid-cols-2">
                <HomeKpi
                  :label="t('FINTURE_HOME.HIGHLIGHTS.PIPELINE')"
                  :value="pipeline ? pipeline.value : null"
                  format="currency"
                  icon="i-lucide-wallet"
                  :hint="dealHint('PIPELINE', pipeline)"
                  :unavailable-reason="
                    t('FINTURE_HOME.HIGHLIGHTS.NOT_COMMERCIAL')
                  "
                  @open="
                    openList(
                      'pipeline_open',
                      t('FINTURE_HOME.HIGHLIGHTS.PIPELINE_LIST')
                    )
                  "
                />
                <HomeKpi
                  :label="t('FINTURE_HOME.HIGHLIGHTS.WITH_AI')"
                  :value="highlights.with_ai"
                  icon="i-lucide-bot"
                  :hint="t('FINTURE_HOME.HIGHLIGHTS.WITH_AI_HINT')"
                  :unavailable-reason="
                    t('FINTURE_HOME.HIGHLIGHTS.WITH_AI_UNAVAILABLE')
                  "
                  @open="
                    openList('with_ai', t('FINTURE_HOME.HIGHLIGHTS.WITH_AI'))
                  "
                />
              </div>
            </div>
          </div>
        </HomeSection>

        <!-- 2. Chegadas x resoluções no tempo -->
        <HomeSection
          :title="t('FINTURE_HOME.TREND.TITLE')"
          :note="
            data.series.granularity === 'hour'
              ? t('FINTURE_HOME.TREND.NOTE_HOUR')
              : t('FINTURE_HOME.TREND.NOTE_DAY')
          "
        >
          <HomeTrendChart :series="data.series" />
        </HomeSection>

        <!-- 3. Carga por equipe (mesmos times do wallboard) -->
        <HomeSection
          :title="t('FINTURE_HOME.TEAMS.TITLE')"
          :note="t('FINTURE_HOME.TEAMS.NOTE')"
        >
          <div
            class="overflow-x-auto rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
          >
            <table class="w-full text-sm">
              <thead>
                <tr class="text-xs text-left align-bottom text-n-slate-11">
                  <th class="px-4 py-2.5 font-medium">
                    {{ t('FINTURE_HOME.TEAMS.TEAM') }}
                  </th>
                  <th
                    v-for="column in teamColumns"
                    :key="column.key"
                    class="px-4 py-2.5 font-medium text-right"
                  >
                    {{ column.label }}
                    <em
                      v-if="column.inPeriod"
                      class="block not-italic text-n-slate-10"
                    >
                      {{ t('FINTURE_HOME.TEAMS.IN_PERIOD') }}
                    </em>
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr v-if="!data.teams.length">
                  <td
                    :colspan="teamColumns.length + 1"
                    class="px-4 py-6 text-center text-n-slate-11"
                  >
                    {{ t('FINTURE_HOME.TEAMS.EMPTY') }}
                  </td>
                </tr>
                <tr v-for="row in data.teams" :key="row.team_id">
                  <td class="px-4 py-2 font-medium text-n-slate-12">
                    {{ row.name }}
                  </td>
                  <td
                    v-for="column in teamColumns"
                    :key="column.key"
                    class="px-4 py-1.5 text-right tabular-nums whitespace-nowrap"
                  >
                    <div class="flex items-center justify-end gap-2">
                      <span
                        v-if="
                          column.key === 'waiting_reply' &&
                          row.oldest_waiting_since
                        "
                        class="text-[11px] text-n-slate-10"
                        :title="t('FINTURE_HOME.TEAMS.OLDEST_TITLE')"
                      >
                        {{
                          t('FINTURE_HOME.TEAMS.OLDEST', {
                            time: fmtElapsed(
                              row.oldest_waiting_since,
                              generatedAt
                            ),
                          })
                        }}
                      </span>
                      <span
                        v-if="column.bar"
                        class="w-16 h-1.5 rounded-full bg-n-alpha-2"
                        aria-hidden="true"
                      >
                        <span
                          v-if="row.attending"
                          class="block h-1.5 rounded-full bg-n-slate-10"
                          :style="{ width: attendingWidth(row) }"
                        />
                      </span>
                      <button
                        v-if="column.metric && row[column.key] > 0"
                        type="button"
                        class="min-w-8 px-2 py-1 font-medium transition-colors rounded-md hover:bg-n-alpha-2"
                        :class="{
                          'text-n-ruby-11': column.tone === 'crit',
                          'text-n-amber-11': column.tone === 'warn',
                          'text-n-slate-12': !column.tone,
                        }"
                        @click="
                          openList(
                            column.metric,
                            `${column.label} · ${row.name}`,
                            { team_id: row.team_id }
                          )
                        "
                      >
                        {{ nf.format(row[column.key]) }}
                      </button>
                      <span
                        v-else
                        class="min-w-8 px-2"
                        :class="
                          row[column.key] ? 'text-n-slate-12' : 'text-n-slate-8'
                        "
                      >
                        {{ nf.format(row[column.key]) }}
                      </span>
                    </div>
                  </td>
                </tr>
              </tbody>
              <tfoot v-if="data.teams.length > 1">
                <tr class="font-medium border-t border-n-weak text-n-slate-12">
                  <td class="px-4 py-2.5">
                    {{ t('FINTURE_HOME.TEAMS.TOTAL') }}
                  </td>
                  <td
                    v-for="column in teamColumns"
                    :key="column.key"
                    class="px-6 py-2.5 text-right tabular-nums"
                  >
                    {{ nf.format(teamTotals[column.key]) }}
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
        </HomeSection>

        <div class="grid gap-8 xl:grid-cols-2">
          <!-- 4. 1º contato humano: barras por equipe com a linha da meta -->
          <HomeSection
            :title="t('FINTURE_HOME.SLA.TITLE')"
            :note="t('FINTURE_HOME.SLA.NOTE')"
          >
            <div :class="cardClass">
              <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span
                  v-if="sla.avg_minutes != null"
                  class="text-[28px] font-semibold leading-none tracking-tight tabular-nums"
                  :class="slaLate ? 'text-n-ruby-11' : 'text-n-slate-12'"
                >
                  {{
                    t('FINTURE_HOME.SLA.MINUTES', { count: sla.avg_minutes })
                  }}
                </span>
                <span
                  v-if="sla.avg_minutes != null"
                  class="flex items-center gap-1 text-xs font-medium"
                  :class="slaLate ? 'text-n-ruby-11' : 'text-n-teal-11'"
                >
                  <Icon
                    :icon="
                      slaLate
                        ? 'i-lucide-triangle-alert'
                        : 'i-lucide-circle-check'
                    "
                    class="size-3.5"
                  />
                  {{
                    slaLate
                      ? t('FINTURE_HOME.SLA.ABOVE_TARGET')
                      : t('FINTURE_HOME.SLA.WITHIN_TARGET')
                  }}
                </span>
                <span class="text-xs text-n-slate-10">
                  {{
                    t('FINTURE_HOME.SLA.HINT', { target: sla.target_minutes })
                  }}
                  ·
                  {{
                    t('FINTURE_HOME.SLA.SAMPLE', {
                      measured: sla.measured || 0,
                      total: sla.total || 0,
                    })
                  }}
                </span>
              </div>

              <ul v-if="hasSlaSample" class="flex flex-col gap-2.5">
                <li
                  v-for="row in slaRows"
                  :key="row.product"
                  class="grid items-center grid-cols-[8rem_1fr_7.5rem] gap-3 text-xs"
                >
                  <span class="truncate text-n-slate-12">{{
                    row.product
                  }}</span>
                  <span class="relative h-2.5 rounded-full bg-n-alpha-2">
                    <span
                      v-if="row.width"
                      class="block h-2.5 rounded-full"
                      :class="row.late ? 'bg-n-ruby-9' : 'bg-n-slate-10'"
                      :style="{ width: `${row.width}%` }"
                    />
                    <span
                      class="absolute border-l border-dashed -top-1 -bottom-1 border-n-slate-11"
                      :style="{ left: `${slaTargetPct}%` }"
                      aria-hidden="true"
                    />
                  </span>
                  <span class="text-right tabular-nums">
                    <template v-if="row.minutes != null">
                      <span
                        class="font-medium"
                        :class="row.late ? 'text-n-ruby-11' : 'text-n-slate-12'"
                      >
                        {{
                          t('FINTURE_HOME.SLA.MINUTES', { count: row.minutes })
                        }}
                      </span>
                      <Icon
                        v-if="row.late"
                        icon="i-lucide-triangle-alert"
                        class="inline-block ml-1 align-[-2px] size-3 text-n-ruby-11"
                        :aria-label="t('FINTURE_HOME.SLA.ABOVE_TARGET')"
                        role="img"
                      />
                      <span class="text-n-slate-10">
                        · {{ row.measured }}/{{ row.total }}
                      </span>
                    </template>
                    <span v-else class="text-n-slate-10">
                      {{ t('FINTURE_HOME.SLA.NOT_MEASURED') }}
                    </span>
                  </span>
                </li>
                <li
                  class="grid grid-cols-[8rem_1fr_7.5rem] gap-3 text-[11px] text-n-slate-10"
                  aria-hidden="true"
                >
                  <span />
                  <span class="relative h-3">
                    <span
                      class="absolute -translate-x-1/2 whitespace-nowrap"
                      :style="{ left: `${slaTargetPct}%` }"
                    >
                      {{
                        t('FINTURE_HOME.SLA.TARGET_LINE', {
                          target: sla.target_minutes,
                        })
                      }}
                    </span>
                  </span>
                </li>
              </ul>
              <p v-else class="py-4 text-sm text-center text-n-slate-11">
                {{ t('FINTURE_HOME.SLA.NO_SAMPLE') }}
              </p>
            </div>
          </HomeSection>

          <!-- 5. Motivos de perda (perdidos no período) -->
          <HomeSection
            v-if="lost"
            :title="t('FINTURE_HOME.LOST.TITLE')"
            :note="t('FINTURE_HOME.LOST.NOTE')"
          >
            <div :class="cardClass">
              <div class="flex items-baseline justify-between gap-3">
                <span class="text-sm text-n-slate-12">
                  {{
                    t(
                      'FINTURE_HOME.LOST.TOTAL',
                      { count: lost.total },
                      lost.total
                    )
                  }}
                </span>
                <Button
                  v-if="lost.total"
                  :label="t('FINTURE_HOME.LOST.OPEN_LIST')"
                  size="xs"
                  variant="link"
                  color="slate"
                  @click="openList('lost', t('FINTURE_HOME.LOST.LIST_TITLE'))"
                />
              </div>
              <ul v-if="lostRows.length" class="flex flex-col gap-2.5">
                <li
                  v-for="row in lostRows"
                  :key="row.label"
                  class="flex flex-col gap-1 text-xs"
                >
                  <span class="flex justify-between gap-3">
                    <span class="truncate text-n-slate-12">{{
                      row.label
                    }}</span>
                    <span class="tabular-nums text-n-slate-11">
                      <span class="font-medium text-n-slate-12">{{
                        row.count
                      }}</span>
                      · {{ row.pct }}%
                    </span>
                  </span>
                  <span class="h-2 rounded-full bg-n-alpha-2">
                    <span
                      class="block h-2 rounded-full bg-n-slate-10"
                      :style="{ width: `${row.width}%` }"
                    />
                  </span>
                </li>
              </ul>
              <p v-else class="py-4 text-sm text-center text-n-slate-11">
                {{ t('FINTURE_HOME.LOST.EMPTY') }}
              </p>
            </div>
          </HomeSection>
        </div>
      </div>
    </div>

    <HomeDrilldownDialog ref="drilldownRef" />
  </section>
</template>
