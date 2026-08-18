<script setup>
// Tendência do Dashboard SDR: leads e ganhos ao longo do período (linha), com a
// linha tracejada = leads da janela de comparação. Cores por token Radix do
// Chatwoot (rgb(var(--…))), então o dark mode acompanha sozinho.
import { computed, ref } from 'vue';

const props = defineProps({
  // { unit, buckets: [{ label, leads, ganhos }], compare: [{ label, leads }] }
  series: { type: Object, required: true },
  compareLabel: { type: String, default: 'período anterior' },
});

const W = 720;
const H = 250;
const PL = 34;
const PR = 18;
const PT = 14;
const PB = 26;

const buckets = computed(() => props.series?.buckets || []);
const compare = computed(() => props.series?.compare || []);
const n = computed(() => buckets.value.length);

const maxV = computed(() => {
  const values = [
    ...buckets.value.flatMap(b => [b.leads, b.ganhos]),
    ...compare.value.map(c => c.leads),
  ];
  return Math.max(20, Math.ceil(Math.max(1, ...values) / 20) * 20);
});

const xAt = i => PL + (W - PL - PR) * (n.value <= 1 ? 0.5 : i / (n.value - 1));
const yAt = v => H - PB - ((H - PB - PT) * v) / maxV.value;
const toLine = arr =>
  arr
    .map((v, i) => `${i ? 'L' : 'M'}${xAt(i).toFixed(1)} ${yAt(v).toFixed(1)}`)
    .join(' ');

const leadsPath = computed(() => toLine(buckets.value.map(b => b.leads)));
const ganhosPath = computed(() => toLine(buckets.value.map(b => b.ganhos)));
const comparePath = computed(() =>
  compare.value.length ? toLine(compare.value.map(c => c.leads)) : ''
);
const areaPath = computed(() =>
  n.value
    ? `${leadsPath.value} L${xAt(n.value - 1).toFixed(1)} ${H - PB} L${PL} ${H - PB} Z`
    : ''
);

const gridLines = computed(() =>
  [0, 1, 2, 3, 4].map(k => {
    const v = (maxV.value * k) / 4;
    return { v, y: yAt(v) };
  })
);

// Rótulos do eixo X sem poluir: no máximo ~8 marcas.
const xLabels = computed(() => {
  const step = Math.max(1, Math.ceil(n.value / 8));
  return buckets.value
    .map((b, i) => ({ label: b.label, x: xAt(i), i }))
    .filter(item => item.i % step === 0 || item.i === n.value - 1);
});

const endLeads = computed(() =>
  n.value ? { x: xAt(n.value - 1), y: yAt(buckets.value.at(-1).leads) } : null
);
const endGanhos = computed(() =>
  n.value ? { x: xAt(n.value - 1), y: yAt(buckets.value.at(-1).ganhos) } : null
);

// ---- Hover / tooltip ------------------------------------------------------
const wrap = ref(null);
const hover = ref(null);
const onMove = event => {
  if (!n.value || !wrap.value) return;
  const rect = wrap.value.getBoundingClientRect();
  const x = ((event.clientX - rect.left) / rect.width) * W;
  const span = (W - PL - PR) / Math.max(1, n.value - 1);
  hover.value = Math.min(n.value - 1, Math.max(0, Math.round((x - PL) / span)));
};
const onLeave = () => {
  hover.value = null;
};
const hoverBucket = computed(() =>
  hover.value == null ? null : buckets.value[hover.value]
);
const hoverCompare = computed(() =>
  hover.value == null ? null : compare.value[hover.value]
);
const hoverLeft = computed(() =>
  hover.value == null ? 0 : (xAt(hover.value) / W) * 100
);
</script>

