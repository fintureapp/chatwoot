<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { useStore } from 'dashboard/composables/store';
import { lostReasonLabel } from 'dashboard/routes/dashboard/kanban/config/stages';
import {
  groupHistoryByContact,
  summaryStateOf,
} from 'dashboard/routes/dashboard/kanban/helper/historyGrouping';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';
import ContactHistoryDialog from './ContactHistoryDialog.vue';

// Histórico da caixa ativa, agrupado por CONTATO (uma linha por número). No
// COMERCIAL, leads fechados por desfecho (ganho/perdido), filtráveis; no
// OPERACIONAL, demandas resolvidas com o resumo da IA (sdr_resumo). Busca por
// nome/e-mail/telefone no servidor (conversations/kanban_history). Clicar na
// linha abre o modal com todas as conversas do contato e seus resumos.
const props = defineProps({
  inboxId: {
    type: [Number, String],
    default: null,
  },
  kanbanType: {
    type: String,
    default: 'comercial',
  },
});

const isOperational = computed(() => props.kanbanType === 'operacional');

const store = useStore();
const { t } = useI18n();

const query = ref('');
const outcome = ref('');
const dialogRef = ref(null);

const items = computed(() =>
  store.getters['kanban/getHistoryForInbox'](props.inboxId)
);
const uiFlags = computed(() => store.getters['kanban/getHistoryUIFlags']);
const groups = computed(() => groupHistoryByContact(items.value));
const hasFilters = computed(
  () => !!query.value.trim() || (!isOperational.value && !!outcome.value)
);

const load = () => {
  if (!props.inboxId) return;
  store.dispatch('kanban/fetchHistory', {
    inboxId: props.inboxId,
    filters: {
      query: query.value.trim(),
      outcome: isOperational.value ? '' : outcome.value,
    },
  });
};
const debouncedLoad = useDebounceFn(load, 300);

watch(() => props.inboxId, load, { immediate: true });
watch(outcome, load);
watch(query, debouncedLoad);

const outcomeOptions = computed(() => [
  { value: '', label: t('KANBAN.HISTORY.FILTER_ALL') },
  { value: 'won', label: t('KANBAN.HISTORY.FILTER_WON') },
  { value: 'lost', label: t('KANBAN.HISTORY.FILTER_LOST') },
]);

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

const formatDate = epoch =>
  epoch ? dateFormatter.format(new Date(epoch * 1000)) : '';

const isWon = record => record.custom_attributes?.sdr_outcome === 'won';

const valueOf = record => {
  const value = Number(record.custom_attributes?.valor_potencial);
  return value ? currencyFormatter.format(value) : '';
};

const reasonOf = record =>
  isWon(record)
    ? ''
    : lostReasonLabel(record.custom_attributes?.sdr_lost_reason);

// Detalhe do último fechamento na linha (comercial): valor ou motivo da perda.
const latestDetail = group =>
  [valueOf(group.latest), reasonOf(group.latest)].filter(Boolean).join(' · ');

const resumoOf = record => record.custom_attributes?.sdr_resumo || '';
const nowSeconds = () => Math.round(Date.now() / 1000);
const latestSummaryState = group =>
  summaryStateOf({
    resumo: resumoOf(group.latest),
    closedAt: group.lastClosedAt,
    now: nowSeconds(),
  });

const summaryLabels = computed(() => ({
  pending: t('KANBAN.HISTORY.SUMMARY_PENDING'),
  missing: t('KANBAN.HISTORY.SUMMARY_MISSING'),
  open: t('KANBAN.HISTORY.SUMMARY_OPEN'),
}));

const countLabel = computed(() => {
  const counts = { contacts: groups.value.length, count: items.value.length };
  return isOperational.value
    ? t('KANBAN.HISTORY.COUNT_GROUPED_OP', counts)
    : t('KANBAN.HISTORY.COUNT_GROUPED', counts);
});

const emptyTitle = computed(() => {
  if (hasFilters.value) return t('KANBAN.HISTORY.EMPTY_SEARCH_TITLE');
  return isOperational.value
    ? t('KANBAN.HISTORY.EMPTY_TITLE_OP')
    : t('KANBAN.HISTORY.EMPTY_TITLE');
});
const emptySubtitle = computed(() => {
  if (hasFilters.value) return t('KANBAN.HISTORY.EMPTY_SEARCH_SUBTITLE');
  return isOperational.value
    ? t('KANBAN.HISTORY.EMPTY_SUBTITLE_OP')
    : t('KANBAN.HISTORY.EMPTY_SUBTITLE');
});

const openContact = group => {
  dialogRef.value?.open({ ...group.contact });
};
</script>

