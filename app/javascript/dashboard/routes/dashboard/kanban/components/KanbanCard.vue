<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import {
  visibleCardFields,
  resolveFieldValue,
} from 'dashboard/routes/dashboard/kanban/config/cardFields';
import { NEXT_ACTION_ATTRIBUTE_KEY } from 'dashboard/routes/dashboard/kanban/config/stages';
import {
  QUOTE_ATTRIBUTE_KEY,
  FOLLOW_UP_DUE_ATTRIBUTE_KEY,
} from 'dashboard/routes/dashboard/kanban/config/quoteProducts';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import KanbanCardField from './KanbanCardField.vue';

const props = defineProps({
  conversation: {
    type: Object,
    required: true,
  },
  inboxName: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['open', 'won', 'lost']);

const route = useRoute();
const router = useRouter();

const fields = visibleCardFields();

// Conversa "enriquecida" para que `inbox.name` funcione como dot-path na config.
const enrichedConversation = computed(() => ({
  ...props.conversation,
  inbox: { name: props.inboxName },
}));

const contactName = computed(() => props.conversation?.meta?.sender?.name);
const contactThumbnail = computed(
  () => props.conversation?.meta?.sender?.thumbnail
);
const nextAction = computed(
  () => props.conversation?.custom_attributes?.[NEXT_ACTION_ATTRIBUTE_KEY]
);

// Espelhos do CRM Fase 1 (gravados pelo backend em custom_attributes).
const quoteSummary = computed(
  () => props.conversation?.custom_attributes?.[QUOTE_ATTRIBUTE_KEY]
);
const followUpDueAt = computed(() => {
  const epoch =
    props.conversation?.custom_attributes?.[FOLLOW_UP_DUE_ATTRIBUTE_KEY];
  return epoch ? epoch * 1000 : null;
});
const followUpOverdue = computed(
  () => followUpDueAt.value && followUpDueAt.value < Date.now()
);
const followUpLabel = computed(() => {
  if (!followUpDueAt.value) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(followUpDueAt.value));
});

const fieldValue = field =>
  resolveFieldValue(enrichedConversation.value, field);

const open = (intent = 'detail') =>
  emit('open', { conversation: props.conversation, intent });

const openConversation = e => {
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: props.conversation.id,
    })
  );
  if (e.metaKey || e.ctrlKey) {
    window.open(
      window.chatwootConfig.hostURL + path,
      '_blank',
      'noopener noreferrer nofollow'
    );
    return;
  }
  router.push({ path });
};

// Histórico do número: atendimentos anteriores colapsados neste card (o card é
// a conversa mais recente; estes são os demais). Mostra os 3 mais recentes;
// cada linha abre aquela conversa antiga.
const HISTORY_PREVIEW = 3;
const history = computed(() => props.conversation?.groupHistory || []);
const visibleHistory = computed(() => history.value.slice(0, HISTORY_PREVIEW));
const extraHistoryCount = computed(() =>
  Math.max(0, history.value.length - HISTORY_PREVIEW)
);

const openHistory = entry => {
  const path = frontendURL(
    conversationUrl({ accountId: route.params.accountId, id: entry.id })
  );
  router.push({ path });
};
</script>

