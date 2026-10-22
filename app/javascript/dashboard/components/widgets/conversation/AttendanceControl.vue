<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useFintureAttendance } from 'dashboard/composables/useFintureAttendance';
import ButtonV4 from 'dashboard/components-next/button/Button.vue';
import ReturnToAiDialog from './ReturnToAiDialog.vue';

// Quem conduz a conversa (IA x humano) + a ação correspondente, sempre visível
// no cabeçalho. Só aparece em caixas com atendimento por IA ligado.
const props = defineProps({
  conversation: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const currentUser = useMapGetter('getCurrentUser');
const returnDialogRef = ref(null);

const { attendance, assignee, isEnabled, isAi, isHuman, isBusy, takeOver } =
  useFintureAttendance(computed(() => props.conversation));

const isMine = computed(
  () => !!assignee.value && assignee.value.id === currentUser.value?.id
);
const isResolved = computed(() => props.conversation.status === 'resolved');

const since = computed(() => {
  const at = attendance.value?.changed_at;
  if (!at) return '';
  const date = new Date(at * 1000);
  const time = date.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
  if (date.toDateString() === new Date().toDateString()) return time;
  return `${date.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} ${time}`;
});

const humanLabel = computed(() => {
  if (isMine.value) return t('CONVERSATION.ATTENDANCE.YOU_ATTENDING');
  if (assignee.value) {
    return t('CONVERSATION.ATTENDANCE.AGENT_ATTENDING', {
      name: assignee.value.available_name || assignee.value.name,
    });
  }
  return t('CONVERSATION.ATTENDANCE.WAITING_AGENT');
});

const statusTooltip = computed(() => {
  const name = attendance.value?.changed_by_name;
  if (!since.value || !name) return '';
  return t('CONVERSATION.ATTENDANCE.CHANGED_BY', { name, time: since.value });
});

const showTakeOver = computed(
  () => isAi.value || (isHuman.value && !assignee.value)
);
const showReturn = computed(() => isHuman.value && !isResolved.value);

const openReturnDialog = () => returnDialogRef.value?.open();
</script>

<template>
  <div v-if="isEnabled" class="flex items-center gap-2">
    <span
      v-tooltip="statusTooltip"
      class="inline-flex items-center gap-1.5 h-7 px-2.5 rounded-full text-xs font-medium whitespace-nowrap"
      :class="
        isAi ? 'bg-n-brand/10 text-n-blue-11' : 'bg-n-alpha-2 text-n-slate-12'
      "
    >
      <span
        class="size-3.5"
        :class="isAi ? 'i-lucide-bot' : 'i-lucide-user-round'"
      />
      <span class="hidden sm:inline">
        {{ isAi ? t('CONVERSATION.ATTENDANCE.AI_ATTENDING') : humanLabel }}
      </span>
      <span v-if="isHuman && since" class="hidden 2xl:inline text-n-slate-11">
        {{ t('CONVERSATION.ATTENDANCE.SINCE', { time: since }) }}
      </span>
    </span>

    <ButtonV4
      v-if="showTakeOver"
      size="sm"
      icon="i-lucide-hand"
      :label="t('CONVERSATION.ATTENDANCE.TAKE_OVER')"
      :is-loading="isBusy"
      :disabled="isBusy"
      @click="takeOver()"
    />
    <ButtonV4
      v-if="showReturn"
      v-tooltip="t('CONVERSATION.ATTENDANCE.RETURN_TOOLTIP')"
      size="sm"
      variant="faded"
      color="slate"
      icon="i-lucide-bot"
      :label="t('CONVERSATION.ATTENDANCE.RETURN')"
      :is-loading="isBusy"
      :disabled="isBusy"
      @click="openReturnDialog"
    />
    <ReturnToAiDialog ref="returnDialogRef" :conversation="conversation" />
  </div>
</template>
