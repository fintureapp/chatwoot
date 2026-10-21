<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// Agendar (ou editar o agendamento de) uma mensagem da conversa. Data/hora são
// hora de parede em America/Sao_Paulo — o servidor interpreta nesse fuso, então
// o resultado não depende do fuso do navegador do operador.
const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const emit = defineEmits(['scheduled', 'updated']);

const TIMEZONE = 'America/Sao_Paulo';
const store = useStore();
const { t } = useI18n();

const dialogRef = ref(null);
const editing = ref(null); // item existente (edição) ou null (novo)
const content = ref('');
const date = ref('');
const time = ref('');
const cancelOnReply = ref(true);
const error = ref('');

const isSaving = computed(
  () => store.getters['fintureScheduledMessages/getUIFlags'].isSaving
);
const meta = computed(() =>
  store.getters['fintureScheduledMessages/getMeta'](props.conversationId)
);

// "YYYY-MM-DDTHH:mm" de um instante, na hora de parede de São Paulo.
const toLocalWall = instant => {
  const parts = new Intl.DateTimeFormat('sv-SE', {
    timeZone: TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(instant);
  return parts.replace(' ', 'T');
};

const nowWall = () => toLocalWall(new Date());
const scheduledWall = computed(() =>
  date.value && time.value ? `${date.value}T${time.value}` : ''
);

const labelFormatter = new Intl.DateTimeFormat('pt-BR', {
  timeZone: TIMEZONE,
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

// Aviso da janela do canal (WhatsApp 24h etc.), calculado pelo servidor.
const windowWarning = computed(() => {
  const closesAt = meta.value?.messaging_window_closes_at;
  if (!closesAt || !scheduledWall.value) return '';
  const closesWall = toLocalWall(new Date(closesAt));
  if (closesWall < nowWall())
    return t('CONVERSATION.SCHEDULE.WINDOW_CLOSED_WARNING');
  if (scheduledWall.value > closesWall) {
    return t('CONVERSATION.SCHEDULE.WINDOW_WARNING', {
      time: labelFormatter.format(new Date(closesAt)),
    });
  }
  return '';
});

const open = ({ message = '', item = null } = {}) => {
  editing.value = item;
  error.value = '';
  if (item) {
    content.value = item.content;
    [date.value, time.value] = item.scheduled_at_local.split('T');
    cancelOnReply.value = item.cancel_on_reply;
  } else {
    content.value = message;
    // Sugestão: daqui a 1 hora (hora de São Paulo).
    const suggestion = toLocalWall(new Date(Date.now() + 60 * 60 * 1000));
    [date.value, time.value] = suggestion.split('T');
    cancelOnReply.value = true;
  }
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const validate = () => {
  if (!content.value.trim()) return t('CONVERSATION.SCHEDULE.EMPTY_ERROR');
  if (!scheduledWall.value || scheduledWall.value <= nowWall()) {
    return t('CONVERSATION.SCHEDULE.PAST_ERROR');
  }
  return '';
};

const submit = async () => {
  error.value = validate();
  if (error.value) return;
  const payload = {
    content: content.value,
    scheduled_at: scheduledWall.value,
    cancel_on_reply: cancelOnReply.value,
  };
  try {
    if (editing.value) {
      const item = await store.dispatch('fintureScheduledMessages/update', {
        conversationId: props.conversationId,
        id: editing.value.id,
        payload,
      });
      useAlert(
        t('CONVERSATION.SCHEDULE.UPDATED', { time: item.scheduled_at_label })
      );
      emit('updated', item);
    } else {
      const item = await store.dispatch('fintureScheduledMessages/create', {
        conversationId: props.conversationId,
        payload,
      });
      useAlert(
        t('CONVERSATION.SCHEDULE.SUCCESS', { time: item.scheduled_at_label })
      );
      emit('scheduled', item);
    }
    close();
  } catch (e) {
    error.value =
      e?.response?.data?.message ||
      e?.response?.data?.error ||
      t('CONVERSATION.SCHEDULE.ERROR');
  }
};

defineExpose({ open, close });

const inputClass =
  'h-9 px-2.5 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand';
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      editing
        ? t('CONVERSATION.SCHEDULE.EDIT_TITLE')
        : t('CONVERSATION.SCHEDULE.TITLE')
    "
    :confirm-button-label="
      editing
        ? t('CONVERSATION.SCHEDULE.SAVE')
        : t('CONVERSATION.SCHEDULE.CONFIRM')
    "
    :cancel-button-label="t('CONVERSATION.SCHEDULE.CANCEL')"
    :is-loading="isSaving"
    :disable-confirm-button="isSaving"
    width="lg"
    overflow-y-auto
    @confirm="submit"
  >
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-2 gap-3">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION.SCHEDULE.DATE') }}
          <input v-model="date" type="date" :class="inputClass" />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION.SCHEDULE.TIME') }}
          <input v-model="time" type="time" :class="inputClass" />
        </label>
      </div>
      <p class="text-xs text-n-slate-10">
        {{ t('CONVERSATION.SCHEDULE.TIMEZONE_NOTE') }}
      </p>

      <label class="flex flex-col gap-1 text-xs text-n-slate-11">
        {{ t('CONVERSATION.SCHEDULE.PREVIEW') }}
        <textarea
          v-model="content"
          rows="5"
          class="px-2.5 py-2 text-sm border rounded-lg resize-y bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        />
      </label>

      <label class="flex items-start gap-2 text-sm text-n-slate-12">
        <input v-model="cancelOnReply" type="checkbox" class="mt-1" />
        <span>{{ t('CONVERSATION.SCHEDULE.CANCEL_ON_REPLY') }}</span>
      </label>

      <p
        v-if="windowWarning"
        class="px-3 py-2 text-xs rounded-lg bg-n-amber-3 text-n-amber-12"
      >
        {{ windowWarning }}
      </p>

      <p class="text-xs leading-snug text-n-slate-10">
        {{ t('CONVERSATION.SCHEDULE.POLICY_NOTE') }}
      </p>

      <p v-if="error" class="text-sm text-n-ruby-11">{{ error }}</p>
    </div>
  </Dialog>
</template>
