<script setup>
// Chegadas x resoluções por dia (por hora no período "hoje"). Barras agrupadas
// no mesmo eixo, começando do zero: a comparação é por posição/comprimento.
// O BarChart (chart.js) é o mesmo dos Relatórios do Chatwoot; como o canvas
// não é lido por leitor de tela, a tabela escondida repete os números.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BarChart from 'shared/components/charts/BarChart.vue';
import { fmtDate, fmtHour, fmtWeekday, themeColor } from '../helpers';

const props = defineProps({
  series: { type: Object, required: true },
});

const { t } = useI18n();

const points = computed(() => props.series.points || []);
const hourly = computed(() => props.series.granularity === 'hour');
const label = point => (hourly.value ? fmtHour(point.at) : fmtDate(point.at));
const tooltipTitle = point =>
  hourly.value ? fmtHour(point.at) : fmtWeekday(point.at);

const legend = computed(() => [
  {
    key: 'entered',
    label: t('FINTURE_HOME.TREND.ENTERED'),
    swatch: 'bg-n-brand',
    color: themeColor('brand'),
  },
  {
    key: 'resolved',
    label: t('FINTURE_HOME.TREND.RESOLVED'),
    swatch: 'bg-n-slate-10',
    color: themeColor('slate-10'),
  },
]);

const collection = computed(() => ({
  labels: points.value.map(label),
  datasets: legend.value.map(item => ({
    label: item.label,
    data: points.value.map(point => point[item.key]),
    backgroundColor: item.color,
    borderRadius: 3,
    barPercentage: 0.9,
    categoryPercentage: hourly.value ? 0.8 : 0.7,
  })),
}));

const chartOptions = computed(() => {
  const tick = { color: themeColor('slate-11'), font: { size: 11 } };
  return {
    scales: {
      x: {
        ticks: { ...tick, maxRotation: 0, autoSkipPadding: 8 },
        grid: { display: false },
      },
      y: {
        beginAtZero: true,
        ticks: { ...tick, precision: 0, maxTicksLimit: 5 },
        grid: { color: themeColor('slate-6', 0.6) },
        border: { display: false },
      },
    },
    plugins: {
      tooltip: {
        callbacks: {
          title: items => tooltipTitle(points.value[items[0].dataIndex]),
        },
      },
    },
  };
});

const totals = computed(() => ({
  entered: points.value.reduce((sum, point) => sum + point.entered, 0),
  resolved: points.value.reduce((sum, point) => sum + point.resolved, 0),
}));

// A legenda do gráfico diz o "o quê"; esta linha diz o "e daí": o pico de
// chegadas e se o período fechou com saldo (chegou mais do que resolveu).
const isEmpty = computed(() => !totals.value.entered && !totals.value.resolved);

const insight = computed(() => {
  if (isEmpty.value) return t('FINTURE_HOME.TREND.EMPTY');
  const peak = points.value.reduce((best, point) =>
    point.entered > best.entered ? point : best
  );
  const parts = [];
  if (peak.entered)
    parts.push(
      t('FINTURE_HOME.TREND.PEAK', {
        when: tooltipTitle(peak),
        count: peak.entered,
      })
    );
  const balance = totals.value.entered - totals.value.resolved;
  if (balance > 0)
    parts.push(t('FINTURE_HOME.TREND.BACKLOG_UP', { count: balance }));
  else if (balance < 0)
    parts.push(t('FINTURE_HOME.TREND.BACKLOG_DOWN', { count: -balance }));
  return parts.join(' · ');
});
</script>

<template>
  <div
    class="flex flex-col gap-3 p-4 rounded-xl bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak"
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="text-sm text-n-slate-12">{{ insight }}</p>
      <ul
        v-if="!isEmpty"
        class="flex items-center gap-4 text-xs text-n-slate-11"
      >
        <li
          v-for="item in legend"
          :key="item.key"
          class="flex items-center gap-1.5"
        >
          <span class="rounded-sm size-2.5" :class="item.swatch" />
          {{ item.label }}
          <span class="font-medium tabular-nums text-n-slate-12">
            {{ totals[item.key] }}
          </span>
        </li>
      </ul>
    </div>
    <div v-if="!isEmpty" class="h-56" aria-hidden="true">
      <BarChart :collection="collection" :chart-options="chartOptions" />
    </div>
    <table v-if="!isEmpty" class="sr-only">
      <caption>
        {{
          t('FINTURE_HOME.TREND.TITLE')
        }}
      </caption>
      <thead>
        <tr>
          <th scope="col">{{ t('FINTURE_HOME.TREND.WHEN') }}</th>
          <th v-for="item in legend" :key="item.key" scope="col">
            {{ item.label }}
          </th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="point in points" :key="point.at">
          <th scope="row">{{ tooltipTitle(point) }}</th>
          <td>{{ point.entered }}</td>
          <td>{{ point.resolved }}</td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