<template>
  <div class="flex flex-col flex-1 min-h-0 px-4 py-3">
    <div class="flex flex-wrap items-center gap-2 mb-3">
      <div class="relative">
        <Icon
          icon="i-lucide-search"
          class="absolute -translate-y-1/2 size-4 text-n-slate-10 top-1/2 ltr:left-2.5 rtl:right-2.5"
        />
        <input
          v-model="query"
          type="search"
          :placeholder="t('KANBAN.HISTORY.SEARCH_PLACEHOLDER')"
          class="reset-base h-8 text-sm border rounded-lg w-72 ltr:pl-8 rtl:pr-8 ltr:pr-2.5 rtl:pl-2.5 bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        />
      </div>

      <!-- Comercial: filtra pelo desfecho -->
      <div
        v-if="!isOperational"
        class="flex items-center gap-0.5 p-0.5 rounded-lg bg-n-alpha-1"
        role="group"
      >
        <button
          v-for="option in outcomeOptions"
          :key="option.value"
          type="button"
          class="px-2.5 h-7 text-xs rounded-md transition-colors"
          :class="
            outcome === option.value
              ? 'bg-n-solid-1 text-n-slate-12 shadow-sm font-medium'
              : 'text-n-slate-11 hover:text-n-slate-12'
          "
          :aria-pressed="outcome === option.value"
          @click="outcome = option.value"
        >
          {{ option.label }}
        </button>
      </div>

      <div class="flex items-center gap-2 ltr:ml-auto rtl:mr-auto">
        <p class="text-sm text-n-slate-11">{{ countLabel }}</p>
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
    </div>

    <EmptyStateLayout
      v-if="!groups.length"
      class="flex-1 min-h-0"
      :title="emptyTitle"
      :subtitle="emptySubtitle"
      :show-backdrop="false"
    />

    <ul
      v-else
      class="flex flex-col flex-1 min-h-0 gap-2 overflow-y-auto [&_p]:mb-0"
    >
      <li v-for="group in groups" :key="group.key">
        <button
          type="button"
          class="flex items-start w-full gap-3 p-3 transition-colors rounded-xl text-start bg-n-solid-1 outline outline-1 -outline-offset-1 outline-n-weak hover:bg-n-alpha-1"
          @click="openContact(group)"
        >
          <Avatar
            :name="group.contact.name || ''"
            :src="group.contact.thumbnail || ''"
            :size="32"
            rounded-full
          />

          <div class="flex flex-col flex-1 min-w-0 gap-1">
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ group.contact.name || '—' }}
              </span>
              <span
                v-if="group.count > 1"
                class="px-1.5 py-0.5 text-xs rounded-md shrink-0 bg-n-alpha-2 text-n-slate-11"
              >
                {{ t('KANBAN.HISTORY.ATTENDANCES', { count: group.count }) }}
              </span>
            </div>

            <span
              v-if="group.contact.phone_number"
              class="text-xs text-n-slate-10"
            >
              {{ group.contact.phone_number }}
            </span>

            <!-- Comercial: último desfecho + valor/motivo -->
            <div
              v-if="!isOperational"
              class="flex flex-wrap items-center gap-2"
            >
              <span
                class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md"
                :class="
                  isWon(group.latest)
                    ? 'bg-n-teal-3 text-n-teal-11'
                    : 'bg-n-ruby-3 text-n-ruby-11'
                "
              >
                <Icon
                  :icon="
                    isWon(group.latest)
                      ? 'i-lucide-trophy'
                      : 'i-lucide-circle-x'
                  "
                  class="size-3"
                />
                {{
                  isWon(group.latest)
                    ? t('KANBAN.OUTCOME.WON')
                    : t('KANBAN.OUTCOME.LOST')
                }}
              </span>
              <span v-if="latestDetail(group)" class="text-xs text-n-slate-11">
                {{ latestDetail(group) }}
              </span>
            </div>

            <!-- Operacional: resumo do último atendimento -->
            <template v-else>
              <p
                v-if="latestSummaryState(group) === 'ready'"
                class="text-sm line-clamp-2 text-n-slate-11"
              >
                {{ resumoOf(group.latest) }}
              </p>
              <p
                v-else
                class="flex items-center gap-1.5 text-xs italic text-n-slate-10"
              >
                <Icon
                  v-if="latestSummaryState(group) === 'pending'"
                  icon="i-lucide-loader"
                  class="size-3.5"
                />
                {{ summaryLabels[latestSummaryState(group)] }}
              </p>
            </template>
          </div>

          <div class="flex items-center gap-1 shrink-0">
            <span class="text-xs text-n-slate-10">
              {{ formatDate(group.lastClosedAt) }}
            </span>
            <Icon
              icon="i-lucide-chevron-right"
              class="size-4 text-n-slate-10 rtl:rotate-180"
            />
          </div>
        </button>
      </li>
    </ul>

    <ContactHistoryDialog ref="dialogRef" :inbox-id="inboxId" />
  </div>
</template>
