<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { lostReasonLabel } from 'dashboard/routes/dashboard/kanban/config/stages';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

// Histórico dos leads fechados (ganho/perdido) da caixa ativa. Fonte: endpoint
// conversations/kanban_history (só cards com sdr_outcome). Permite reabrir.
const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
});

const store = useStore();
const { t } = useI18n();

const items = computed(() =>
  store.getters['kanban/getHistoryForInbox'](props.inboxId)
);
const uiFlags = computed(() => store.getters['kanban/getHistoryUIFlags']);

const load = () => {
  if (props.inboxId)
    store.dispatch('kanban/fetchHistory', { inboxId: props.inboxId });
};
watch(() => props.inboxId, load, { immediate: true });

const dateFormatter = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});
const currencyFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});

const contactName = record => record.meta?.sender?.name || '—';
const outcomeOf = record => record.custom_attributes?.sdr_outcome;
const isWon = record => outcomeOf(record) === 'won';

const closedAt = record => {
  const epoch = record.custom_attributes?.sdr_outcome_at;
  return epoch ? dateFormatter.format(new Date(epoch * 1000)) : '';
};

const valueOf = record => {
  const value = Number(record.custom_attributes?.valor_potencial);
  return value ? currencyFormatter.format(value) : '—';
};

const reasonOf = record =>
  isWon(record)
    ? ''
    : lostReasonLabel(record.custom_attributes?.sdr_lost_reason);

const reopen = async record => {
  try {
    await store.dispatch('kanban/reopenLead', {
      conversationId: record.id,
      inboxId: props.inboxId,
    });
  } catch {
    useAlert(t('KANBAN.ERRORS.UPDATE_OUTCOME'));
  }
};
</script>

<template>
  <div class="flex flex-col flex-1 min-h-0 px-4 py-3">
    <div class="flex items-center justify-between mb-3">
      <p class="text-sm text-n-slate-11">
        {{ t('KANBAN.HISTORY.COUNT', { count: items.length }) }}
      </p>
      <Button
        color="slate"
        variant="ghost"
        size="sm"
        icon="i-lucide-refresh-cw"
        :label="t('KANBAN.HISTORY.REFRESH')"
        :is-loading="uiFlags.isFetching"
        @click="load"
      />
    </div>

    <EmptyStateLayout
      v-if="!items.length"
      class="flex-1 min-h-0"
      :title="t('KANBAN.HISTORY.EMPTY_TITLE')"
      :subtitle="t('KANBAN.HISTORY.EMPTY_SUBTITLE')"
      :show-backdrop="false"
    />

    <div v-else class="flex-1 min-h-0 overflow-y-auto">
      <table class="w-full text-sm border-collapse">
        <thead
          class="sticky top-0 text-xs text-left bg-n-surface-1 text-n-slate-11"
        >
          <tr class="border-b border-n-weak">
            <th class="px-2 py-2 font-medium">
              {{ t('KANBAN.HISTORY.COL_LEAD') }}
            </th>
            <th class="px-2 py-2 font-medium">
              {{ t('KANBAN.HISTORY.COL_OUTCOME') }}
            </th>
            <th class="px-2 py-2 font-medium">
              {{ t('KANBAN.HISTORY.COL_VALUE') }}
            </th>
            <th class="px-2 py-2 font-medium">
              {{ t('KANBAN.HISTORY.COL_REASON') }}
            </th>
            <th class="px-2 py-2 font-medium">
              {{ t('KANBAN.HISTORY.COL_DATE') }}
            </th>
            <th class="px-2 py-2" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="record in items"
            :key="record.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-2 py-2 text-n-slate-12">{{ contactName(record) }}</td>
            <td class="px-2 py-2">
              <span
                class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md"
                :class="
                  isWon(record)
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-ruby-3 text-n-ruby-11'
                "
              >
                <Icon
                  :icon="
                    isWon(record) ? 'i-lucide-trophy' : 'i-lucide-circle-x'
                  "
                  class="size-3"
                />
                {{
                  isWon(record)
                    ? t('KANBAN.OUTCOME.WON')
                    : t('KANBAN.OUTCOME.LOST')
                }}
              </span>
            </td>
            <td class="px-2 py-2 text-n-slate-11">{{ valueOf(record) }}</td>
            <td class="px-2 py-2 text-n-slate-11">
              {{ reasonOf(record) || '—' }}
            </td>
            <td class="px-2 py-2 text-n-slate-11">{{ closedAt(record) }}</td>
            <td class="px-2 py-2 text-right">
              <Button
                color="slate"
                variant="ghost"
                size="sm"
                icon="i-lucide-rotate-ccw"
                :label="t('KANBAN.OUTCOME.REOPEN')"
                @click="reopen(record)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