<template>
  <div ref="wrap" class="relative" @mousemove="onMove" @mouseleave="onLeave">
    <svg
      :viewBox="`0 0 ${W} ${H}`"
      class="block w-full h-auto overflow-visible"
      role="img"
      :aria-label="$t('KANBAN.DASHBOARD.TREND_TITLE')"
    >
      <defs>
        <linearGradient id="sdrTrendArea" x1="0" y1="0" x2="0" y2="1">
          <stop
            offset="0"
            stop-color="rgb(var(--blue-9))"
            stop-opacity="0.16"
          />
          <stop offset="1" stop-color="rgb(var(--blue-9))" stop-opacity="0" />
        </linearGradient>
      </defs>

      <!-- grade -->
      <g>
        <line
          v-for="g in gridLines"
          :key="g.v"
          :x1="PL"
          :y1="g.y.toFixed(1)"
          :x2="W - PR"
          :y2="g.y.toFixed(1)"
          stroke="rgb(var(--slate-4))"
          stroke-width="1"
        />
        <text
          v-for="g in gridLines"
          :key="`t-${g.v}`"
          :x="PL - 6"
          :y="(g.y - 3).toFixed(1)"
          text-anchor="end"
          fill="rgb(var(--slate-10))"
          font-size="11"
        >
          {{ g.v }}
        </text>
      </g>

      <!-- rótulos eixo X -->
      <text
        v-for="l in xLabels"
        :key="`x-${l.i}`"
        :x="l.x.toFixed(1)"
        :y="H - 8"
        text-anchor="middle"
        fill="rgb(var(--slate-10))"
        font-size="11"
      >
        {{ l.label }}
      </text>

      <!-- área + linhas -->
      <path :d="areaPath" fill="url(#sdrTrendArea)" />
      <path
        v-if="comparePath"
        :d="comparePath"
        fill="none"
        stroke="rgb(var(--slate-8))"
        stroke-width="2"
        stroke-dasharray="3 5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        :d="leadsPath"
        fill="none"
        stroke="rgb(var(--blue-9))"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
      <path
        :d="ganhosPath"
        fill="none"
        stroke="rgb(var(--teal-9))"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />

      <!-- linha de hover -->
      <line
        v-if="hover != null"
        :x1="xAt(hover).toFixed(1)"
        :y1="PT"
        :x2="xAt(hover).toFixed(1)"
        :y2="H - PB"
        stroke="rgb(var(--slate-6))"
        stroke-width="1"
      />

      <!-- extremidades -->
      <circle
        v-if="endLeads"
        :cx="endLeads.x.toFixed(1)"
        :cy="endLeads.y.toFixed(1)"
        r="4.5"
        fill="rgb(var(--blue-9))"
        stroke="rgb(var(--solid-1))"
        stroke-width="2"
      />
      <circle
        v-if="endGanhos"
        :cx="endGanhos.x.toFixed(1)"
        :cy="endGanhos.y.toFixed(1)"
        r="4.5"
        fill="rgb(var(--teal-9))"
        stroke="rgb(var(--solid-1))"
        stroke-width="2"
      />
    </svg>

    <!-- tooltip -->
    <div
      v-if="hoverBucket"
      class="absolute z-10 px-2.5 py-2 -translate-x-1/2 rounded-lg pointer-events-none bg-n-solid-1 outline outline-1 outline-n-strong shadow-lg top-1"
      :style="{ left: `${hoverLeft}%` }"
    >
      <div class="text-xs font-semibold text-n-slate-12 mb-1 whitespace-nowrap">
        {{ hoverBucket.label }}
      </div>
      <div
        class="flex items-center gap-2 text-xs whitespace-nowrap text-n-slate-11"
      >
        <span class="inline-block rounded-sm size-2 bg-n-blue-9" />
        {{ $t('KANBAN.DASHBOARD.TREND_LEADS') }}
        <b class="ml-auto text-n-slate-12">{{ hoverBucket.leads }}</b>
      </div>
      <div
        class="flex items-center gap-2 text-xs whitespace-nowrap text-n-slate-11"
      >
        <span class="inline-block rounded-sm size-2 bg-n-teal-9" />
        {{ $t('KANBAN.DASHBOARD.TREND_GAINS') }}
        <b class="ml-auto text-n-slate-12">{{ hoverBucket.ganhos }}</b>
      </div>
      <div
        v-if="hoverCompare"
        class="flex items-center gap-2 text-xs whitespace-nowrap text-n-slate-11"
      >
        <span class="inline-block rounded-sm size-2 bg-n-slate-8" />
        {{ $t('KANBAN.DASHBOARD.TREND_COMPARE') }}
        <b class="ml-auto text-n-slate-12">{{ hoverCompare.leads }}</b>
      </div>
    </div>

    <!-- legenda -->
    <div
      class="flex flex-wrap gap-x-4 gap-y-1 mt-3 text-[12.5px] text-n-slate-11"
    >
      <span class="inline-flex items-center gap-1.5">
        <span class="inline-block rounded-sm size-2.5 bg-n-blue-9" />
        {{ $t('KANBAN.DASHBOARD.TREND_LEADS') }}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="inline-block rounded-sm size-2.5 bg-n-teal-9" />
        {{ $t('KANBAN.DASHBOARD.TREND_GAINS') }}
      </span>
      <span v-if="compare.length" class="inline-flex items-center gap-1.5">
        <span class="inline-block rounded-sm size-2.5 bg-n-slate-8" />
        {{
          $t('KANBAN.DASHBOARD.TREND_COMPARE_LEGEND', { label: compareLabel })
        }}
      </span>
    </div>
  </div>
</template>
