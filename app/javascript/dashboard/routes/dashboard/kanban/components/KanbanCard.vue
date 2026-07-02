<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import {
  visibleCardFields,
  resolveFieldValue,
} from 'dashboard/routes/dashboard/kanban/config/cardFields';

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

const fieldValue = field => resolveFieldValue(enrichedConversation.value, field);

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
    class="relative flex flex-col gap-2 p-3 mb-2 transition-shadow bg-n-solid-2 rounded-xl outline outline-1 -outline-offset-1 outline-n-container cursor-grab hover:shadow-md"
  >
    <button
      class="absolute z-10 flex items-center justify-center rounded-md top-2 ltr:right-2 rtl:left-2 size-6 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
      :title="$t('KANBAN.CARD.OPEN_CONVERSATION')"
      @click.stop="openConversation"
    >
      <Icon icon="i-lucide-external-link" class="size-4" />
    </button>
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
  </div>
</template>
