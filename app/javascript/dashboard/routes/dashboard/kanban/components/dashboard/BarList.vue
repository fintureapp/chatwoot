<script setup>
// Lista de barras horizontais reutilizável (Mix, Perdas, Velocidade, SLA…).
// Paleta enxuta alinhada ao Chatwoot: um único tom por lista; o rótulo carrega a
// identidade (não dependemos de cor para diferenciar itens).
import { computed } from 'vue';

const props = defineProps({
  // [{ label, value: Number, display: String, sub?: String }]
  rows: { type: Array, required: true },
  tone: { type: String, default: 'brand' }, // brand | teal | ruby | slate
});

const max = computed(() =>
  Math.max(1, ...props.rows.map(row => Number(row.value) || 0))
);

const fillClass = computed(
  () =>
    ({
      brand: 'bg-n-blue-9',
      teal: 'bg-n-teal-9',
      ruby: 'bg-n-ruby-8',
      slate: 'bg-n-slate-9',
    })[props.tone] || 'bg-n-blue-9'
);
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-for="row in rows"
      :key="row.label"
      class="grid grid-cols-[minmax(88px,132px)_1fr_auto] items-center gap-3"
    >
      <span class="text-[13px] text-n-slate-12 truncate" :title="row.label">{{
        row.label
      }}</span>
      <div class="h-3 overflow-hidden rounded-full bg-n-alpha-2">
        <div
          class="h-full rounded-full"
          :class="fillClass"
          :style="{ width: `${Math.max(4, (row.value / max) * 100)}%` }"
        />
      </div>
      <span
        class="text-[13px] font-semibold text-right text-n-slate-12 tabular-nums min-w-[60px]"
      >
        {{ row.display }}
        <span v-if="row.sub" class="ml-1.5 font-normal text-n-slate-10">{{
          row.sub
        }}</span>
      </span>
    </div>
  </div>
</template>
