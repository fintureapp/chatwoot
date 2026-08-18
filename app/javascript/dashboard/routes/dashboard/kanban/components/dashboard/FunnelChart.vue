<script setup>
// Funil de conversão do Dashboard SDR: cada etapa como barra proporcional ao
// topo, com a taxa de passagem entre etapas. Duas cores só: azul de acento nas
// etapas e teal no nó final (Ganho).
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  // [{ slug, name, count }] — vindo do backend (SdrCommercialReportService#funnel)
  nodes: { type: Array, required: true },
});

const rows = computed(() => {
  const top = Math.max(1, props.nodes[0]?.count || 1);
  return props.nodes.map((node, index) => {
    const previous = index ? props.nodes[index - 1].count : null;
    return {
      ...node,
      width: Math.max(14, (node.count / top) * 100),
      conv:
        index && previous ? Math.round((node.count / previous) * 100) : null,
      isWon: node.slug === 'ganho',
    };
  });
});
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <template v-for="(row, index) in rows" :key="row.slug">
      <div
        v-if="index && row.conv !== null"
        class="flex items-center gap-1.5 pl-3 py-0.5 text-[11px] text-n-slate-11"
      >
        <Icon icon="i-lucide-corner-down-right" class="size-3 text-n-slate-9" />
        <span class="font-semibold text-n-teal-11">{{ `${row.conv}%` }}</span>
        {{ $t('KANBAN.DASHBOARD.FUNNEL_ADVANCED_SUFFIX') }}
      </div>
      <div class="flex flex-col gap-1">
        <div class="flex items-baseline justify-between text-[13px]">
          <span class="text-n-slate-12">{{ row.name }}</span>
          <span class="font-semibold text-n-slate-12 tabular-nums">{{
            row.count
          }}</span>
        </div>
        <div
          class="h-8 rounded-lg min-w-[52px] transition-[width] duration-500"
          :class="row.isWon ? 'bg-n-teal-9' : 'bg-n-blue-9'"
          :style="{ width: `${row.width}%` }"
        />
      </div>
    </template>
  </div>
</template>
