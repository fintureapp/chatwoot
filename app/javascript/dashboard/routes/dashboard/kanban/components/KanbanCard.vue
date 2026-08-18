<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
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
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
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

const { t } = useI18n();
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

const goToConversation = () => {
  const path = frontendURL(
    conversationUrl({
      accountId: route.params.accountId,
      id: props.conversation.id,
    })
  );
  router.push({ path });
};

// Ações utilitárias do card, agora recolhidas num menu discreto ("⋯") no canto
// superior direito — antes eram 3 botões fixos poluindo o rodapé do card.
const [isMenuOpen, toggleMenu] = useToggle(false);
const menuItems = computed(() => [
  {
    icon: 'i-lucide-sticky-note',
    label: t('KANBAN.CARD.ADD_NOTE'),
    action: 'note',
    value: 'note',
  },
  {
    icon: 'i-lucide-list-checks',
    label: t('KANBAN.CARD.EDIT_NEXT_ACTION'),
    action: 'next-action',
    value: 'next-action',
  },
  {
    icon: 'i-lucide-external-link',
    label: t('KANBAN.CARD.OPEN_CONVERSATION'),
    action: 'open-conversation',
    value: 'open-conversation',
  },
]);

const onMenuAction = ({ action }) => {
  toggleMenu(false);
  if (action === 'note') open('note');
  else if (action === 'next-action') open('next-action');
  else if (action === 'open-conversation') goToConversation();
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
    <!-- Menu discreto de ações (⋯) no canto superior direito. stop no click E
         pointerdown para não iniciar drag nem abrir o detalhe do card. -->
    <div
      v-on-clickaway="() => toggleMenu(false)"
      class="absolute z-10 ltr:right-2 rtl:left-2 top-2"
      @click.stop
      @pointerdown.stop
    >
      <button
        type="button"
        class="flex items-center justify-center rounded-lg size-7 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
        :class="{ 'bg-n-alpha-2 text-n-slate-12': isMenuOpen }"
        :title="$t('KANBAN.CARD.MORE_ACTIONS')"
        @click.stop="toggleMenu()"
      >
        <Icon icon="i-lucide-more-horizontal" class="size-4" />
      </button>
      <DropdownMenu
        v-if="isMenuOpen"
        :menu-items="menuItems"
        class="mt-1 ltr:right-0 rtl:left-0 top-full"
        @action="onMenuAction"
      />
    </div>

    <div class="flex items-start gap-2 ltr:pr-7 rtl:pl-7">
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
    <!-- Barra de desfecho: Ganho/Perdido com rótulo (decisão do SDR). As ações
         utilitárias foram para o menu "⋯" no topo. stop em click E pointerdown
         para não iniciar drag nem abrir o detalhe. -->
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
    </div>
  </div>
</template>
