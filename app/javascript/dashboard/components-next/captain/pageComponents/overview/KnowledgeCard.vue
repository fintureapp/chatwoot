<script setup>
import { computed } from 'vue';

// Knowledge coverage (sample data).
const knowledge = {
  approved: 142,
  pending: 9,
  documents: 23,
};

const approvedPct = computed(() => {
  const total = knowledge.approved + knowledge.pending;
  return total ? Math.round((knowledge.approved / total) * 100) : 0;
});
</script>

<template>
  <div
    class="flex flex-col gap-4 p-5 border rounded-xl bg-n-solid-1 border-n-weak"
  >
    <div class="flex items-center justify-between">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('CAPTAIN.OVERVIEW.KNOWLEDGE.TITLE') }}
      </span>
      <span class="text-sm text-n-slate-11">
        {{ $t('CAPTAIN.OVERVIEW.KNOWLEDGE.COVERAGE', { pct: approvedPct }) }}
      </span>
    </div>
    <div class="w-full h-2 overflow-hidden rounded-full bg-n-alpha-2">
      <div
        class="h-full rounded-full bg-n-brand"
        :style="{ width: `${approvedPct}%` }"
      />
    </div>
    <div class="grid grid-cols-3 gap-3">
      <div class="flex flex-col gap-1">
        <span class="text-xl font-semibold text-n-slate-12">
          {{ knowledge.approved }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ $t('CAPTAIN.OVERVIEW.KNOWLEDGE.APPROVED') }}
        </span>
      </div>
      <div class="flex flex-col gap-1">
        <span class="text-xl font-semibold text-n-slate-12">
          {{ knowledge.pending }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ $t('CAPTAIN.OVERVIEW.KNOWLEDGE.PENDING') }}
        </span>
      </div>
      <div class="flex flex-col gap-1">
        <span class="text-xl font-semibold text-n-slate-12">
          {{ knowledge.documents }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ $t('CAPTAIN.OVERVIEW.KNOWLEDGE.DOCUMENTS') }}
        </span>
      </div>
    </div>
  </div>
</template>
