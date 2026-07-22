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

const emit = defineEmits(['open']);

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
</script>

<template>
  <div
    class="relative flex flex-col gap-2 p-3 mb-2 transition-shadow group bg-n-solid-2 rounded-xl outline outline-1 -outline-offset-1 outline-n-container cursor-grab hover:shadow-md"
    role="button"
    tabindex="0"
    @click="open('detail')"
    @keydown.enter="open('detail')"
  >
    <!-- Ações rápidas (discretas, aparecem no hover). Param stop em click E pointerdown
         para não iniciar drag nem abrir o detalhe ao usá-las. -->
    <div
      class="absolute z-10 items-center hidden gap-0.5 top-2 ltr:right-2 rtl:left-2 group-hover:flex"
    >
      <button
        class="flex items-center justify-center rounded-md size-6 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="$t('KANBAN.CARD.ADD_NOTE')"
        @click.stop="open('note')"
        @pointerdown.stop
      >
        <Icon icon="i-lucide-sticky-note" class="size-4" />
      </button>
      <button
        class="flex items-center justify-center rounded-md size-6 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="$t('KANBAN.CARD.EDIT_NEXT_ACTION')"
        @click.stop="open('next-action')"
        @pointerdown.stop
      >
        <Icon icon="i-lucide-list-checks" class="size-4" />
      </button>
      <button
        class="flex items-center justify-center rounded-md size-6 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :title="$t('KANBAN.CARD.OPEN_CONVERSATION')"
        @click.stop="openConversation"
        @pointerdown.stop
      >
        <Icon icon="i-lucide-external-link" class="size-4" />
      </button>
    </div>
    <div class="flex items-start gap-2 ltr:pr-6 rtl:pl-6">
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
      class="flex items-center gap-1 pt-1 mt-1 border-t border-n-weak text-n-slate-11"
    >
      <Icon icon="i-lucide-arrow-right-circle" class="size-3 shrink-0" />
      <span class="text-xs truncate">{{ nextAction }}</span>
    </div>
  </div>
</template>
