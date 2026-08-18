<script setup>
// Barra empilhada da idade dos leads em aberto (aging). Cores = status: teal
// (fresco), amber (atenção), ruby (velho). Números na legenda para não brigar
// com o contraste do texto sobre a barra.
import { computed } from 'vue';

const props = defineProps({
  fresh: { type: Number, default: 0 }, // 0–3 dias
  warm: { type: Number, default: 0 }, // 4–7 dias
  stale: { type: Number, default: 0 }, // +7 dias
});

const total = computed(() =>
  Math.max(1, (props.fresh || 0) + (props.warm || 0) + (props.stale || 0))
);
const width = value => `${((value || 0) / total.value) * 100}%`;
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex h-6 gap-0.5 overflow-hidden rounded-lg bg-n-alpha-1">
      <div
        v-if="fresh"
        class="h-full bg-n-teal-9"
        :style="{ width: width(fresh) }"
      />
      <div
        v-if="warm"
        class="h-full bg-n-amber-9"
        :style="{ width: width(warm) }"
      />
      <div
        v-if="stale"
        class="h-full bg-n-ruby-9"
        :style="{ width: width(stale) }"
      />
    </div>
    <div class="flex flex-wrap gap-4 text-[12.5px] text-n-slate-11">
      <span class="inline-flex items-center gap-1.5">
        <span class="rounded-sm size-2.5 bg-n-teal-9" />
        {{ $t('KANBAN.DASHBOARD.AGING_FRESH') }}
        <b class="text-n-slate-12 tabular-nums">{{ fresh }}</b>
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="rounded-sm size-2.5 bg-n-amber-9" />
        {{ $t('KANBAN.DASHBOARD.AGING_WARM') }}
        <b class="text-n-slate-12 tabular-nums">{{ warm }}</b>
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span class="rounded-sm size-2.5 bg-n-ruby-9" />
        {{ $t('KANBAN.DASHBOARD.AGING_STALE') }}
        <b class="text-n-slate-12 tabular-nums">{{ stale }}</b>
      </span>
    </div>
  </div>
</template>
