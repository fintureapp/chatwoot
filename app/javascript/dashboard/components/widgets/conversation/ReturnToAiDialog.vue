<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFintureAttendance } from 'dashboard/composables/useFintureAttendance';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

// "Devolver à IA": motivo obrigatório + o que ficou pendente (vai para a IA
// retomar sem refazer a triagem). Só fecha quando o servidor confirmou.
const props = defineProps({
  conversation: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const dialogRef = ref(null);
const reason = ref('');
const pendingNotes = ref('');

const { isBusy, returnToAi } = useFintureAttendance(
  computed(() => props.conversation)
);

const canConfirm = computed(() => reason.value.trim().length > 0);

const open = () => {
  reason.value = '';
  pendingNotes.value = '';
  dialogRef.value?.open();
};

const onConfirm = async () => {
  if (!canConfirm.value) return;
  const ok = await returnToAi({
    reason: reason.value.trim(),
    pendingNotes: pendingNotes.value.trim(),
  });
  if (ok) dialogRef.value?.close();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CONVERSATION.ATTENDANCE.RETURN_DIALOG.TITLE')"
    :description="t('CONVERSATION.ATTENDANCE.RETURN_DIALOG.DESCRIPTION')"
    :confirm-button-label="t('CONVERSATION.ATTENDANCE.RETURN_DIALOG.CONFIRM')"
    :disable-confirm-button="!canConfirm || isBusy"
    :is-loading="isBusy"
    @confirm="onConfirm"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.ATTENDANCE.RETURN_DIALOG.REASON_LABEL') }}
        </span>
        <input
          v-model="reason"
          type="text"
          maxlength="255"
          :placeholder="
            t('CONVERSATION.ATTENDANCE.RETURN_DIALOG.REASON_PLACEHOLDER')
          "
          class="w-full h-10 px-3 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand !mb-0"
        />
      </label>
      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CONVERSATION.ATTENDANCE.RETURN_DIALOG.PENDING_LABEL') }}
        </span>
        <textarea
          v-model="pendingNotes"
          rows="3"
          :placeholder="
            t('CONVERSATION.ATTENDANCE.RETURN_DIALOG.PENDING_PLACEHOLDER')
          "
          class="w-full px-3 py-2 text-sm border rounded-lg resize-none bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand !mb-0"
        />
      </label>
    </div>
  </Dialog>
</template>
