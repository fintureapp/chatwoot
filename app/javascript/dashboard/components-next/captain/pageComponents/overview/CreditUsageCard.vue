<script setup>
import { computed } from 'vue';

defineProps({
  // Selected day-range, used only for the chart's start-axis label.
  range: { type: String, default: '30' },
});

// Daily assistant credit usage (sample data) rendered as a lightweight bar
// chart, so we avoid pulling in a chart library for placeholder visuals.
const creditUsage = {
  total: '48,210',
  trend: '+18.2%',
  daily: [
    120, 145, 132, 160, 175, 158, 190, 210, 195, 230, 220, 245, 260, 240, 275,
    290, 270, 310, 295, 330, 350, 325, 360, 380, 355, 400, 420, 395, 440, 465,
  ],
};

// Bar heights as a percentage of the peak day, with a small floor so even the
// lowest day stays visible.
const bars = computed(() => {
  const max = Math.max(...creditUsage.daily);
  return creditUsage.daily.map((value, index) => ({
    key: index,
    value,
    height: Math.max(6, Math.round((value / max) * 100)),
  }));
});
</script>

<template>
  <section class="flex flex-col gap-4">
    <div class="flex items-start justify-between gap-4">
      <div class="flex flex-col gap-1">
        <h3 class="text-base font-medium text-n-slate-12">
          {{ $t('CAPTAIN.OVERVIEW.CREDITS.TITLE') }}
        </h3>
        <div class="flex items-baseline gap-2">
          <span class="text-2xl font-semibold tabular-nums text-n-slate-12">
            {{ creditUsage.total }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t('CAPTAIN.OVERVIEW.CREDITS.UNIT') }}
          </span>
          <span class="text-sm font-medium tabular-nums text-n-slate-11">
            {{ creditUsage.trend }}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-2 mt-1">
        <span class="rounded-full size-2.5 bg-n-brand" />
        <span class="text-xs text-n-slate-11">
          {{ $t('CAPTAIN.OVERVIEW.CREDITS.LEGEND') }}
        </span>
      </div>
    </div>

    <div class="p-5 border rounded-xl bg-n-solid-1 border-n-weak">
      <div class="flex items-end gap-1 h-40">
        <div
          v-for="bar in bars"
          :key="bar.key"
          v-tooltip="`${bar.value} ${$t('CAPTAIN.OVERVIEW.CREDITS.UNIT')}`"
          class="flex-1 rounded-t transition-colors bg-n-brand/70 hover:bg-n-brand"
          :style="{ height: `${bar.height}%` }"
        />
      </div>
      <div class="flex items-center justify-between mt-3">
        <span class="text-xs text-n-slate-10">
          {{ $t('CAPTAIN.OVERVIEW.CREDITS.AXIS_START', { count: range }) }}
        </span>
        <span class="text-xs text-n-slate-10">
          {{ $t('CAPTAIN.OVERVIEW.CREDITS.AXIS_END') }}
        </span>
      </div>
    </div>
  </section>
</template>
