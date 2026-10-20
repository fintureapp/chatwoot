<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import FintureCrmApi from 'dashboard/api/fintureCrm';
import { lostReasonLabel } from 'dashboard/routes/dashboard/kanban/config/stages';
import { summaryStateOf } from 'dashboard/routes/dashboard/kanban/helper/historyGrouping';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Modal do Histórico: tudo de um contato em um lugar só — cada conversa (de
// qualquer caixa que o usuário enxerga) com quando abriu, quando fechou e o
// resumo gerado pela IA, mais o resumo geral do cliente (resumo_atendimentos).
// Fonte: contacts/:id/finture_timeline.
const props = defineProps({
  // Caixa ativa do Kanban: o reabrir recarrega o Histórico dela.
  inboxId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();
const route = useRoute();
const router = useRouter();

const dialogRef = ref(null);
const contact = ref({});
const entries = ref([]);
const isLoading = ref(false);
const hasError = ref(false);
const reopeningId = ref(null);

const load = async contactId => {
  isLoading.value = true;
  hasError.value = false;
  try {
    const { data } = await FintureCrmApi.getContactTimeline(contactId);
    contact.value = { ...contact.value, ...data.contact };
    entries.value = data.payload || [];
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

// `seed` é o contato da linha clicada (nome/telefone aparecem na hora, antes
// da resposta da API).
const open = seed => {
  contact.value = seed || {};
  entries.value = [];
  dialogRef.value?.open();
  if (seed?.id) load(seed.id);
};

const dateFormatter = new Intl.DateTimeFormat('pt-BR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});
const formatDate = epoch =>
  epoch ? dateFormatter.format(new Date(epoch * 1000)) : '';

const subtitle = computed(() =>
  [contact.value.phone_number, contact.value.email].filter(Boolean).join(' · ')
);

const closedCount = computed(
  () => entries.value.filter(entry => entry.closed_at).length
);

// Selo do atendimento: desfecho comercial > status da conversa.
const badgeOf = entry => {
  if (entry.outcome === 'won')
    return {
      label: t('KANBAN.OUTCOME.WON'),
      icon: 'i-lucide-trophy',
      class: 'bg-n-teal-3 text-n-teal-11',
    };
  if (entry.outcome === 'lost')
    return {
      label: t('KANBAN.OUTCOME.LOST'),
      icon: 'i-lucide-circle-x',
      class: 'bg-n-ruby-3 text-n-ruby-11',
    };
  if (entry.closed_at)
    return {
      label: t('KANBAN.HISTORY.TIMELINE.RESOLVED'),
      icon: 'i-lucide-check-check',
      class: 'bg-n-slate-3 text-n-slate-11',
    };
  return {
    label: t('KANBAN.HISTORY.TIMELINE.OPEN'),
    icon: 'i-lucide-circle-dot',
    class: 'bg-n-amber-3 text-n-amber-11',
  };
};

// "#123 · Caixa · Responsável"
const entryMeta = entry =>
  [`#${entry.id}`, entry.inbox_name, entry.assignee_name]
    .filter(Boolean)
    .join(' · ');

// "Aberta em … · fechada em …"
const entryDates = entry => {
  const parts = [
    t('KANBAN.HISTORY.TIMELINE.OPENED_AT', {
      date: formatDate(entry.created_at),
    }),
  ];
  if (entry.closed_at)
    parts.push(
      t('KANBAN.HISTORY.TIMELINE.CLOSED_AT', {
        date: formatDate(entry.closed_at),
      })
    );
  return parts.join(' · ');
};

const summaryLabels = computed(() => ({
  pending: t('KANBAN.HISTORY.SUMMARY_PENDING'),
  missing: t('KANBAN.HISTORY.SUMMARY_MISSING'),
  open: t('KANBAN.HISTORY.SUMMARY_OPEN'),
}));

const nowSeconds = () => Math.round(Date.now() / 1000);
const summaryState = entry =>
  summaryStateOf({
    resumo: entry.resumo,
    closedAt: entry.closed_at,
    now: nowSeconds(),
  });

const openConversation = entry => {
  const path = frontendURL(
    conversationUrl({ accountId: route.params.accountId, id: entry.id })
  );
  dialogRef.value?.close();
  router.push({ path });
};

const reopen = async entry => {
  reopeningId.value = entry.id;
  try {
    await store.dispatch('kanban/reopenLead', {
      conversationId: entry.id,
      inboxId: props.inboxId,
    });
    await load(contact.value.id);
  } catch {
    useAlert(t('KANBAN.ERRORS.UPDATE_OUTCOME'));
  } finally {
    reopeningId.value = null;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    :show-confirm-button="false"
    :cancel-button-label="t('KANBAN.HISTORY.TIMELINE.CLOSE')"
  >
    <div class="flex flex-col gap-5 -mt-2 [&_p]:mb-0">
      <!-- Cabeçalho do contato -->
      <div class="flex items-center gap-3">
        <Avatar
          :name="contact.name || ''"
          :src="contact.thumbnail || ''"
          :size="40"
          rounded-full
        />
        <div class="flex flex-col min-w-0">
          <h3 class="text-base font-medium truncate text-n-slate-12">
            {{ contact.name || '—' }}
          </h3>
          <p v-if="subtitle" class="text-sm truncate text-n-slate-11">
            {{ subtitle }}
          </p>
        </div>
      </div>

      <div v-if="isLoading && !entries.length" class="flex justify-center py-8">
        <Spinner />
      </div>
      <p v-else-if="hasError" class="py-6 text-sm text-center text-n-ruby-11">
        {{ t('KANBAN.HISTORY.TIMELINE.ERROR') }}
      </p>

      <div
        v-else
        class="flex flex-col gap-5 overflow-y-auto max-h-[60vh] ltr:pr-1 rtl:pl-1"
      >
        <!-- Resumo geral do cliente (rolante, todas as conversas) -->
        <section
          v-if="contact.resumo_atendimentos"
          class="flex flex-col gap-1.5 p-3 rounded-xl bg-n-alpha-1"
        >
          <span
            class="flex items-center gap-1.5 text-xs font-medium text-n-slate-11"
          >
            <Icon icon="i-lucide-sparkles" class="size-3.5" />
            {{ t('KANBAN.HISTORY.TIMELINE.CLIENT_SUMMARY') }}
          </span>
          <p class="text-sm whitespace-pre-line text-n-slate-12">
            {{ contact.resumo_atendimentos }}
          </p>
        </section>

        <!-- Linha do tempo: uma entrada por conversa -->
        <section class="flex flex-col gap-2">
          <span class="text-xs font-medium text-n-slate-11">
            {{
              t('KANBAN.HISTORY.TIMELINE.COUNT', {
                count: entries.length,
                closed: closedCount,
              })
            }}
          </span>
          <ol class="flex flex-col">
            <li
              v-for="(entry, index) in entries"
              :key="entry.id"
              class="relative flex gap-3 ltr:pl-1 rtl:pr-1"
            >
              <div class="flex flex-col items-center pt-1.5">
                <span class="rounded-full size-2.5 shrink-0 bg-n-slate-8" />
                <span
                  v-if="index < entries.length - 1"
                  class="flex-1 w-px mt-1 bg-n-weak"
                />
              </div>
              <div class="flex flex-col flex-1 min-w-0 gap-1.5 pb-4">
                <div class="flex flex-wrap items-center gap-2">
                  <span
                    class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded-md"
                    :class="badgeOf(entry).class"
                  >
                    <Icon :icon="badgeOf(entry).icon" class="size-3" />
                    {{ badgeOf(entry).label }}
                  </span>
                  <span class="text-xs text-n-slate-11">
                    {{ entryMeta(entry) }}
                  </span>
                </div>

                <p class="text-xs text-n-slate-11">{{ entryDates(entry) }}</p>

                <p
                  v-if="entry.outcome === 'lost' && entry.lost_reason"
                  class="text-xs text-n-slate-11"
                >
                  {{
                    t('KANBAN.HISTORY.TIMELINE.LOST_REASON', {
                      reason: lostReasonLabel(entry.lost_reason),
                    })
                  }}
                </p>

                <p
                  v-if="summaryState(entry) === 'ready'"
                  class="text-sm whitespace-pre-line text-n-slate-12"
                >
                  {{ entry.resumo }}
                </p>
                <p
                  v-else
                  class="flex items-center gap-1.5 text-xs italic text-n-slate-10"
                >
                  <Icon
                    v-if="summaryState(entry) === 'pending'"
                    icon="i-lucide-loader"
                    class="size-3.5"
                  />
                  {{ summaryLabels[summaryState(entry)] }}
                </p>

                <div class="flex items-center gap-1 -ml-2 rtl:-mr-2 rtl:ml-0">
                  <Button
                    type="button"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    icon="i-lucide-message-circle"
                    :label="t('KANBAN.HISTORY.TIMELINE.OPEN_CONVERSATION')"
                    @click="openConversation(entry)"
                  />
                  <Button
                    v-if="entry.outcome"
                    type="button"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    icon="i-lucide-rotate-ccw"
                    :label="t('KANBAN.OUTCOME.REOPEN')"
                    :is-loading="reopeningId === entry.id"
                    @click="reopen(entry)"
                  />
                </div>
              </div>
            </li>
          </ol>
        </section>
      </div>
    </div>
  </Dialog>
</template>
