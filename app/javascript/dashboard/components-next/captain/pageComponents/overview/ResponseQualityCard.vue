<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

// Flagged responses broken down by report reason, mapped from
// captain_message_reports.report_reason (sample data).
const flagReasons = [
  {
    key: 'incorrect',
    label: t('CAPTAIN.OVERVIEW.FLAG_REASONS.INCORRECT'),
    count: 11,
  },
  {
    key: 'incomplete',
    label: t('CAPTAIN.OVERVIEW.FLAG_REASONS.INCOMPLETE'),
    count: 7,
  },
  {
    key: 'outdated',
    label: t('CAPTAIN.OVERVIEW.FLAG_REASONS.OUTDATED'),
    count: 4,
  },
  {
    key: 'inappropriate',
    label: t('CAPTAIN.OVERVIEW.FLAG_REASONS.INAPPROPRIATE'),
    count: 2,
  },
  { key: 'other', label: t('CAPTAIN.OVERVIEW.FLAG_REASONS.OTHER'), count: 3 },
];

const total = computed(() =>
  flagReasons.reduce((sum, reason) => sum + reason.count, 0)
);
</script>

<template>
  <div
    class="flex flex-col gap-4 p-5 border rounded-xl bg-n-solid-1 border-n-weak"
  >
    <div class="flex items-center justify-between">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t('CAPTAIN.OVERVIEW.FLAGGED.TITLE') }}
      </span>
      <span class="text-sm text-n-slate-11">
        {{ $t('CAPTAIN.OVERVIEW.FLAGGED.TOTAL', { count: total }) }}
      </span>
    </div>
    <div class="flex flex-col gap-3">
      <div
        v-for="reason in flagReasons"
        :key="reason.key"
        class="flex items-center gap-3"
      >
        <span class="w-28 text-xs truncate text-n-slate-11 shrink-0">
          {{ reason.label }}
        </span>
        <div class="flex-1 h-2 overflow-hidden rounded-full bg-n-alpha-2">
          <div
            class="h-full rounded-full bg-n-amber-9"
            :style="{ width: `${Math.round((reason.count / total) * 100)}%` }"
          />
        </div>
        <span class="w-6 text-xs font-medium text-right text-n-slate-12">
          {{ reason.count }}
        </span>
      </div>
    </div>
  </div>
</template>
