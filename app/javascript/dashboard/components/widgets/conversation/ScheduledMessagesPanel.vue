<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ScheduleMessageDialog from './ScheduleMessageDialog.vue';

// Mensagens agendadas da conversa, logo acima da caixa de resposta. Pendentes
// sempre visíveis (autor, horário, prévia), com editar/cancelar; enviadas,
// canceladas e falhas ficam recolhidas num histórico. Recarrega quando chega
// mensagem nova na conversa (o envio agendado vira uma mensagem normal).
const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const inboxId = computed(() => store.getters.getSelectedChat?.inbox_id);

const showHistory = ref(false);
const confirmingId = ref(null);
const dialogRef = ref(null);

const items = computed(() =>
  store.getters['fintureScheduledMessages/getForConversation'](
    props.conversationId
  )
);
const pending = computed(() =>
  items.value.filter(item => item.status === 'pending')
);
const history = computed(() =>
  items.value.filter(item => item.status !== 'pending')
);

const load = () => {
  if (!props.conversationId) return;
  store.dispatch('fintureScheduledMessages/fetch', {
    conversationId: props.conversationId,
  });
};

watch(() => props.conversationId, load, { immediate: true });

// Mensagem nova na conversa (inclusive a enviada pelo agendamento): recarrega.
const messageCount = computed(
  () => store.getters.getSelectedChat?.messages?.length || 0
);
watch(messageCount, load);

const statusClass = {
  pending: 'bg-n-amber-3 text-n-amber-11',
  processing: 'bg-n-blue-3 text-n-blue-11',
  sent: 'bg-n-teal-3 text-n-teal-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
  cancelled: 'bg-n-alpha-2 text-n-slate-11',
};

const detailOf = item => {
  if (item.status === 'failed' && item.error_message) return item.error_message;
  if (item.status === 'cancelled' && item.cancel_reason) {
    return t(`CONVERSATION.SCHEDULE.CANCEL_REASON.${item.cancel_reason}`);
  }
  return '';
};

const edit = item => dialogRef.value?.open({ item });

const cancel = async item => {
  if (confirmingId.value !== item.id) {
    confirmingId.value = item.id;
    return;
  }
  confirmingId.value = null;
  try {
    await store.dispatch('fintureScheduledMessages/cancel', {
      conversationId: props.conversationId,
      id: item.id,
    });
    useAlert(t('CONVERSATION.SCHEDULE.CANCELLED'));
  } catch (e) {
    useAlert(e?.response?.data?.message || t('CONVERSATION.SCHEDULE.ERROR'));
  }
};
</script>

<template>
  <div>
    <div
      v-if="pending.length || history.length"
      class="flex flex-col gap-1.5 px-2 pb-1"
    >
      <div class="flex items-center gap-2 px-1 text-xs text-n-slate-11">
        <Icon icon="i-lucide-clock" class="size-3.5" />
        <span class="font-medium">
          {{ t('CONVERSATION.SCHEDULE.PANEL_TITLE') }}
        </span>
        <span v-if="pending.length">
          {{
            t('CONVERSATION.SCHEDULE.PANEL_PENDING', { count: pending.length })
          }}
        </span>
        <button
          v-if="history.length"
          type="button"
          class="ltr:ml-auto rtl:mr-auto text-n-slate-10 hover:text-n-slate-12"
          @click="showHistory = !showHistory"
        >
          {{
            showHistory
              ? t('CONVERSATION.SCHEDULE.HIDE_HISTORY')
              : t('CONVERSATION.SCHEDULE.SHOW_HISTORY')
          }}
        </button>
      </div>

      <ul class="flex flex-col gap-1.5 max-h-48 overflow-y-auto">
        <li
          v-for="item in showHistory ? items : pending"
          :key="item.id"
          class="flex items-start gap-2 px-3 py-2 border rounded-lg bg-n-solid-1 border-n-weak"
        >
          <Avatar
            :name="item.user?.name || ''"
            :src="item.user?.thumbnail || ''"
            :size="24"
            rounded-full
          />
          <div class="flex flex-col flex-1 min-w-0 gap-0.5">
            <div class="flex flex-wrap items-center gap-2 text-xs">
              <span class="font-medium text-n-slate-12">
                {{ item.scheduled_at_label }}
              </span>
              <span
                class="px-1.5 py-0.5 rounded-md"
                :class="statusClass[item.status]"
              >
                {{ t(`CONVERSATION.SCHEDULE.STATUS.${item.status}`) }}
              </span>
              <span
                v-if="item.kind === 'template'"
                class="px-1.5 py-0.5 rounded-md bg-n-teal-3 text-n-teal-11"
              >
                {{
                  t('CONVERSATION.SCHEDULE.TEMPLATE_BADGE', {
                    name: item.template_params?.name || '',
                  })
                }}
              </span>
              <span v-if="item.user" class="text-n-slate-10">
                {{ t('CONVERSATION.SCHEDULE.BY', { name: item.user.name }) }}
              </span>
            </div>
            <p class="text-sm line-clamp-2 text-n-slate-11 whitespace-pre-line">
              {{ item.content }}
            </p>
            <p v-if="detailOf(item)" class="text-xs text-n-slate-10">
              {{ detailOf(item) }}
            </p>
          </div>
          <div v-if="item.status === 'pending'" class="flex items-center gap-1">
            <button
              type="button"
              class="px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
              @click="edit(item)"
            >
              {{ t('CONVERSATION.SCHEDULE.EDIT') }}
            </button>
            <button
              type="button"
              class="px-2 py-1 text-xs rounded-md"
              :class="
                confirmingId === item.id
                  ? 'bg-n-ruby-9 text-white'
                  : 'text-n-ruby-11 hover:bg-n-ruby-3'
              "
              @click="cancel(item)"
            >
              {{
                confirmingId === item.id
                  ? t('CONVERSATION.SCHEDULE.CANCEL_ITEM_CONFIRM', {
                      time: item.scheduled_at_label,
                    })
                  : t('CONVERSATION.SCHEDULE.CANCEL_ITEM')
              }}
            </button>
          </div>
        </li>
      </ul>
    </div>
    <ScheduleMessageDialog
      ref="dialogRef"
      :conversation-id="conversationId"
      :inbox-id="inboxId"
    />
  </div>
</template>
