<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { LOST_REASONS } from 'dashboard/routes/dashboard/kanban/config/stages';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

const dialogRef = ref(null);
const selectedReason = ref('');
const comment = ref('');
const confirmed = ref(false);

const open = () => {
  selectedReason.value = '';
  comment.value = '';
  confirmed.value = false;
  dialogRef.value?.open();
};

const onConfirm = () => {
  // Motivo é obrigatório; comentário é opcional.
  if (!selectedReason.value) return;
  confirmed.value = true;
  emit('submit', { reason: selectedReason.value, comment: comment.value });
  dialogRef.value?.close();
};

const onClose = () => {
  // Fechou sem confirmar (cancelar / clicar fora) => reverte a movimentação.
  if (!confirmed.value) emit('cancel');
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('KANBAN.LOST_DIALOG.TITLE')"
    :description="t('KANBAN.LOST_DIALOG.DESCRIPTION')"
    :confirm-button-label="t('KANBAN.LOST_DIALOG.CONFIRM')"
    :disable-confirm-button="!selectedReason"
    @confirm="onConfirm"
    @close="onClose"
  >
    <div class="flex flex-col gap-4">
      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.LOST_DIALOG.REASON_LABEL') }}
        </span>
        <select
          v-model="selectedReason"
          class="w-full h-10 px-3 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        >
          <option value="" disabled>
            {{ t('KANBAN.LOST_DIALOG.REASON_PLACEHOLDER') }}
          </option>
          <option
            v-for="reason in LOST_REASONS"
            :key="reason.value"
            :value="reason.value"
          >
            {{ reason.label }}
          </option>
        </select>
      </label>
      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('KANBAN.LOST_DIALOG.COMMENT_LABEL') }}
        </span>
        <textarea
          v-model="comment"
          rows="3"
          :placeholder="t('KANBAN.LOST_DIALOG.COMMENT_PLACEHOLDER')"
          class="w-full px-3 py-2 text-sm border rounded-lg resize-none bg-n-background border-n-weak text-n-slate-12 focus:border-n-brand"
        />
      </label>
    </div>
  </Dialog>
</template>
