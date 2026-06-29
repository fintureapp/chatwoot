<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import CaptainAssistant from 'dashboard/api/captain/assistant';

import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import RangeSelector from 'dashboard/components-next/captain/pageComponents/overview/RangeSelector.vue';
import WelcomeCard from 'dashboard/components-next/captain/pageComponents/overview/WelcomeCard.vue';
import MetricCard from 'dashboard/components-next/captain/pageComponents/overview/MetricCard.vue';
import KnowledgeCard from 'dashboard/components-next/captain/pageComponents/overview/KnowledgeCard.vue';
import ResponseQualityCard from 'dashboard/components-next/captain/pageComponents/overview/ResponseQualityCard.vue';
import CreditUsageCard from 'dashboard/components-next/captain/pageComponents/overview/CreditUsageCard.vue';
import QuickLinks from 'dashboard/components-next/captain/pageComponents/overview/QuickLinks.vue';
import InboxBanner from 'dashboard/components-next/captain/pageComponents/overview/InboxBanner.vue';

const { t } = useI18n();
const route = useRoute();

const selectedRange = ref('this_month');

const assistantId = computed(() => route.params.assistantId);
const stats = ref(null);

const fetchStats = async () => {
  try {
    const { data } = await CaptainAssistant.getStats({
      assistantId: assistantId.value,
      range: selectedRange.value,
    });
    stats.value = data;
  } catch {
    stats.value = null;
  }
};

watch([selectedRange, assistantId], fetchStats, { immediate: true });

// `direction` says whether a rising trend is good ('up'), bad ('down'), or
// neutral, so we can colour the delta independently of its sign.
const resolveTrendGood = (trendValue, direction) => {
  if (direction === 'neutral' || trendValue === 0) return null;
  return direction === 'up' ? trendValue > 0 : trendValue < 0;
};

const metricFor = (statKey, formatValue, direction, absoluteTrend = false) => {
  const data = stats.value?.[statKey];
  if (!data) return { value: '—', trend: '', trendGood: null };

  const sign = data.trend > 0 ? '+' : '';
  return {
    value: formatValue(data.current),
    trend: absoluteTrend ? `${sign}${data.trend}` : `${sign}${data.trend}%`,
    trendGood: resolveTrendGood(data.trend, direction),
  };
};

const metrics = computed(() => [
  {
    key: 'handled',
    label: t('CAPTAIN.OVERVIEW.METRICS.HANDLED.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.HANDLED.HINT'),
    ...metricFor('conversations_handled', v => v.toLocaleString(), 'up'),
  },
  {
    key: 'autoResolution',
    label: t('CAPTAIN.OVERVIEW.METRICS.AUTO_RESOLUTION.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.AUTO_RESOLUTION.HINT'),
    ...metricFor('auto_resolution_rate', v => `${v}%`, 'up'),
  },
  {
    key: 'handoff',
    label: t('CAPTAIN.OVERVIEW.METRICS.HANDOFF.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.HANDOFF.HINT'),
    ...metricFor('handoff_rate', v => `${v}%`, 'down'),
  },
  {
    key: 'hoursSaved',
    label: t('CAPTAIN.OVERVIEW.METRICS.HOURS_SAVED.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.HOURS_SAVED.HINT'),
    ...metricFor('hours_saved', v => `${v}h`, 'up'),
  },
  {
    key: 'reopen',
    label: t('CAPTAIN.OVERVIEW.METRICS.REOPEN.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.REOPEN.HINT'),
    ...metricFor('reopen_rate', v => `${v}%`, 'down'),
  },
  {
    key: 'depth',
    label: t('CAPTAIN.OVERVIEW.METRICS.DEPTH.LABEL'),
    hint: t('CAPTAIN.OVERVIEW.METRICS.DEPTH.HINT'),
    ...metricFor('conversation_depth', v => v.toFixed(1), 'neutral', true),
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
    <template #headerActions>
      <RangeSelector v-model="selectedRange" />
    </template>
    <template #body>
      <div class="flex flex-col gap-6">
        <InboxBanner />

        <WelcomeCard :range="selectedRange" />

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
          <KnowledgeCard :knowledge="stats?.knowledge" />
          <ResponseQualityCard />
        </div>

        <CreditUsageCard />

        <QuickLinks />
      </div>
    </template>
  </PageLayout>
</template>
