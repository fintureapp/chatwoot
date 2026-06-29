<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import MetricCard from 'dashboard/components-next/captain/pageComponents/overview/MetricCard.vue';
import KnowledgeCard from 'dashboard/components-next/captain/pageComponents/overview/KnowledgeCard.vue';
import ResponseQualityCard from 'dashboard/components-next/captain/pageComponents/overview/ResponseQualityCard.vue';
import CreditUsageCard from 'dashboard/components-next/captain/pageComponents/overview/CreditUsageCard.vue';
import QuickLinks from 'dashboard/components-next/captain/pageComponents/overview/QuickLinks.vue';

const { t } = useI18n();

// NOTE: All figures below are placeholder/sample data. There is no backend
// wiring yet; this page exists to explore the layout of the assistant overview.
const ranges = ['7', '30', '90'];
const selectedRange = ref('30');

// Headline KPI cards. `trendGood` marks whether the trend direction is a
// good outcome for the user, so we can colour the delta independently of sign.
const metrics = computed(() => [
  {
    key: 'handled',
    label: t('CAPTAIN.OVERVIEW.METRICS.HANDLED.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.HANDLED.HINT'),
    value: '1,248',
    trend: '+12.4%',
    trendGood: true,
  },
  {
    key: 'autoResolution',
    label: t('CAPTAIN.OVERVIEW.METRICS.AUTO_RESOLUTION.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.AUTO_RESOLUTION.HINT'),
    value: '63.2%',
    trend: '+4.1%',
    trendGood: true,
  },
  {
    key: 'handoff',
    label: t('CAPTAIN.OVERVIEW.METRICS.HANDOFF.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.HANDOFF.HINT'),
    value: '28.7%',
    trend: '-3.2%',
    trendGood: true,
  },
  {
    key: 'hoursSaved',
    label: t('CAPTAIN.OVERVIEW.METRICS.HOURS_SAVED.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.HOURS_SAVED.HINT'),
    value: '612h',
    trend: '+22.1%',
    trendGood: true,
  },
  {
    key: 'reopen',
    label: t('CAPTAIN.OVERVIEW.METRICS.REOPEN.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.REOPEN.HINT'),
    value: '6.5%',
    trend: '+0.8%',
    trendGood: false,
  },
  {
    key: 'depth',
    label: t('CAPTAIN.OVERVIEW.METRICS.DEPTH.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.DEPTH.HINT'),
    value: '3.4',
    trend: '+0.2',
    trendGood: null,
  },
]);
</script>

<template>
  <PageLayout
    :header-title="$t('CAPTAIN.OVERVIEW.HEADER')"
    :is-empty="false"
    :show-pagination-footer="false"
    :show-know-more="false"
    :feature-flag="FEATURE_FLAGS.CAPTAIN"
  >
    <template #body>
      <div class="flex flex-col gap-6">
        <div class="flex items-center justify-between gap-4">
          <p class="text-sm text-n-slate-11">
            {{ $t('CAPTAIN.OVERVIEW.SAMPLE_NOTICE') }}
          </p>
          <div
            class="flex items-center gap-1 p-1 rounded-lg bg-n-alpha-1 shrink-0"
          >
            <button
              v-for="range in ranges"
              :key="range"
              type="button"
              class="px-3 py-1 text-sm font-medium rounded-md transition-colors"
              :class="
                selectedRange === range
                  ? 'bg-n-solid-active text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="selectedRange = range"
            >
              {{ $t('CAPTAIN.OVERVIEW.RANGES.DAYS', { count: range }) }}
            </button>
          </div>
        </div>

        <div
          class="grid grid-cols-1 gap-px overflow-hidden border rounded-xl sm:grid-cols-2 lg:grid-cols-3 bg-n-weak border-n-weak"
        >
          <MetricCard
            v-for="metric in metrics"
            :key="metric.key"
            :label="metric.label"
            :value="metric.value"
            :trend="metric.trend"
            :hint="metric.hint"
            :trend-good="metric.trendGood"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
          <KnowledgeCard />
          <ResponseQualityCard />
        </div>

        <CreditUsageCard :range="selectedRange" />

        <QuickLinks />
      </div>
    </template>
  </PageLayout>
</template>