<template>
  <div
    class="relative flex flex-col gap-2 p-3 mb-2 transition-shadow bg-n-solid-2 rounded-xl outline outline-1 -outline-offset-1 outline-n-container cursor-grab hover:shadow-md"
    role="button"
    tabindex="0"
    @click="open('detail')"
    @keydown.enter="open('detail')"
  >
    <div class="flex items-start gap-2">
      <Avatar
        :name="contactName"
        :src="contactThumbnail"
        :size="24"
        rounded-full
      />
      <div class="flex flex-col min-w-0 gap-1">
        <KanbanCardField
          v-for="field in fields"
          :key="field.key"
          :field="field"
          :value="fieldValue(field)"
        />
      </div>
    </div>
    <!-- Badges do CRM: resumo da cotação e follow-up (vencido em destaque). -->
    <div
      v-if="quoteSummary || followUpDueAt"
      class="flex flex-wrap items-center gap-x-2 gap-y-1"
    >
      <span
        v-if="quoteSummary"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded bg-n-alpha-1 text-n-slate-11"
        :title="$t('KANBAN.QUOTE.TITLE')"
      >
        <Icon icon="i-lucide-file-text" class="size-3 shrink-0" />
        <span class="truncate max-w-40">{{ quoteSummary }}</span>
      </span>
      <span
        v-if="followUpDueAt"
        class="inline-flex items-center gap-1 px-1.5 py-0.5 text-xs rounded"
        :class="
          followUpOverdue
            ? 'bg-n-ruby-3 text-n-ruby-11 font-medium'
            : 'bg-n-alpha-1 text-n-slate-11'
        "
        :title="$t('KANBAN.FOLLOW_UPS.TITLE')"
      >
        <Icon
          :icon="followUpOverdue ? 'i-lucide-bell-ring' : 'i-lucide-bell'"
          class="size-3 shrink-0"
        />
        {{ followUpLabel }}
      </span>
    </div>
    <!-- Dica de próxima ação, quando existir (discreta, no rodapé do card). -->
    <div
      v-if="nextAction"
      class="flex items-center gap-1 pt-1 mt-1 text-n-slate-11"
    >
      <Icon icon="i-lucide-arrow-right-circle" class="size-3 shrink-0" />
      <span class="text-xs truncate">{{ nextAction }}</span>
    </div>
    <!-- Histórico do número: atendimentos anteriores (colapsados neste card).
         Cada linha abre a conversa antiga; stop no click/pointerdown para não
         iniciar drag nem abrir o detalhe do card. -->
    <div
      v-if="conversation.groupCount > 1"
      class="pt-2 mt-1 border-t border-n-weak"
      @click.stop
    >
      <div class="flex items-center gap-1 mb-1 text-n-slate-10">
        <Icon icon="i-lucide-history" class="size-3 shrink-0" />
        <span class="text-[11px] font-medium uppercase tracking-wide">
          {{
            $t('KANBAN.CARD.HISTORY_TITLE', {
              count: conversation.groupCount - 1,
            })
          }}
        </span>
      </div>
      <ul class="flex flex-col gap-0.5">
        <li v-for="entry in visibleHistory" :key="entry.id">
          <button
            type="button"
            class="flex items-center w-full gap-1 text-xs text-left transition-colors rounded text-n-slate-11 hover:text-n-slate-12"
            :title="$t('KANBAN.CARD.HISTORY_OPEN_ENTRY')"
            @click.stop="openHistory(entry)"
            @pointerdown.stop
          >
            <Icon icon="i-lucide-corner-down-right" class="size-3 shrink-0" />
            <span class="truncate">{{ entry.label }}</span>
          </button>
        </li>
      </ul>
      <button
        v-if="extraHistoryCount"
        type="button"
        class="mt-0.5 text-[11px] text-n-slate-10 hover:text-n-slate-11"
        @click.stop="open('detail')"
        @pointerdown.stop
      >
        {{ $t('KANBAN.CARD.HISTORY_MORE', { count: extraHistoryCount }) }}
      </button>
    </div>
    <!-- Barra de ações fixa: sempre visível e autoexplicativa. Ganho/Perdido com
         rótulo (decisão do SDR); ações utilitárias como ícones com tooltip.
         stop em click E pointerdown para não iniciar drag nem abrir o detalhe. -->
    <div
      class="flex items-center gap-1 pt-2 mt-1 border-t border-n-weak"
      @click.stop
    >
      <button
        class="inline-flex items-center gap-1 h-7 px-2 rounded-lg text-xs font-medium text-n-teal-11 bg-n-teal-3 hover:bg-n-teal-4 transition-colors"
        :title="$t('KANBAN.CARD.MARK_WON')"
        @click.stop="emit('won', conversation)"
        @pointerdown.stop
      >
        <Icon icon="i-lucide-trophy" class="size-3.5 shrink-0" />
        {{ $t('KANBAN.OUTCOME.WON') }}
      </button>
      <button
        class="inline-flex items-center gap-1 h-7 px-2 rounded-lg text-xs font-medium text-n-ruby-11 bg-n-ruby-3 hover:bg-n-ruby-4 transition-colors"
        :title="$t('KANBAN.CARD.MARK_LOST')"
        @click.stop="emit('lost', conversation)"
        @pointerdown.stop
      >
        <Icon icon="i-lucide-circle-x" class="size-3.5 shrink-0" />
        {{ $t('KANBAN.OUTCOME.LOST') }}
      </button>
      <div class="flex items-center gap-0.5 ltr:ml-auto rtl:mr-auto">
        <button
          class="flex items-center justify-center rounded-lg size-7 text-n-slate-11 bg-n-alpha-1 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
          :title="$t('KANBAN.CARD.ADD_NOTE')"
          @click.stop="open('note')"
          @pointerdown.stop
        >
          <Icon icon="i-lucide-sticky-note" class="size-4" />
        </button>
        <button
          class="flex items-center justify-center rounded-lg size-7 text-n-slate-11 bg-n-alpha-1 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
          :title="$t('KANBAN.CARD.EDIT_NEXT_ACTION')"
          @click.stop="open('next-action')"
          @pointerdown.stop
        >
          <Icon icon="i-lucide-list-checks" class="size-4" />
        </button>
        <button
          class="flex items-center justify-center rounded-lg size-7 text-n-slate-11 bg-n-alpha-1 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
          :title="$t('KANBAN.CARD.OPEN_CONVERSATION')"
          @click.stop="openConversation"
          @pointerdown.stop
        >
          <Icon icon="i-lucide-external-link" class="size-4" />
        </button>
      </div>
    </div>
  </div>
</template>
