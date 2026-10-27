<script setup>
// Lista que compõe um indicador da Home. Busca no MESMO endpoint e com os
// MESMOS filtros do resumo, então o total aqui é o total do cartão. Cada linha
// abre a conversa (as permissões são as do próprio Chatwoot).
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import FintureHomeAPI from 'dashboard/api/fintureHome';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { fmtDateTime, fmtElapsed } from '../helpers';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();

const dialogRef = ref(null);
const title = ref('');
const metric = ref('');
const result = ref(null);
const isLoading = ref(false);
const hasError = ref(false);
const nowEpoch = ref(0);

// Ganho, perdido e funil mostram o valor do lead (valor_potencial).
const showsValue = computed(() =>
  ['won', 'lost', 'pipeline_open'].includes(metric.value)
);
const currency = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  maximumFractionDigits: 0,
});

const totalLabel = computed(() => {
  const count = result.value?.total ?? 0;
  return t('FINTURE_HOME.LIST.TOTAL', { count }, count);
});

const isTruncated = computed(
  () => result.value && result.value.total > result.value.items.length
);

const whenLabel = item => {
  if (['won', 'lost'].includes(metric.value) && item.outcome_at)
    return t(`FINTURE_HOME.LIST.${metric.value.toUpperCase()}_AT`, {
      date: fmtDateTime(item.outcome_at),
    });
  if (metric.value === 'waiting_reply' && item.waiting_since)
    return t('FINTURE_HOME.LIST.WAITING_FOR', {
      time: fmtElapsed(item.waiting_since, nowEpoch.value),
    });
  if (['attending', 'unassigned', 'with_ai'].includes(metric.value))
    return t('FINTURE_HOME.LIST.IDLE_FOR', {
      time: fmtElapsed(item.last_activity_at, nowEpoch.value),
    });
  return t('FINTURE_HOME.LIST.CREATED', { date: fmtDateTime(item.created_at) });
};

const load = async filters => {
  isLoading.value = true;
  hasError.value = false;
  result.value = null;
  try {
    const { data } = await FintureHomeAPI.list(metric.value, filters);
    result.value = data;
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

const open = ({ metric: key, title: label, filters }) => {
  metric.value = key;
  title.value = label;
  nowEpoch.value = Math.floor(Date.now() / 1000);
  dialogRef.value?.open();
  load(filters);
};

const goToConversation = item => {
  dialogRef.value?.close();
  router.push({
    path: frontendURL(
      conversationUrl({ accountId: route.params.accountId, id: item.id })
    ),
  });
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    width="3xl"
    :show-confirm-button="false"
    :cancel-button-label="t('FINTURE_HOME.LIST.CLOSE')"
    overflow-y-auto
  >
    <div class="flex flex-col gap-3 min-h-[160px]">
      <div v-if="isLoading" class="flex items-center justify-center py-10">
        <Spinner class="size-5" />
      </div>
      <p v-else-if="hasError" class="py-6 text-sm text-center text-n-ruby-11">
        {{ t('FINTURE_HOME.LIST.ERROR') }}
      </p>
      <template v-else-if="result">
        <p class="text-xs text-n-slate-11">
          {{ totalLabel }}
          <template v-if="isTruncated">
            ·
            {{
              t('FINTURE_HOME.LIST.TRUNCATED', { shown: result.items.length })
            }}
          </template>
        </p>
        <p
          v-if="!result.items.length"
          class="py-6 text-sm text-center text-n-slate-11"
        >
          {{ t('FINTURE_HOME.LIST.EMPTY') }}
        </p>
        <ul
          v-else
          class="flex flex-col overflow-y-auto divide-y max-h-[60vh] divide-n-weak rounded-lg outline outline-1 -outline-offset-1 outline-n-weak"
        >
          <li v-for="item in result.items" :key="item.id">
            <button
              type="button"
              class="grid items-center w-full grid-cols-[minmax(0,2fr)_minmax(0,1.4fr)_minmax(0,1.2fr)_minmax(0,1.2fr)] gap-3 px-3 py-2.5 text-left transition-colors hover:bg-n-alpha-1"
              @click="goToConversation(item)"
            >
              <span class="flex flex-col min-w-0">
                <span class="text-sm font-medium truncate text-n-slate-12">
                  #{{ item.id }} · {{ item.contact || '—' }}
                </span>
                <span
                  v-if="showsValue"
                  class="text-xs truncate text-n-slate-11 tabular-nums"
                >
                  {{
                    item.value == null
                      ? t('FINTURE_HOME.LIST.NO_VALUE')
                      : currency.format(item.value)
                  }}
                </span>
              </span>
              <span class="flex flex-col min-w-0 text-xs text-n-slate-11">
                <span class="truncate">{{ item.inbox }}</span>
                <span class="truncate">{{ item.team }}</span>
              </span>
              <span class="text-xs truncate text-n-slate-11">
                {{ item.assignee || t('FINTURE_HOME.LIST.NO_ASSIGNEE') }}
              </span>
              <span class="text-xs text-right text-n-slate-11 tabular-nums">
                {{ whenLabel(item) }}
              </span>
            </button>
          </li>
        </ul>
      </template>
    </div>
  </Dialog>
</template>
