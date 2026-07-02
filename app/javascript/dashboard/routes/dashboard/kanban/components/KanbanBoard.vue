<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import {
  KANBAN_STAGES,
  WON_STAGE,
  LOST_STAGE,
  resolveStage,
} from 'dashboard/routes/dashboard/kanban/config/stages';

import KanbanColumn from './KanbanColumn.vue';
import LostReasonDialog from './LostReasonDialog.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useStore();
const { t } = useI18n();

const records = useMapGetter('kanban/getRecords');
const selectedInboxIds = useMapGetter('kanban/getSelectedInboxIds');
const inboxes = useMapGetter('inboxes/getInboxes');

const localColumns = ref([]);

const lostDialogRef = ref(null);
const wonDialogRef = ref(null);
const pendingLost = ref(null);
const pendingWon = ref(null);
const wonConfirmed = ref(false);

const inboxNames = computed(() => {
  const map = {};
  inboxes.value.forEach(inbox => {
    map[inbox.id] = inbox.name;
  });
  return map;
});

const rebuildColumns = () => {
  const selected = selectedInboxIds.value;
  const filtered = records.value.filter(record =>
    selected.includes(record.inbox_id)
  );
  localColumns.value = KANBAN_STAGES.map(stage => ({
    stage,
    cards: filtered.filter(record => resolveStage(record) === stage.value),
  }));
};

// Reconstrói apenas quando o conjunto de conversas ou a seleção muda (fetch),
// nunca em atualizações de atributo em memória — evita "piscar" o card após o drop.
const columnsSignature = computed(
  () =>
    `${records.value.map(record => record.id).join(',')}|${selectedInboxIds.value.join(',')}`
);
watch(columnsSignature, rebuildColumns, { immediate: true });

const persistStage = async (conversation, stage, extra = {}) => {
  try {
    await store.dispatch('kanban/updateStage', {
      conversationId: conversation.id,
      stage,
      ...extra,
    });
  } catch {
    rebuildColumns();
    useAlert(t('KANBAN.ERRORS.UPDATE_STAGE'));
  }
};

const handleChange = (stageValue, event) => {
  // Só reagimos ao card que ENTRA numa coluna (destino).
  if (!event.added) return;
  const conversation = event.added.element;

  if (stageValue === LOST_STAGE) {
    pendingLost.value = conversation;
    lostDialogRef.value.open();
    return;
  }
  if (stageValue === WON_STAGE) {
    pendingWon.value = conversation;
    wonConfirmed.value = false;
    wonDialogRef.value.open();
    return;
  }
  persistStage(conversation, stageValue);
};

const onLostSubmit = ({ reason, comment }) => {
  const conversation = pendingLost.value;
  pendingLost.value = null;
  persistStage(conversation, LOST_STAGE, {
    lostReason: reason,
    lostComment: comment,
  });
};

const onLostCancel = () => {
  pendingLost.value = null;
  rebuildColumns();
};

const onWonConfirm = () => {
  wonConfirmed.value = true;
  const conversation = pendingWon.value;
  pendingWon.value = null;
  wonDialogRef.value.close();
  persistStage(conversation, WON_STAGE);
};

const onWonClose = () => {
  if (!wonConfirmed.value) rebuildColumns();
};
</script>

<template>
  <div class="flex gap-4 px-6 py-4 overflow-x-auto min-h-0">
    <KanbanColumn
      v-for="column in localColumns"
      :key="column.stage.value"
      :stage="column.stage"
      :cards="column.cards"
      :inbox-names="inboxNames"
      @change="handleChange(column.stage.value, $event)"
    />

    <LostReasonDialog
      ref="lostDialogRef"
      @submit="onLostSubmit"
      @cancel="onLostCancel"
    />

    <Dialog
      ref="wonDialogRef"
      type="edit"
      :title="t('KANBAN.WON_DIALOG.TITLE')"
      :description="t('KANBAN.WON_DIALOG.DESCRIPTION')"
      :confirm-button-label="t('KANBAN.WON_DIALOG.CONFIRM')"
      @confirm="onWonConfirm"
      @close="onWonClose"
    />
  </div>
</template>
